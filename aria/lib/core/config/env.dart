import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Compile-time configuration, supplied via
/// `flutter run --dart-define-from-file=env/dev.json`.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Social sign-in needs console credentials; off until configured.
  static const enableGoogleSignIn = bool.fromEnvironment(
    'ENABLE_GOOGLE_SIGN_IN',
  );
  static const enableAppleSignIn = bool.fromEnvironment('ENABLE_APPLE_SIGN_IN');

  /// RevenueCat public SDK keys (store purchases). Empty = purchases off.
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );
  static const revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  /// Direct UPI/card payments via Razorpay — only where store policy allows
  /// (web, or regions with alternative billing). Off by default.
  static const enableRazorpay = bool.fromEnvironment('ENABLE_RAZORPAY');

  /// Firebase (Crashlytics + Analytics). All empty = telemetry off.
  static const _fbApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _fbProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _fbSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _fbAndroidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _fbIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _fbIosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
  );

  static FirebaseOptions? get firebaseOptions {
    if (kIsWeb || _fbApiKey.isEmpty || _fbProjectId.isEmpty) return null;
    final appId = Platform.isIOS ? _fbIosAppId : _fbAndroidAppId;
    if (appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: _fbApiKey,
      appId: appId,
      messagingSenderId: _fbSenderId,
      projectId: _fbProjectId,
      iosBundleId: Platform.isIOS && _fbIosBundleId.isNotEmpty
          ? _fbIosBundleId
          : null,
    );
  }

  /// Deep-link scheme (also used as the auth redirect).
  static const deepLinkScheme = 'aria';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
