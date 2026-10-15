import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'widgets/scaffold.dart';

/// Settings, export and account deletion.
///
/// In-app account deletion is mandatory for any App Store app that offers
/// sign-up — the iOS build is rejected without it, and no document in the
/// corpus mentioned it (audit LEG-01). Deletion removes the embeddings, not
/// only the rows: student notes are personal data and India's DPDP Act
/// applies. Export exists for the same reason — the work is the student's.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return VxScreen(
      title: 'Settings',
      children: [
        VxGroup(
          header: 'Examination',
          children: [
            VxRow(
              title: 'Exam date',
              trailing: Text('12 September',
                  style: VxType.body.copyWith(color: vx.muted)),
              onTap: () {},
            ),
            VxRow(
              title: 'Voice answers',
              trailing: Text('On', style: VxType.body.copyWith(color: vx.muted)),
              onTap: () {},
            ),
            VxRow(
              title: 'Revision reminders',
              trailing: Text('On', style: VxType.body.copyWith(color: vx.muted)),
              onTap: () {},
            ),
          ],
        ),
        VxGroup(
          header: 'Your data',
          children: [
            VxRow(
              title: 'Documents',
              trailing: Text('3', style: VxType.body.copyWith(color: vx.muted)),
            ),
            VxRow(
              title: 'Passages indexed',
              trailing:
                  Text('214', style: VxType.body.copyWith(color: vx.muted)),
            ),
            VxRow(
              title: 'Answers recorded',
              trailing: Text('86', style: VxType.body.copyWith(color: vx.muted)),
            ),
            VxRow(
              title: 'Export everything',
              detail: 'Notes, answers, scores and history as one file.',
              onTap: () {},
            ),
          ],
        ),
        VxGroup(
          children: [
            VxRow(
              title: 'Delete account',
              detail: 'Removes your notes, embeddings, scores and history. '
                  'Permanent.',
              destructive: true,
              onTap: () => _confirmDelete(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your notes, their embeddings, every score and your whole history '
          'are removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not wired to a backend in this build.')),
      );
    }
  }
}
