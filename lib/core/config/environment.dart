/// Environment configuration loaded via build-time `--dart-define`
/// or `--dart-define-from-file=config/dev.json`.
abstract final class Environment {
  /// The public Supabase Project URL (e.g. https://xyz.supabase.co).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// The public/publishable Anon key. Never include service_role or secret keys.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// Whether valid Supabase credentials have been injected at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Validates environment variables at startup and throws a clean,
  /// developer-friendly error if required credentials are missing.
  static void validate() {
    if (!isConfigured) {
      final missing = <String>[];
      if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
      if (supabasePublishableKey.isEmpty) {
        missing.add('SUPABASE_PUBLISHABLE_KEY');
      }

      throw StateError(
        'FreshMarket startup configuration error:\n'
        'Missing build-time environment variables: ${missing.join(', ')}\n\n'
        'To run the application, provide credentials using:\n'
        '  flutter run --dart-define-from-file=config/dev.json\n\n'
        'Ensure config/dev.json exists with valid development keys.',
      );
    }
  }
}
