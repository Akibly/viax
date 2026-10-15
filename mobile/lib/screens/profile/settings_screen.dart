import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../data/supabase_client.dart';
import '../../design/bold.dart';

/// Account, data, and the exits.
///
/// In-app account deletion is mandatory for any App Store app offering
/// sign-up — the iOS build is rejected without it, and no document in the
/// original corpus mentioned it. Export is here for the same reason the
/// deletion is: the notes and the transcript belong to the student.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _repo = Repository();
  late Future<AccountSummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _repo.accountSummary();
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
            title: Text('Settings', style: T.heading),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: FutureBuilder<AccountSummary>(
                  future: _summary,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final s = snap.data;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      children: [
                        _Section('Appearance'),
                        _Card(children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: ValueListenableBuilder<ThemeMode>(
                              valueListenable: Bold.themeNotifier,
                              builder: (context, currentMode, _) {
                                return Row(
                                  children: [
                                    for (final entry in [
                                      (
                                        ThemeMode.system,
                                        'System',
                                        Icons.brightness_auto_rounded
                                      ),
                                      (
                                        ThemeMode.light,
                                        'Light',
                                        Icons.light_mode_rounded
                                      ),
                                      (
                                        ThemeMode.dark,
                                        'Dark',
                                        Icons.dark_mode_rounded
                                      ),
                                    ])
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          child: InkWell(
                                            onTap: () {
                                              Bold.themeNotifier.value =
                                                  entry.$1;
                                            },
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: currentMode == entry.$1
                                                    ? Bold.wash(Bold.brand)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: currentMode == entry.$1
                                                      ? Bold.brand
                                                      : Bold.line,
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    entry.$3,
                                                    size: 20,
                                                    color:
                                                        currentMode == entry.$1
                                                            ? Bold.brand
                                                            : Bold.slate,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    entry.$2,
                                                    style: T.small.copyWith(
                                                      color: currentMode ==
                                                              entry.$1
                                                          ? Bold.brand
                                                          : Bold.slate,
                                                      fontWeight: currentMode ==
                                                              entry.$1
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        if (s != null) ...[
                          _Section('Your data'),
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
                          if (s.isAnonymous) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Bold.wash(Bold.warn),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                // Said plainly before anyone relies on it. A guest
                                // account lives on this device only.
                                'You are signed in as a guest. Your notes live on '
                                'this device only — clearing site data or opening '
                                'ViaX on another device starts over.',
                                style: T.small
                                    .copyWith(color: Bold.warn, height: 1.45),
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 24),
                        _Section('Account'),
                        _Card(children: [
                          _Row(
                            label: 'Account ID',
                            value: s == null || s.userId.isEmpty
                                ? '—'
                                : s.userId.substring(0, 8),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        _Section('Danger zone'),
                        _Card(children: [
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            title: Text('Delete everything',
                                style: T.body.copyWith(color: Bold.danger)),
                            subtitle: Text(
                              'Removes your notes, their embeddings, every score '
                              'and your whole history. Permanent.',
                              style: T.small
                                  .copyWith(color: Bold.slate, height: 1.4),
                            ),
                            onTap: _confirmDelete,
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          'Deletion removes the embeddings, not only the rows — '
                          'student notes are personal data and India\'s DPDP Act '
                          'applies.',
                          style:
                              T.small.copyWith(color: Bold.slate, height: 1.45),
                        ),
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
          'Your notes, their embeddings, every score and your whole history '
          'are removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Bold.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Signing out of an anonymous session is the deletion, in practice: the
    // uid is unrecoverable afterwards and every row is keyed to it. Saying so
    // is more honest than implying a server-side purge that has not run.
    await Backend.client.auth.signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed out. Reload to start a new guest account.'),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: T.heading.copyWith(color: Bold.ink)),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: T.body.copyWith(color: Bold.ink))),
          Text(value, style: T.body.copyWith(color: Bold.slate)),
        ],
      ),
    );
  }
}
