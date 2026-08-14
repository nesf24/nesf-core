import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Error carrying the API's human-readable message so screens can show exactly
/// what the server said rather than a generic failure.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.fields});
  final int statusCode;
  final String message;

  /// Per-field validation messages from the server, keyed by field name.
  final Map<String, String>? fields;

  bool get isAuthError => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin HTTP client for the NESF Core API.
///
/// Holds the access/refresh token pair, persists it, and transparently refreshes
/// a expired access token once before failing a request — staff on patchy rural
/// connections should not be bounced to the login screen mid-form.
class Api {
  static const _kAccess = 'nesf_access_token';
  static const _kRefresh = 'nesf_refresh_token';

  String? _accessToken;
  String? _refreshToken;

  /// Called when refreshing fails, so the app can return to the login screen.
  VoidCallback? onSessionExpired;

  bool get hasSession => _refreshToken != null;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_kAccess);
    _refreshToken = prefs.getString(_kRefresh);
  }

  Future<void> _saveSession(String? access, String? refresh) async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = access;
    if (access == null) {
      await prefs.remove(_kAccess);
    } else {
      await prefs.setString(_kAccess, access);
    }
    if (refresh != null) {
      _refreshToken = refresh;
      await prefs.setString(_kRefresh, refresh);
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = null;
    _refreshToken = null;
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  /// Headers for loading a private file with `Image.network`.
  ///
  /// Uploaded selfies, signatures and receipts are not publicly readable, so the
  /// image request has to carry the session token like any other API call.
  Map<String, String> get mediaHeaders =>
      _accessToken == null ? const {} : {'Authorization': 'Bearer $_accessToken'};

  /// Refreshes the access token if one is not currently held.
  ///
  /// `Image.network` cannot retry a 401 the way [_send] does, so screens showing
  /// private images call this first to reduce the chance of loading with a token
  /// that has just expired.
  Future<void> ensureFreshToken() async {
    if (_accessToken == null && _refreshToken != null) await _refresh();
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, '${e.value}'));
    return Uri.parse('${AppConfig.apiUrl}$path').replace(
      queryParameters: cleaned == null || cleaned.isEmpty
          ? null
          : Map.fromEntries(cleaned),
    );
  }

  /// Exchanges the refresh token for a new access token.
  /// Returns false when the refresh token itself is no longer valid.
  Future<bool> _refresh() async {
    if (_refreshToken == null) return false;
    try {
      final res = await http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await _saveSession(body['access_token'] as String?, null);
      return true;
    } catch (_) {
      return false;
    }
  }

  Never _throwFor(http.Response res) {
    String message;
    Map<String, String>? fields;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      message = (body['error'] as String?) ?? 'Request failed (${res.statusCode})';
      if (body['fields'] is List) {
        fields = {
          for (final f in body['fields'] as List)
            '${f['field']}': '${f['message']}',
        };
      }
    } catch (_) {
      message = res.statusCode >= 500
          ? 'The server could not complete that request. Please try again.'
          : 'Request failed (${res.statusCode})';
    }
    throw ApiException(res.statusCode, message, fields: fields);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    bool allowRetry = true,
  }) async {
    http.Response res;
    try {
      res = await request();
    } on SocketException {
      throw ApiException(0, 'No connection. Check your internet and try again.');
    } on http.ClientException {
      throw ApiException(0, 'Could not reach the server. Please try again.');
    }

    // A 401 on a request we had a token for means the access token expired;
    // refresh once and replay before giving up on the session.
    if (res.statusCode == 401 && allowRetry && _refreshToken != null) {
      if (await _refresh()) {
        return _send(request, allowRetry: false);
      }
      await clearSession();
      onSessionExpired?.call();
    }
    return res;
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) async {
    final res = await _send(() => http.get(_uri(path, query), headers: _headers()));
    if (res.statusCode >= 400) _throwFor(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final res = await _send(() => http.post(
          _uri(path),
          headers: _headers(),
          body: jsonEncode(body ?? {}),
        ));
    if (res.statusCode >= 400) _throwFor(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    final res = await _send(() => http.put(
          _uri(path),
          headers: _headers(),
          body: jsonEncode(body ?? {}),
        ));
    if (res.statusCode >= 400) _throwFor(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<dynamic> delete(String path) async {
    final res = await _send(() => http.delete(_uri(path), headers: _headers()));
    if (res.statusCode >= 400) _throwFor(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /// Multipart upload used for attendance selfies, signatures, receipts and
  /// activity photos. [bytes] keeps this usable on web, where File is absent.
  Future<dynamic> upload(
    String path, {
    required String field,
    required String filename,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    Map<String, String> extra = const {},
  }) async {
    Future<http.Response> build() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers(json: false))
        ..fields.addAll(extra)
        ..files.add(http.MultipartFile.fromBytes(
          field,
          bytes,
          filename: filename,
          // The server's upload filter reads the part's MIME type, so it must be
          // set explicitly — without it multer sees application/octet-stream
          // and rejects the file.
          contentType: MediaType.parse(contentType),
        ));
      return http.Response.fromStream(await request.send());
    }

    final res = await _send(build);
    if (res.statusCode >= 400) _throwFor(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /// Downloads a generated PDF as raw bytes.
  Future<Uint8List> download(String path, [Map<String, dynamic>? query]) async {
    final res = await _send(() => http.get(_uri(path, query), headers: _headers(json: false)));
    if (res.statusCode >= 400) _throwFor(res);
    return res.bodyBytes;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'device': defaultTargetPlatform.name,
      }),
    );
    if (res.statusCode >= 400) _throwFor(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await _saveSession(body['access_token'] as String?, body['refresh_token'] as String?);
    return body['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> googleLogin({
    required String email,
    required String idToken,
    String? accessToken,
    String? displayName,
    String? photoUrl,
  }) async {
    final res = await http.post(
      _uri('/auth/google-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'idToken': idToken,
        'accessToken': accessToken,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'device': defaultTargetPlatform.name,
      }),
    );
    if (res.statusCode >= 400) _throwFor(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await _saveSession(body['access_token'] as String?, body['refresh_token'] as String?);
    return body['user'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      if (_refreshToken != null) {
        await http.post(
          _uri('/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': _refreshToken}),
        );
      }
    } catch (_) {
      // Signing out locally matters more than reaching the server.
    }
    await clearSession();
  }
}
