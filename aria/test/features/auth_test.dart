import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('authRedirect', () {
    test('signed-out users are sent to sign-in', () {
      expect(authRedirect(signedIn: false, location: '/today'), '/sign-in');
      expect(authRedirect(signedIn: false, location: '/splash'), '/sign-in');
      expect(
        authRedirect(signedIn: false, location: '/reminder/x'),
        '/sign-in',
      );
    });

    test('signed-out users may stay on auth pages', () {
      expect(authRedirect(signedIn: false, location: '/sign-in'), isNull);
      expect(
        authRedirect(signedIn: false, location: '/sign-in/verify'),
        isNull,
      );
    });

    test('signed-in users skip splash and auth pages', () {
      expect(authRedirect(signedIn: true, location: '/splash'), '/today');
      expect(authRedirect(signedIn: true, location: '/sign-in'), '/today');
      expect(authRedirect(signedIn: true, location: '/lists'), isNull);
      expect(
        authRedirect(signedIn: true, location: '/reminder/abc'),
        isNull,
        reason: 'deep links survive',
      );
    });
  });

  group('phone & email validation', () {
    test('accepts 10-digit Indian mobiles and E.164', () {
      expect(normalisePhone('98765 43210'), '+919876543210');
      expect(normalisePhone('+44 7700 900123'), '+447700900123');
    });

    test('rejects bad numbers', () {
      expect(normalisePhone('12345'), isNull);
      expect(
        normalisePhone('1234567890'),
        isNull,
        reason: 'Indian mobiles start with 6–9',
      );
    });

    test('email', () {
      expect(isValidEmail('a@b.in'), isTrue);
      expect(isValidEmail('nope'), isFalse);
    });
  });

  test('sign-in errors are plain language, never raw exceptions', () {
    expect(
      friendlyAuthError(
        Exception(
          'AuthApiException(message: Error sending SMS: twilio, statusCode: 500)',
        ),
      ),
      contains('Try email instead'),
    );
    expect(
      friendlyAuthError(Exception('SocketException: Failed host lookup')),
      contains('internet'),
    );
    expect(
      friendlyAuthError(
        Exception(
          'For security purposes, you can only request this after 42 seconds',
        ),
      ),
      contains('wait a minute'),
    );
    expect(
      friendlyAuthError(Exception('Token has expired or is invalid')),
      contains('expired'),
    );
    expect(friendlyAuthError(Exception('weird')), isNot(contains('Exception')));
  });
}
