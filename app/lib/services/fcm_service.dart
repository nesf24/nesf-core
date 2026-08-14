import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:developer' as developer;
import 'api.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _token;

  static Future<void> initialize() async {
    // Request notification permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    developer.log('FCM Permission status: ${settings.authorizationStatus}');

    // Get token
    _token = await _messaging.getToken();
    developer.log('FCM Token: $_token');

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background/terminated state messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    developer.log('Foreground message: ${message.data}');
    // App can handle the message UI here
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    developer.log('Background message: ${message.data}');
    // Handle background message (notification shown by system)
  }

  static Future<String?> getToken() async {
    if (_token == null) {
      _token = await _messaging.getToken();
    }
    return _token;
  }

  static Future<void> sendTokenToApi(String token, Api api) async {
    try {
      await api.post('/auth/fcm-token', {
        'fcm_token': token,
        'device_type': 'android',
      });
      developer.log('FCM token sent to server');
    } catch (e) {
      developer.log('Failed to send FCM token: $e');
    }
  }
}
