import 'package:flutter/foundation.dart';

import 'api.dart';

/// The signed-in staff member.
class Employee {
  Employee(this.raw);
  final Map<String, dynamic> raw;

  int get id => raw['id'] as int;
  String get empCode => '${raw['emp_code'] ?? ''}';
  String get fullName => '${raw['full_name'] ?? ''}';
  String get email => '${raw['email'] ?? ''}';
  String? get phone => raw['phone'] as String?;
  String get role => '${raw['role'] ?? 'staff'}';
  String? get designation => raw['designation'] as String?;
  String? get department => raw['department'] as String?;
  String? get grade => raw['grade'] as String?;
  String? get photoUrl => raw['photo_url'] as String?;
  String? get signatureUrl => raw['signature_url'] as String?;
  String? get reportingToName => raw['reporting_to_name'] as String?;
  bool get mustChangePassword => raw['must_change_pw'] == true;

  double? get baseLat => (raw['base_lat'] as num?)?.toDouble();
  double? get baseLng => (raw['base_lng'] as num?)?.toDouble();
  String? get baseLabel => raw['base_label'] as String?;
  bool get hasBaseLocation => baseLat != null && baseLng != null;

  /// Can review submissions from their reportees.
  bool get isReviewer => role == 'manager' || role == 'authority' || role == 'admin';

  /// Can give final approval — their signature appears on issued documents.
  bool get isApprover => role == 'authority' || role == 'admin';

  bool get isAdmin => role == 'admin';

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get roleLabel => switch (role) {
        'admin' => 'Administrator',
        'authority' => 'Approving Authority',
        'manager' => 'Reporting Officer',
        _ => 'Staff',
      };
}

/// Holds the session and the current user, and notifies the router when either
/// changes so navigation can react to sign-in and sign-out.
class AuthService extends ChangeNotifier {
  AuthService(this.api) {
    api.onSessionExpired = () {
      _employee = null;
      _sessionExpired = true;
      notifyListeners();
    };
  }

  final Api api;

  Employee? _employee;
  bool _loading = true;
  bool _sessionExpired = false;

  Employee? get employee => _employee;
  bool get isSignedIn => _employee != null;
  bool get loading => _loading;
  bool get sessionExpired => _sessionExpired;

  void acknowledgeExpiry() {
    _sessionExpired = false;
  }

  /// Restores a stored session on launch, so staff are not asked to sign in
  /// every time they open the app.
  Future<void> restore() async {
    await api.loadSession();
    if (api.hasSession) {
      try {
        final me = await api.get('/auth/me') as Map<String, dynamic>;
        _employee = Employee(me);
      } catch (_) {
        // Token unusable — fall through to the login screen.
        await api.clearSession();
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final user = await api.login(email.trim(), password);
    _employee = Employee(user);
    _sessionExpired = false;
    notifyListeners();
  }

  Future<void> signInWithGoogle(Map<String, dynamic> response) async {
    final user = response['user'] as Map<String, dynamic>;
    _employee = Employee(user);
    _sessionExpired = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await api.logout();
    _employee = null;
    notifyListeners();
  }

  /// Re-reads the profile after a change (photo, signature, base location).
  Future<void> refresh() async {
    if (!api.hasSession) return;
    try {
      final me = await api.get('/auth/me') as Map<String, dynamic>;
      _employee = Employee(me);
      notifyListeners();
    } catch (_) {
      // A failed refresh should not drop the user out of the app.
    }
  }

  Future<void> changePassword(String current, String next) async {
    await api.post('/auth/change-password', {
      'current_password': current,
      'new_password': next,
    });
    // The server revokes other sessions and clears must_change_pw.
    await refresh();
  }
}
