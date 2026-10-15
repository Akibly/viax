import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../home/home_screen.dart';
import '../progress/progress_screen.dart';
import '../subjects/subjects_screen.dart';
import '../viva/mode_picker_screen.dart';
import '../study/study_hub_screen.dart';
import '../chat/chat_screen.dart';
import '../../data/notification_service.dart';
import '../../design/bold.dart';

/// Five task destinations: overview, source library, study, viva, progress.
///
/// Home, Subjects, Viva, Progress — the core loop reachable in one tap.
/// Profile and settings live behind the avatar in the top bar of Home, as the
/// guide specifies, rather than taking a fifth tab they do not deserve.
///
/// Each tab keeps its own navigator so a deep flow (a subject, a concept)
/// does not lose its place when the student checks another tab and comes back.
class TabShell extends StatefulWidget {
  const TabShell({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell> {
  int _index = 0;
  final _navigators = List.generate(6, (_) => GlobalKey<NavigatorState>());

  /// Bumped to force the visible tab to refetch after something changes it —
  /// finishing a viva moves mastery, and a stale Home is a lie.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    NotificationService().scheduleNextReviewReminder();
  }

  void _refreshAll() {
    setState(() => _revision++);
    NotificationService().scheduleNextReviewReminder();
  }

  @override
  Widget build(BuildContext context) {
    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.auto_stories_outlined),
        selectedIcon: Icon(Icons.auto_stories_rounded),
        label: 'Library',
      ),
      NavigationDestination(
        icon: Icon(Icons.style_outlined),
        selectedIcon: Icon(Icons.style_rounded),
        label: 'Study',
      ),
      NavigationDestination(
        icon: Icon(Icons.mic_none_rounded),
        selectedIcon: Icon(Icons.mic_rounded),
        label: 'Viva',
      ),
      NavigationDestination(
        icon: Icon(Icons.query_stats_rounded),
        selectedIcon: Icon(Icons.insights_rounded),
        label: 'Progress',
      ),
      NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Chat'),
    ];

    void select(int i) {
      if (i == _index) {
        _navigators[i].currentState?.popUntil((r) => r.isFirst);
      } else {
        setState(() => _index = i);
      }
    }

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || (_navigators[_index].currentState?.canPop() ?? false)) {
          return;
        }
        if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expanded = constraints.maxWidth >= 800;
          final content = IndexedStack(
            index: _index,
            children: [
              _TabNavigator(
                key: ValueKey('home-nav-$_revision'),
                navigatorKey: _navigators[0],
                active: _index == 0,
                child: HomeScreen(
                  key: ValueKey('home-$_revision'),
                  onSignedOut: widget.onSignedOut,
                  onChanged: _refreshAll,
                  onOpenTab: select,
                ),
              ),
              _TabNavigator(
                key: ValueKey('library-nav-$_revision'),
                navigatorKey: _navigators[1],
                active: _index == 1,
                child: SubjectsScreen(
                  key: ValueKey('subjects-$_revision'),
                  onChanged: _refreshAll,
                ),
              ),
              _TabNavigator(
                key: ValueKey('study-nav-$_revision'),
                navigatorKey: _navigators[2],
                active: _index == 2,
                child: StudyHubScreen(
                  key: ValueKey('study-$_revision'),
                  onChanged: _refreshAll,
                  onOpenLibrary: () => select(1),
                ),
              ),
              _TabNavigator(
                key: ValueKey('viva-nav-$_revision'),
                navigatorKey: _navigators[3],
                active: _index == 3,
                child: ModePickerScreen(
                  key: ValueKey('viva-$_revision'),
                  onChanged: _refreshAll,
                  onOpenLibrary: () => select(1),
                ),
              ),
              _TabNavigator(
                key: ValueKey('progress-nav-$_revision'),
                navigatorKey: _navigators[4],
                active: _index == 4,
                child: ProgressScreen(key: ValueKey('progress-$_revision')),
              ),
              _TabNavigator(
                  navigatorKey: _navigators[5],
                  active: _index == 5,
                  child: const ChatScreen()),
            ],
          );

          return Scaffold(
            extendBody: !expanded,
            // The tab dock belongs to the screen edge. Let the active tab's
            // own Scaffold handle its editor/answer field when the IME opens;
            // otherwise a stale or transient IME inset can lift the entire
            // shell dock into the middle of the screen.
            resizeToAvoidBottomInset: expanded ? null : false,
            body: expanded
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: select,
                        extended: constraints.maxWidth >= 1100,
                        labelType: constraints.maxWidth >= 1100
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        destinations: [
                          for (final item in destinations)
                            NavigationRailDestination(
                              icon: item.icon,
                              selectedIcon: item.selectedIcon,
                              label: Text(item.label),
                            ),
                        ],
                      ),
                      VerticalDivider(width: 1, color: Bold.line),
                      Expanded(child: content),
                    ],
                  )
                : content,
            bottomNavigationBar: expanded
                ? null
                : ViaXFloatingTabBar(
                    selectedIndex: _index,
                    destinations: destinations,
                    onSelect: select,
                  ),
          );
        },
      ),
    );
  }
}

/// A compact, translucent dock that floats above the gesture area instead of
/// becoming a full-width fifth screen edge. Each destination keeps a generous
/// touch target and an explicit label for clarity and accessibility.
class ViaXFloatingTabBar extends StatelessWidget {
  const ViaXFloatingTabBar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
  });

  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Bold.inkDark : Bold.inkLight;
    final quiet = isDark ? Bold.slateDark : Bold.slateLight;
    final selectedFill =
        isDark ? const Color(0xFF273664) : const Color(0xFFE1E7FF);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      // Scaffold measures bottomNavigationBar with a loose height constraint.
      // A plain Center expands into that entire space, consuming the body and
      // centering the dock halfway down the display. Keep the dock intrinsic
      // in height while still filling the available width.
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ClipRRect(
            key: const Key('viax-dock-surface'),
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? Bold.cardDark : Bold.cardLight)
                      .withValues(alpha: isDark ? 0.92 : 0.90),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: (isDark ? Colors.white : Bold.lineLight)
                        .withValues(alpha: isDark ? 0.10 : 0.9),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.24 : 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _FloatingTabItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          foreground: foreground,
                          quiet: quiet,
                          selectedFill: selectedFill,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingTabItem extends StatelessWidget {
  const _FloatingTabItem({
    required this.destination,
    required this.selected,
    required this.foreground,
    required this.quiet,
    required this.selectedFill,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final Color foreground;
  final Color quiet;
  final Color selectedFill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: selected ? selectedFill : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 21,
                    color: selected ? foreground : quiet,
                  ),
                  child: selected
                      ? (destination.selectedIcon ?? destination.icon)
                      : destination.icon,
                ),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? foreground : quiet,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.active,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<Object?>(
      enabled: active,
      onPopWithResult: (_) => navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
      ),
    );
  }
}
