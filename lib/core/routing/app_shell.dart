import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.currentPath});

  final Widget child;
  final String currentPath;

  // Lucide ships one weight per icon (no separate outline/fill), so the
  // selected state is signaled by color + pill background, not icon swap.
  static const _destinations = [
    (path: '/', icon: LucideIcons.layoutGrid, label: 'Home'),
    (path: '/transactions', icon: LucideIcons.list, label: 'Activity'),
    (path: '/budgets', icon: LucideIcons.pieChart, label: 'Budgets'),
    (path: '/assistant', icon: LucideIcons.sparkles, label: 'Assistant'),
    (path: '/settings', icon: LucideIcons.settings, label: 'Settings'),
  ];

  int get _currentIndex {
    final index = _destinations.indexWhere((d) => d.path == currentPath);
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onHome = _currentIndex == 0;
    return PopScope(
      // Back from any tab returns to the dashboard first; only a back press
      // from the dashboard itself is allowed to leave the app. Tab switches
      // use go() (which replaces rather than stacks), so without this a back
      // press from any other tab would exit outright.
      canPop: onHome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        // Deliberately NOT using Scaffold's bottomNavigationBar slot — it wraps
        // its content in an opaque Material that fills the whole slot, which
        // shows through as a bar behind a rounded/margined pill. Overlaying it
        // directly on the body is the only way to get a truly floating nav.
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(padding: const EdgeInsets.only(bottom: 72), child: child),
              ),
              Positioned(
                left: 28,
                right: 28,
                bottom: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        // Semi-transparent + blurred behind it — a genuinely
                        // floating glass pill instead of an opaque bar that
                        // just happens to have rounded corners.
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: colors.hairline),
                        boxShadow: [
                          BoxShadow(color: colors.ink.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < _destinations.length; i++)
                            Expanded(child: _NavItem(destination: _destinations[i], selected: i == _currentIndex)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected});

  final ({String path, IconData icon, String label}) destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: destination.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => context.go(destination.path),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.brandSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(destination.icon, size: 18, color: selected ? colors.brand : colors.textMuted),
          ),
        ),
      ),
    );
  }
}
