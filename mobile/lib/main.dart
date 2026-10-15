import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/auth.dart';
import 'data/supabase_client.dart';
import 'design/bold.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/shell/tab_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const ViaXApp());
}

class ViaXApp extends StatelessWidget {
  const ViaXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Bold.themeNotifier,
      builder: (context, themeMode, _) {
        Brightness brightness = Brightness.light;
        try {
          brightness =
              WidgetsBinding.instance.platformDispatcher.platformBrightness;
        } catch (_) {}
        final isDark = themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system && brightness == Brightness.dark);
        Bold.isDark = isDark;

        return MaterialApp(
          title: 'ViaX',
          debugShowCheckedModeBanner: false,
          theme: boldLightTheme(),
          darkTheme: boldDarkTheme(),
          themeMode: themeMode,
          home: Builder(
            builder: (ctx) {
              Bold.isDark = Theme.of(ctx).brightness == Brightness.dark;
              return const _Gate();
            },
          ),
        );
      },
    );
  }
}

/// Boot, then the door.
///
/// Three states, in order: connecting, not signed in, signed in. Previously
/// the app signed everyone in anonymously at boot, which meant a returning
/// student was silently handed a fresh empty account — the same screen a new
/// user sees, with all their work apparently gone.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  static const _auth = Auth();
  late Future<void> _ready;
  bool _seenOnboarding = false;

  @override
  void initState() {
    super.initState();
    _ready = Backend.init();
  }

  void _retry() {
    // Block body, not an arrow: `setState(() => x = f())` returns the
    // value of the assignment, and Flutter refuses a callback that
    // returns a Future. The assignment has to be a statement.
    setState(() {
      _ready = Backend.init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        if (snap.hasError) {
          return _ConnectionError(error: '${snap.error}', onRetry: _retry);
        }

        // Rebuilds on sign-in, sign-out and token refresh, so the gate never
        // shows a stale side of the door.
        return StreamBuilder(
          stream: _auth.changes,
          builder: (context, _) {
            if (_auth.isSignedIn) {
              return TabShell(onSignedOut: () => setState(() {}));
            }
            if (!_seenOnboarding) {
              return OnboardingScreen(
                onDone: () => setState(() => _seenOnboarding = true),
              );
            }
            return SignInScreen(onSignedIn: () => setState(() {}));
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Bold.brandDeep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ViaXMark(size: 66, radius: 18),
            const SizedBox(height: 20),
            Text('ViaX', style: T.title.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text('Your examiner is getting ready',
                style: T.small.copyWith(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: Bold.slate),
              const SizedBox(height: 16),
              Text('Could not connect',
                  style: T.title.copyWith(color: Bold.ink)),
              const SizedBox(height: 8),
              Text(Auth.readable(error),
                  textAlign: TextAlign.center,
                  style: T.bodyQuiet.copyWith(color: Bold.slate)),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
