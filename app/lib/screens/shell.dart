import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth.dart';
import '../theme.dart';

/// Bottom-tab shell. The Approvals tab only appears for staff who can actually
/// review or approve something, so an ordinary field coordinator is not shown a
/// permanently empty inbox.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.state, required this.child});
  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final showApprovals = auth.employee?.isReviewer ?? false;

    final tabs = <({String path, IconData icon, IconData active, String label})>[
      (path: '/home', icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home'),
      (
        path: '/attendance',
        icon: Icons.fingerprint_outlined,
        active: Icons.fingerprint_rounded,
        label: 'Attendance'
      ),
      (
        path: '/calendar',
        icon: Icons.calendar_month_outlined,
        active: Icons.calendar_month_rounded,
        label: 'Calendar'
      ),
      if (showApprovals)
        (
          path: '/approvals',
          icon: Icons.assignment_turned_in_outlined,
          active: Icons.assignment_turned_in_rounded,
          label: 'Approvals'
        ),
      (
        path: '/profile',
        icon: Icons.person_outline_rounded,
        active: Icons.person_rounded,
        label: 'Profile'
      ),
    ];

    final location = state.matchedLocation;
    var index = tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          if (tabs[i].path != location) context.go(tabs[i].path);
        },
        backgroundColor: Colors.white,
        indicatorColor: NesfColors.greenLight,
        surfaceTintColor: Colors.white,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon, color: NesfColors.muted),
              selectedIcon: Icon(tab.active, color: NesfColors.green),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
