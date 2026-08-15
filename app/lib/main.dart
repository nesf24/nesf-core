import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'router.dart';
import 'services/api.dart';
import 'services/attendance.dart';
import 'services/auth.dart';
import 'services/documents.dart';
import 'services/fcm_service.dart';
import 'providers/splash_provider.dart';
import 'widgets/splash_overlay.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase with timeout
    await Firebase.initializeApp().timeout(Duration(seconds: 10));
  } catch (e) {
    print('Firebase initialization timeout or error: $e');
  }

  try {
    // Initialize FCM with timeout
    await FcmService.initialize().timeout(Duration(seconds: 10));
  } catch (e) {
    print('FCM initialization timeout or error: $e');
  }

  runApp(const NesfCoreApp());
}

class NesfCoreApp extends StatefulWidget {
  const NesfCoreApp({super.key});

  @override
  State<NesfCoreApp> createState() => _NesfCoreAppState();
}

class _NesfCoreAppState extends State<NesfCoreApp> {
  late final Api _api;
  late final AuthService _auth;
  late final AttendanceService _attendance;
  late final DocumentService _documents;

  @override
  void initState() {
    super.initState();
    _api = Api();
    _auth = AuthService(_api);
    _attendance = AttendanceService(_api);
    _documents = DocumentService(_api);
    // Restore a stored session before the first frame settles, so returning
    // staff land on the dashboard rather than the login screen.
    _auth.restore();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Api>.value(value: _api),
        ChangeNotifierProvider<AuthService>.value(value: _auth),
        Provider<AttendanceService>.value(value: _attendance),
        Provider<DocumentService>.value(value: _documents),
        ChangeNotifierProvider(create: (_) => SplashProvider()),
      ],
      child: Builder(
        builder: (context) {
          final router = buildRouter(_auth);
          return SplashOverlay(
            child: MaterialApp.router(
              title: 'NESF Core',
              debugShowCheckedModeBanner: false,
              theme: buildNesfTheme(),
              routerConfig: router,
            ),
          );
        },
      ),
    );
  }
}
