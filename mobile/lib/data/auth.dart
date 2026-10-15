import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Authentication.
///
/// PRD §5.1 lists email authentication as P0. Anonymous sign-in stays as a
/// deliberate second door: a student can try a viva before committing to an
/// account, and Supabase upgrades that account in place — the uid never
/// changes, so no rows move and nothing is lost on sign-up.
class Auth {
  const Auth();

  static SupabaseClient get _c => Backend.client;

  User? get user => _c.auth.currentUser;
  Session? get session => _c.auth.currentSession;
  bool get isSignedIn => session != null;
  bool get isGuest => user?.isAnonymous ?? false;

  Stream<AuthState> get changes => _c.auth.onAuthStateChange;

  String get displayName {
    final u = user;
    if (u == null) return 'Guest';
    final meta = u.userMetadata?['full_name'] as String?;
    if (meta != null && meta.trim().isNotEmpty) return meta.trim();
    final email = u.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Guest';
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    // An existing guest is *linked*, not replaced: their subjects, answers and
    // mastery all hang off this uid, and a fresh sign-up would strand them.
    if (isGuest) {
      await _c.auth.updateUser(
        UserAttributes(
            email: email, password: password, data: {'full_name': name}),
      );
      return;
    }
    final res = await _c.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );
    if (res.session == null && res.user == null) {
      throw const AuthException('Could not create the account.');
    }
  }

  Future<void> signIn({required String email, required String password}) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<void> continueAsGuest() async {
    if (session == null) await _c.auth.signInAnonymously();
  }

  Future<void> sendPasswordReset(String email) =>
      _c.auth.resetPasswordForEmail(email);

  Future<void> signOut() => _c.auth.signOut();

  /// Turns Supabase's error text into something a student can act on.
  ///
  /// "AuthApiException(message: Invalid login credentials, statusCode: 400)"
  /// is accurate and useless; a person needs to know whether to retry the
  /// password or create an account.
  static String readable(Object error) {
    final raw = error is AuthException ? error.message : error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (lower.contains('already registered') ||
        lower.contains('already been registered')) {
      return 'An account with that email already exists. Sign in instead.';
    }
    if (lower.contains('password should be at least')) {
      return 'Passwords need at least 8 characters.';
    }
    if (lower.contains('unable to validate email')) {
      return 'That email address does not look right.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('clientexception')) {
      return 'Could not reach the server. Check your connection.';
    }
    return raw;
  }
}
