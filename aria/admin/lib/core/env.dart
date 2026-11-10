/// `flutter run -d web-server --dart-define-from-file=../env/dev.json`
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static bool get configured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
