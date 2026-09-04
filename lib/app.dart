import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'ui/core/app_state.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/admin/admin_screen.dart';
import 'ui/features/admin/activity_history_screen.dart';
import 'ui/features/admin/analytics_screen.dart';
import 'ui/features/admin/hazard_reports_screen.dart';
import 'ui/features/admin/import_screen.dart';
import 'ui/features/admin/tickets_screen.dart';
import 'ui/features/admin/user_management_screen.dart';
import 'ui/features/admin/revenue_screen.dart';
import 'ui/features/admin/ratings_screen.dart';
import 'ui/features/admin/rewards_screen.dart';
import 'ui/features/admin/vouchers_screen.dart';
import 'ui/features/auth/auth_screen.dart';
import 'ui/features/home/home_screen.dart';
import 'ui/features/navigation/in_app_navigation_screen.dart';
import 'ui/features/notifications/notifications_screen.dart';
import 'ui/features/profile/profile_screen.dart';
import 'ui/features/profile/charging_history_screen.dart';
import 'ui/features/profile/rewards_screen.dart';
import 'ui/features/profile/vouchers_screen.dart';
import 'ui/features/trip/trip_screen.dart';

class ChargeMyApp extends ConsumerWidget {
  const ChargeMyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authFlags = ref.watch(
      sessionProvider.select(
        (session) => (session.isAuthenticated, session.isAdmin),
      ),
    );
    final router = GoRouter(
      initialLocation: '/home',
      redirect: (context, state) {
        final protected =
            state.matchedLocation == '/trip' ||
            state.matchedLocation.startsWith('/profile');
        if (state.matchedLocation == '/auth' && authFlags.$1) {
          return authFlags.$2 ? '/admin' : '/home';
        }
        if (state.matchedLocation == '/home' &&
            authFlags.$2 &&
            state.uri.queryParameters['view'] != 'user') {
          return '/admin';
        }
        if (protected && !authFlags.$1) {
          return '/auth';
        }
        if (state.matchedLocation.startsWith('/admin') && !authFlags.$2) {
          return '/auth';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/navigation',
          builder:
              (_, state) => InAppNavigationScreen(
                request: state.extra! as NavigationRequest,
              ),
        ),
        GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/profile/history',
          builder: (_, _) => const ChargingHistoryScreen(),
        ),
        GoRoute(
          path: '/profile/vouchers',
          builder: (_, _) => const VouchersScreen(),
        ),
        GoRoute(
          path: '/profile/rewards',
          builder: (_, _) => const RewardsScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(path: '/trip', builder: (_, _) => const TripScreen()),
        GoRoute(
          path: '/admin',
          builder:
              (_, state) => AdminScreen(
                focusStationId: state.uri.queryParameters['station'],
                focusPileId: state.uri.queryParameters['pile'],
              ),
        ),
        GoRoute(
          path: '/admin/users',
          builder: (_, _) => const UserManagementScreen(),
        ),
        GoRoute(
          path: '/admin/revenue',
          builder: (_, _) => const RevenueScreen(),
        ),
        GoRoute(
          path: '/admin/reports',
          builder: (_, _) => const HazardReportsScreen(),
        ),
        GoRoute(
          path: '/admin/tickets',
          builder: (_, _) => const TicketsScreen(),
        ),
        GoRoute(
          path: '/admin/analytics',
          builder: (_, _) => const AnalyticsScreen(),
        ),
        GoRoute(
          path: '/admin/activity',
          builder: (_, _) => const ActivityHistoryScreen(),
        ),
        GoRoute(
          path: '/admin/ratings',
          builder: (_, _) => const RatingsScreen(),
        ),
        GoRoute(
          path: '/admin/vouchers',
          builder: (_, _) => const VouchersAdminScreen(),
        ),
        GoRoute(
          path: '/admin/rewards',
          builder: (_, _) => const RewardsAdminScreen(),
        ),
        GoRoute(path: '/admin/import', builder: (_, _) => const ImportScreen()),
      ],
    );
    return MaterialApp.router(
      title: 'ChargeMY',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
