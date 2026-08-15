import 'package:google_sign_in/google_sign_in.dart';
import 'dart:developer' as developer;
import 'api.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Note: hostedDomain was removed as it can cause auth issues on some devices
    // Server-side domain validation is more reliable
  );

  /// Sign in with Google and authenticate with backend
  static Future<Map<String, dynamic>> signInWithGoogle(Api api) async {
    try {
      // Trigger Google Sign-In
      developer.log('Starting Google Sign-In...');
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Sign in aborted by user');
      }

      developer.log('Google user email: ${googleUser.email}');

      // Verify email is from correct domain (client-side check)
      if (!googleUser.email.endsWith('@nesportsfoundation.in')) {
        await _googleSignIn.signOut();
        throw Exception('Please use your @nesportsfoundation.in account. You signed in as ${googleUser.email}');
      }

      developer.log('Google user signed in: ${googleUser.email}');

      // Get authentication tokens
      final googleAuth = await googleUser.authentication;

      // Send to backend for verification and user lookup
      final response = await api.googleLogin(
        email: googleUser.email,
        idToken: googleAuth.idToken ?? '',
        accessToken: googleAuth.accessToken,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
      );

      developer.log('Backend authenticated successfully');

      return response;
    } catch (e) {
      developer.log('Google sign-in error: $e');
      rethrow;
    }
  }

  /// Sign out from Google
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      developer.log('Signed out from Google');
    } catch (e) {
      developer.log('Sign out error: $e');
    }
  }

  /// Get current Google user
  static GoogleSignInAccount? getCurrentUser() {
    return _googleSignIn.currentUser;
  }

  /// Check if user is already signed in
  static Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  /// Refresh authentication tokens
  static Future<GoogleSignInAuthentication?> refreshAuthTokens() async {
    try {
      final user = _googleSignIn.currentUser;
      if (user == null) return null;

      return await user.authentication;
    } catch (e) {
      developer.log('Token refresh error: $e');
      return null;
    }
  }
}
