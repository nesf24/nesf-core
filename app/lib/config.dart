import 'package:flutter/foundation.dart';

class AppConfig {
  /// Explicit override, set at build time:
  ///   flutter build apk --dart-define=API_BASE=https://app.nesportsfoundation.in
  static const String _override = String.fromEnvironment('API_BASE');

  /// Where the app lives when nothing else is specified.
  /// For local testing on same WiFi network: use computer's IP
  static const String productionOrigin = 'http://10.13.97.1:4000';

  /// Base origin of the NESF Core API, always absolute.
  ///
  /// Resolution order:
  ///  1. An `API_BASE` define, when a non-empty one was given.
  ///  2. On web, the origin the page was served from — the deployed web build is
  ///     served by the API itself, so same-origin is correct and avoids any
  ///     cross-origin preflight. This is also why `build:web` passes an empty
  ///     define rather than hardcoding the domain.
  ///  3. Release builds fall back to the production domain.
  ///  4. Debug builds point at a local API: the Android emulator reaches the host
  ///     on 10.0.2.2, never on localhost.
  static String get apiBase {
    if (_override.isNotEmpty) return _stripTrailingSlash(_override);
    if (kIsWeb) return _stripTrailingSlash(Uri.base.origin);
    if (kReleaseMode) return productionOrigin;
    return 'http://10.0.2.2:4000';
  }

  static String get apiUrl => '$apiBase/api';

  /// Absolute URL for a stored file.
  ///
  /// The API stores a storage key (`attendance/2026-08/….jpg`), never a public
  /// URL — uploads are private, so loading one needs the session token. Use
  /// [Api.mediaHeaders] alongside this when passing it to `Image.network`.
  ///
  /// Returns null for a null/empty key so callers can fall back to a placeholder.
  static String? mediaUrl(String? key) {
    if (key == null || key.trim().isEmpty) return null;
    final k = key.trim();
    // Records written before uploads became private may hold a full URL.
    if (k.startsWith('http://') || k.startsWith('https://')) return k;
    final path = k.startsWith('/') ? k.substring(1) : k;
    return '$apiUrl/media/$path';
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  static const String appName = 'NESF Core';
  static const String orgName = 'The NE Sports Foundation';
}
