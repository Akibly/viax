import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/repository.dart';
import '../../design/bold.dart';
import 'settings_screen.dart';

/// Profile — who you are, and the way out (UI/UX §3: behind the avatar).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _auth = Auth();
  static const _repo = Repository();
  late Future<AccountSummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _repo.accountSummary();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_auth.isGuest ? 'Leave guest session?' : 'Sign out?'),
        content: Text(
          _auth.isGuest
              // A guest account cannot be signed back into — saying so before
              // they tap is the difference between a choice and a trap.
              ? 'This guest account cannot be recovered once you leave. Create '
                  'an account first if you want to keep your notes and progress.'
              : 'You can sign back in any time with your email and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _auth.isGuest
                ? FilledButton.styleFrom(backgroundColor: Bold.danger)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_auth.isGuest ? 'Leave anyway' : 'Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _auth.signOut();
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Bold.themeNotifier,
      builder: (context, _, __) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Bold.canvas,
            surfaceTintColor: Colors.transparent,
            title: Text('Profile', style: T.heading.copyWith(color: Bold.ink)),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: FutureBuilder<AccountSummary>(
                  future: _summary,
                  builder: (context, snap) {
                    final s = snap.data;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: const BoxDecoration(
                                color: Bold.brand,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _auth.displayName.characters.first
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_auth.displayName,
                                      style: T.title.copyWith(color: Bold.ink)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _auth.user?.email ?? 'Guest account',
                                    style: T.small.copyWith(color: Bold.slate),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_auth.isGuest) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Bold.wash(Bold.warn),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('You are signed in as a guest',
                                    style: T.body.copyWith(
                                        color: Bold.warn,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Text(
                                  'Your notes and progress live on this device only. '
                                  'Creating an account keeps them — nothing is lost '
                                  'in the upgrade.',
                                  style: T.small
                                      .copyWith(color: Bold.warn, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (s != null) ...[
                          Text('Your data',
                              style: T.heading.copyWith(color: Bold.ink)),
                          const SizedBox(height: 10),
                          _Card(children: [
                            _Row(label: 'Subjects', value: '${s.subjects}'),
                            _Row(label: 'Documents', value: '${s.documents}'),
                            _Row(
                                label: 'Passages indexed',
                                value: '${s.passages}'),
                            _Row(
                                label: 'Answers recorded',
                                value: '${s.answers}'),
                          ]),
                        ],
                        const SizedBox(height: 24),
                        _Card(children: [
                          ListTile(
                            leading: Icon(Icons.settings_outlined,
                                color: Bold.slate),
                            title: Text('Settings',
                                style: T.body.copyWith(color: Bold.ink)),
                            trailing: Icon(Icons.chevron_right_rounded,
                                color: Bold.slate),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen()),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.logout_rounded,
                                color: Bold.danger),
                            title: Text(
                              _auth.isGuest
                                  ? 'Leave guest session'
                                  : 'Sign out',
                              style: T.body.copyWith(color: Bold.danger),
                            ),
                            onTap: _signOut,
                          ),
                        ]),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Bold.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bold.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label, style: T.body.copyWith(color: Bold.ink))),
          Text(value, style: T.body.copyWith(color: Bold.slate)),
        ],
      ),
    );
  }
}
