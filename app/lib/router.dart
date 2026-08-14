import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/approvals_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/attendance_checkin.dart';
import 'screens/calendar_screen.dart';
import 'screens/crm_screen.dart';
import 'screens/crm_contact_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/leave_apply_screen.dart';
import 'screens/leave_screen.dart';
import 'screens/leave_request.dart';
import 'screens/google_login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/activity_form_screen.dart';
import 'screens/report_form_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'screens/tada_form_screen.dart';
import 'screens/tada_screen.dart';
import 'services/auth.dart';

GoRouter buildRouter(AuthService auth) {
  return GoRouter(
    initialLocation: '/',
    // Re-evaluates redirects whenever the session changes, so signing out from
    // any screen returns to login without each screen handling it.
    refreshListenable: auth,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';

      if (auth.loading) return state.matchedLocation == '/' ? null : '/';
      if (!auth.isSignedIn) return loggingIn ? null : '/login';
      if (loggingIn || state.matchedLocation == '/') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const GoogleLoginScreen()),

      // The five-tab shell staff spend their time in.
      ShellRoute(
        builder: (context, state, child) => AppShell(state: state, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/attendance', builder: (_, __) => const AttendanceScreen()),
          GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(path: '/approvals', builder: (_, __) => const ApprovalsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),

      GoRoute(path: '/leaves', builder: (_, __) => const LeaveScreen()),
      GoRoute(path: '/leaves/apply', builder: (_, __) => const LeaveApplyScreen()),
      GoRoute(path: '/checkin', builder: (_, __) => const AttendanceCheckInScreen()),
      GoRoute(path: '/leaves/request', builder: (_, __) => const LeaveRequestScreen()),

      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(
        path: '/reports/new',
        builder: (context, state) => ReportFormScreen(existing: state.extra as Map<String, dynamic>?),
      ),

      GoRoute(path: '/tada', builder: (_, __) => const TadaScreen()),
      GoRoute(path: '/tada/new', builder: (_, __) => const TadaFormScreen()),

      GoRoute(path: '/projects', builder: (_, __) => const ProjectsScreen()),
      GoRoute(
        path: '/activities/new',
        builder: (context, state) => ActivityFormScreen(project: state.extra as Map<String, dynamic>?),
      ),

      GoRoute(path: '/crm', builder: (_, __) => const CrmScreen()),
      GoRoute(
        path: '/crm/:id',
        builder: (context, state) => CrmContactScreen(
          contactId: int.parse(state.pathParameters['id']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('No screen for ${state.uri}')),
    ),
  );
}
