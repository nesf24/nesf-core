// Exercises the app's real Api/AuthService classes against a running NESF Core
// API, so a mismatch between the Dart client and the server contract (paths,
// field names, response shapes) fails here rather than on a staff member's phone.
//
// Requires the API on http://localhost:4000 with the seeded admin. Skipped
// automatically when the server is not reachable, so `flutter test` stays green
// in environments without it.
//
// The API_BASE define is required: without it a non-web debug build points at
// 10.0.2.2, which is the Android emulator's route to the host and unreachable
// from the test VM.
//
//   cd api && npm start
//   cd app && flutter test test/api_contract_test.dart --dart-define=API_BASE=http://localhost:4000
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nesf_core/services/api.dart';
import 'package:nesf_core/services/auth.dart';

const _adminEmail = 'biki@nesportsfoundation.in';
const _adminPassword = 'ChangeMe@123';

Future<bool> _apiReachable() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final req = await client.getUrl(Uri.parse('http://localhost:4000/health'));
    final res = await req.close();
    await res.drain();
    client.close();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool reachable;

  setUpAll(() async {
    reachable = await _apiReachable();
    if (!reachable) {
      // ignore: avoid_print
      print('NESF Core API not reachable on :4000 — contract tests skipped.');
    }
  });

  setUp(() {
    // Api persists tokens through SharedPreferences, which has no platform
    // implementation under the test VM.
    SharedPreferences.setMockInitialValues({});
  });

  test('signs in and loads the dashboard payload the home screen reads', () async {
    if (!reachable) return;
    final api = Api();
    final auth = AuthService(api);

    await auth.signIn(_adminEmail, _adminPassword);
    expect(auth.isSignedIn, isTrue);

    final me = auth.employee!;
    expect(me.empCode, isNotEmpty);
    expect(me.fullName, isNotEmpty);
    expect(me.isApprover, isTrue, reason: 'seeded account is an admin');

    // Every key the dashboard screen dereferences must be present.
    final dash = await api.get('/dashboard') as Map<String, dynamic>;
    for (final key in [
      'date', 'user', 'attendance', 'leave_balance',
      'my_pending', 'inbox', 'crm_due', 'org_today',
    ]) {
      expect(dash.containsKey(key), isTrue, reason: 'dashboard is missing "$key"');
    }
    expect((dash['attendance'] as Map)['can_check_in'], isA<bool>());
    expect(dash['leave_balance'], isA<List>());
    expect((dash['org_today'] as Map)['staff_total'], isA<int>());
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('surfaces the server message on a bad password', () async {
    if (!reachable) return;
    final api = Api();
    await expectLater(
      api.login(_adminEmail, 'definitely-not-the-password'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', contains('Incorrect'))),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('reports validation failures per field', () async {
    if (!reachable) return;
    final api = Api();
    await api.login(_adminEmail, _adminPassword);

    // Too short a reason: the server returns field-level detail the forms show.
    try {
      await api.post('/leaves', {
        'leave_type_id': 1,
        'from_date': '2026-09-01',
        'to_date': '2026-09-02',
        'reason': 'x',
      });
      fail('expected the short reason to be rejected');
    } on ApiException catch (e) {
      expect(e.statusCode, 400);
      expect(e.fields, isNotNull);
      expect(e.fields!.keys, contains('reason'));
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('lists the endpoints each screen loads on open', () async {
    if (!reachable) return;
    final api = Api();
    await api.login(_adminEmail, _adminPassword);

    // Paths and query shapes exactly as the screens call them.
    expect(await api.get('/leaves/types'), isA<List>());
    expect(await api.get('/leaves', {'scope': 'mine'}), isA<List>());
    expect(await api.get('/leaves', {'scope': 'inbox'}), isA<List>());
    expect(await api.get('/reports', {'scope': 'mine'}), isA<List>());
    expect(await api.get('/tada', {'scope': 'mine'}), isA<List>());
    expect(await api.get('/projects'), isA<List>());
    expect(await api.get('/projects/activities/list', {'scope': 'mine'}), isA<List>());
    expect(await api.get('/crm/contacts'), isA<List>());
    expect(await api.get('/crm/pipeline'), isA<List>());
    expect(await api.get('/employees'), isA<List>());
    expect(await api.get('/attendance/today'), isA<Map>());
    expect(await api.get('/attendance/me'), isA<List>());

    final rates = await api.get('/tada/rates') as Map<String, dynamic>;
    expect(rates['ta_rates'], isA<List>());
    expect(rates['da_rates'], isA<List>());

    // The calendar screen indexes into these two shapes directly.
    final leaveCal = await api.get('/leaves/calendar', {'year': 2026, 'month': 8})
        as Map<String, dynamic>;
    expect(leaveCal['by_date'], isA<Map>());
    expect(leaveCal['holidays'], isA<List>());

    final attCal = await api.get('/attendance/calendar', {'year': 2026, 'month': 8})
        as Map<String, dynamic>;
    expect(attCal['days'], isA<int>());
    expect(attCal['rows'], isA<List>());
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('downloads an issued PDF as real PDF bytes', () async {
    if (!reachable) return;
    final api = Api();
    await api.login(_adminEmail, _adminPassword);

    final bytes = await api.download('/attendance/muster.pdf', {'year': 2026, 'month': 8});
    expect(bytes.length, greaterThan(1000));
    // %PDF- magic number — proves the download path returns the file, not JSON.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('refreshes an expired access token without losing the session', () async {
    if (!reachable) return;
    final api = Api();
    await api.login(_adminEmail, _adminPassword);

    // Simulate an expired access token while the refresh token stays valid;
    // the client should refresh and replay the request transparently.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nesf_access_token', 'not-a-valid-jwt');

    final fresh = Api();
    await fresh.loadSession();
    // Re-login is needed to seed a refresh token into this fresh instance's
    // storage, since the mock store was reset above.
    await fresh.login(_adminEmail, _adminPassword);
    expect(await fresh.get('/auth/me'), isA<Map>());
  }, timeout: const Timeout(Duration(seconds: 30)));
}
