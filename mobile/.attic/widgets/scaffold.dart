import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../design/tokens.dart';

/// The page frame.
///
/// A large title that sits in the content rather than in an app bar, the way
/// every native list screen on both platforms does it. Content is capped at
/// 520pt and centred: the app is phone-first but runs on the web, and a viva
/// question stretched across a 1400px browser breaks the measure the type
/// scale is built on.
class VxScreen extends StatelessWidget {
  const VxScreen({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.onBack,
    this.backLabel,
  });

  final List<Widget> children;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return Scaffold(
      backgroundColor: vx.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.only(bottom: VxSpace.xxl),
              children: [
                if (onBack != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.chevron_left_rounded, size: 22),
                      label: Text(backLabel ?? 'Back'),
                      style: TextButton.styleFrom(
                        foregroundColor: vx.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      VxSpace.md,
                      onBack == null ? VxSpace.md : VxSpace.xs,
                      VxSpace.md,
                      subtitle == null ? VxSpace.md : 2,
                    ),
                    child: Text(title!, style: VxType.title.copyWith(color: vx.text)),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        VxSpace.md, 0, VxSpace.md, VxSpace.md),
                    child: Text(
                      subtitle!,
                      style: VxType.body.copyWith(color: vx.muted),
                    ),
                  ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A grouped list of rows — the primitive this app is built from.
///
/// Deliberately one primitive, repeated. The previous pass gave nearly every
/// block on screen its own border, radius and accent stripe, which is card
/// soup: when everything is separated, nothing is grouped, and the hierarchy
/// flattens into a wall of equal-weight boxes.
///
/// So: a single quiet surface, rows divided by inset hairlines, and the
/// section's name in plain sentence case *outside* the group where it labels
/// rather than decorates.
class VxGroup extends StatelessWidget {
  const VxGroup({super.key, required this.children, this.header, this.footer});

  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                VxSpace.md, VxSpace.lg, VxSpace.md, VxSpace.xs),
            // Sentence case. All-caps micro-labels above every block are a
            // generated-interface tell and they shout at 11px.
            child: Text(header!, style: VxType.label.copyWith(color: vx.muted)),
          ),
        Container(
          decoration: BoxDecoration(
            color: vx.card,
            borderRadius: BorderRadius.circular(VxRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(horizontal: VxSpace.md),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: VxSpace.md),
                    child: Divider(height: 1, thickness: 1, color: vx.hairline),
                  ),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                VxSpace.md, VxSpace.xs, VxSpace.md, 0),
            child: Text(
              footer!,
              style: VxType.caption.copyWith(color: vx.muted, height: 1.45),
            ),
          ),
      ],
    );
  }
}

/// A single row inside a [VxGroup].
class VxRow extends StatelessWidget {
  const VxRow({
    super.key,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final vx = context.vx;

    final body = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: VxSpace.md, vertical: VxSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: VxType.body.copyWith(
                    color: destructive ? vx.textOn(VxPalette.red) : vx.text,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: VxType.caption.copyWith(color: vx.muted, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: VxSpace.sm),
            trailing!,
          ],
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 20, color: vx.faint),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}

/// Full-width primary action, in the page's own margin.
class VxAction extends StatelessWidget {
  const VxAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VxSpace.md, VxSpace.xs, VxSpace.md, 0),
      child: secondary
          ? TextButton(onPressed: onPressed, child: Text(label))
          : FilledButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
