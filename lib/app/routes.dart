import 'package:flutter/material.dart';

import '../core/widgets/role_guard.dart';
import '../features/authentication/screens/login_screen.dart';
import '../features/authentication/screens/register_screen.dart';
import '../features/user/screens/user_dashboard.dart';
import '../features/user/screens/laundry_order_screen.dart';
import '../features/admin/screens/admin_dashboard.dart';
import '../features/admin/screens/manage_orders_screen.dart';
import '../features/admin/screens/manage_services_screen.dart';
import '../features/admin/screens/manage_users_screen.dart';
import '../features/admin/screens/manage_promos_screen.dart';
import '../features/admin/screens/reports_screen.dart';
import '../models/user_model.dart';
import 'auth_gate.dart';
import '../features/authentication/screens/forgot_password_screen.dart';
import '../features/splash/screens/splash_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  // Session/role resolution that used to live directly at [home] now
  // lives here — [home] plays the one-time splash animation first,
  // then hands off to this route. Reached only via
  // pushReplacementNamed from SplashScreen, never pushed directly.
  static const String gate = '/gate';
  static const String login = '/login';
  static const String register = '/register';
  static const String userDashboard = '/user-dashboard';
  static const String adminDashboard = '/admin-dashboard';
  static const String forgotPassword = '/forgot-password';
  static const String laundryOrder = '/laundry-order';
  static const String manageOrders = '/admin-manage-orders';
  static const String manageServices = '/admin-manage-services';
  static const String manageUsers = '/admin-manage-users';
  static const String managePromos = '/admin-manage-promos';
  static const String reports = '/admin-reports';

  static Map<String, WidgetBuilder> get routes => {
        // Cold-start entry point — plays the splash/welcome
        // animation once, then replaces itself with [gate].
        home: (context) => const SplashScreen(),
        // Resolves the session and hands off to Login or the right
        // dashboard. See [AuthGate]. This used to be what [home]
        // pointed at directly.
        gate: (context) => const AuthGate(),
        login: (context) => const LoginScreen(),
        register: (context) => const RegisterScreen(),
        // Any authenticated user (role: user OR admin) can reach the user
        // dashboard — it only needs to be UNREACHABLE while logged out
        // (Part 05.4 · Test 3). Restricting it to UserRole.user only would
        // create a redirect loop for admins, since RoleGuard's default
        // fallback for a denied role IS this same route.
        userDashboard: (context) => const RoleGuard(
              allowedRoles: {UserRole.user, UserRole.admin},
              child: UserDashboard(),
            ),
        // Admin-only. A normal user hitting this route directly gets
        // bounced to the user dashboard (Part 05.4 · Test 4).
        adminDashboard: (context) => const RoleGuard(
              allowedRoles: {UserRole.admin},
              child: AdminDashboard(),
            ),
        forgotPassword: (context) => const ForgotPasswordScreen(),
        // Any authenticated user can place an order. Not admin-only —
        // admins aren't blocked from it either, same reasoning as
        // userDashboard above.
        laundryOrder: (context) => const RoleGuard(
              allowedRoles: {UserRole.user, UserRole.admin},
              child: LaundryOrderScreen(),
            ),
        // PART 16 — Admin-only, same guard shape as adminDashboard. A
        // normal user hitting this route directly bounces to their own
        // dashboard rather than seeing every customer's orders.
        manageOrders: (context) => const RoleGuard(
              allowedRoles: {UserRole.admin},
              child: ManageOrdersScreen(),
            ),
        // PART 17 — Admin-only, same guard shape as manageOrders.
        manageServices: (context) => const RoleGuard(
              allowedRoles: {UserRole.admin},
              child: ManageServicesScreen(),
            ),
        manageUsers: (context) => const RoleGuard(
              allowedRoles: {UserRole.admin},
              child: ManageUsersScreen(),
            ),
        // PART 18B — Admin-only, same guard shape as manageServices.
        managePromos: (context) => const RoleGuard(
              allowedRoles: {UserRole.admin},
              child: ManagePromosScreen(),
            ),
        // PART 19A — Admin-only, same guard shape as managePromos.
        // SalesReportScreen/OrderReportScreen are reached by pushing
        // from ReportsScreen (same pattern as Add/Edit Promo from
        // ManagePromosScreen), so they don't need their own named
        // routes here.
        reports: (context) => const RoleGuard(
              allowedRoles: {UserRole.admin},
              child: ReportsScreen(),
            ),
      };
}