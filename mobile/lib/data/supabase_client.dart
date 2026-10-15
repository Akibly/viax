import 'package:supabase_flutter/supabase_flutter.dart';

/// Backend connection.
///
/// The URL and publishable key are compile-time constants supplied with
/// `--dart-define`, with the project's own values as defaults so the app runs
/// from a clean checkout. A publishable key is designed to ship inside the
/// client — every table is behind RLS keyed to `auth.uid()`, so this key alone
/// grants nothing. The service-role key must never appear in this package.
abstract final class Backend {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yqmxzjkebqtfjlopzgze.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_YVVPUOjB_iJLflmuUYCvJw_5FKaXTPY',
  );

  static SupabaseClient get client => Supabase.instance.client;

  static User? get user => client.auth.currentUser;

  /// Connects to Supabase. Does *not* sign anyone in.
  ///
  /// The app used to sign in anonymously here, which meant a returning
  /// student was silently handed a brand new empty account instead of being
  /// asked to sign in. Authentication is now a decision the person makes, on
  /// a screen built for it (PRD §5.1 lists email auth as P0).
  static Future<void> init() async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}
