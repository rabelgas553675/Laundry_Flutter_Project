import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../widgets/dashboard_stat_card.dart';

/// PART 15 — the real Admin Dashboard. Every stat, summary, and list
/// below is computed from live Firestore data via [OrderRepository]
/// and [UserRepository] — nothing here is placeholder/hard-coded, per
/// the spec's "All statistics must come from Firestore" requirement.
///
/// Reachable only through the `adminDashboard` route, which
/// [RoleGuard] (PART 05) already restricts to [UserRole.admin] — this
/// screen does no role checking of its own.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final OrderRepository _orderRepository = OrderRepository();
  final UserRepository _userRepository = UserRepository();

  // FIX: these used to be created inline as `_orderRepository.streamAllOrders()`
  // / `_userRepository.streamAllUsers()` directly inside `build()`'s
  // `StreamBuilder(stream: ...)`. Every time either stream emitted new
  // data, StreamBuilder called setState -> build() ran again -> a brand
  // new Stream instance was created -> StreamBuilder tore down its
  // subscription and resubscribed. That caused the dashboard to flicker
  // back to the loading state on every Firestore update (and burned
  // extra reads/connections).
  //
  // Caching the streams as state fields means they're created exactly
  // once, and only ever replaced explicitly (on retry), so
  // StreamBuilder keeps a single live subscription per stream.
  late Stream<List<OrderModel>> _ordersStream = _orderRepository.streamAllOrders();
  late Stream<List<UserModel>> _usersStream = _userRepository.streamAllUsers();

  void _retryOrders() {
    setState(() => _ordersStream = _orderRepository.streamAllOrders());
  }

  void _retryUsers() {
    setState(() => _usersStream = _userRepository.streamAllUsers());
  }

  Future<void> _handleLogout(BuildContext context) async {
    await AuthState.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Manage Orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.manageOrders),
          ),
          // PART 19A — quick access to the reporting system, same
          // shape as the Manage Orders shortcut above.
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.reports),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<OrderModel>>(
          stream: _ordersStream,
          builder: (context, orderSnapshot) {
            if (orderSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading orders...');
            }
            if (orderSnapshot.hasError) {
              return ErrorState(
                message: 'Unable to load orders. Please try again.',
                onRetry: _retryOrders,
              );
            }

            final orders = orderSnapshot.data ?? const <OrderModel>[];

            return StreamBuilder<List<UserModel>>(
              stream: _usersStream,
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingWidget(message: 'Loading users...');
                }
                if (userSnapshot.hasError) {
                  return ErrorState(
                    message: 'Unable to load users. Please try again.',
                    onRetry: _retryUsers,
                  );
                }

                final users = userSnapshot.data ?? const <UserModel>[];
                return _DashboardContent(orders: orders, users: users);
              },
            );
          },
        ),
      ),
    );
  }
}

/// The actual dashboard body once both streams have data — split out
/// so [_AdminDashboardState.build] stays readable, and every stat
/// below is derived fresh from whatever the latest snapshot pair is.
class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.orders, required this.users});

  final List<OrderModel> orders;
  final List<UserModel> users;

  @override
  Widget build(BuildContext context) {
    final totalUsers = users.length;
    final totalOrders = orders.length;
    final pendingOrders =
        orders.where((o) => o.status == OrderStatus.pending).length;

    // Revenue counts only completed orders — a pending/washing order's
    // total isn't money the shop has actually earned yet, and a
    // cancelled order never will be.
    final totalRevenue = orders
        .where((o) => o.status == OrderStatus.completed)
        .fold<double>(0, (sum, o) => sum + o.total);

    // Both lists already arrive newest-first from their repositories'
    // `orderBy('createdAt', descending: true)` queries, so "recent"
    // here is just "the first 5".
    final recentOrders = orders.take(5).toList();
    final recentUsers = users.take(5).toList();

    final statusCounts = <OrderStatus, int>{
      for (final status in OrderStatus.values)
        status: orders.where((o) => o.status == status).length,
    };

    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 900 ? 32.0 : 16.0;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: width > 600 ? 4 : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            DashboardStatCard(
              label: 'Total Users',
              value: '$totalUsers',
              icon: Icons.people_outline,
            ),
            DashboardStatCard(
              label: 'Total Orders',
              value: '$totalOrders',
              icon: Icons.receipt_long_outlined,
            ),
            DashboardStatCard(
              label: 'Pending Orders',
              value: '$pendingOrders',
              icon: Icons.pending_actions_outlined,
              iconColor: Colors.orange,
            ),
            DashboardStatCard(
              label: 'Total Revenue',
              value: PriceCalculator.formatCurrency(totalRevenue),
              icon: Icons.payments_outlined,
              iconColor: Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // PART 16 — the primary way into Admin Order Management; the
        // AppBar icon above is the quick/secondary path for anyone
        // already familiar with the app.
        AppButton(
          label: 'Manage Orders',
          icon: Icons.receipt_long_outlined,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.manageOrders),
        ),
        const SizedBox(height: 12),
        // PART 19A — the primary way into Admin Reports; the AppBar
        // icon above is the quick/secondary path, same reasoning as
        // Manage Orders' own pair of entry points.
        AppButton(
          label: 'View Reports',
          icon: Icons.bar_chart_outlined,
          variant: AppButtonVariant.outlined,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.reports),
        ),
        const SizedBox(height: 12),
        // BUG FIX — AppRoutes.manageServices / manageUsers /
        // managePromos, and their screens (ManageServicesScreen,
        // ManageUsersScreen, ManagePromosScreen), were all fully
        // built and registered in routes.dart, but nothing in the
        // app ever navigated to them — no button, no icon, no menu
        // entry anywhere. They were only reachable by typing the
        // route path directly. Wiring them up here the same way
        // Manage Orders / Reports already are.
        AppButton(
          label: 'Manage Services',
          icon: Icons.local_laundry_service_outlined,
          variant: AppButtonVariant.outlined,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.manageServices),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Manage Users',
          icon: Icons.people_outline,
          variant: AppButtonVariant.outlined,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.manageUsers),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Manage Promos',
          icon: Icons.local_offer_outlined,
          variant: AppButtonVariant.outlined,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.managePromos),
        ),
        const SizedBox(height: 24),
        Text('Order Status Summary', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: statusCounts.entries.map((entry) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.value}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                StatusBadge(status: entry.key.value),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Text('Recent Orders', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (recentOrders.isEmpty)
          const EmptyState(
            title: 'No orders yet',
            message: 'Placed orders will show up here.',
            icon: Icons.receipt_long_outlined,
          )
        else
          ...recentOrders.map((order) => _RecentOrderTile(order: order)),
        const SizedBox(height: 24),
        Text('Recent Users', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (recentUsers.isEmpty)
          const EmptyState(
            title: 'No users yet',
            message: 'Newly registered customers will show up here.',
            icon: Icons.people_outline,
          )
        else
          ...recentUsers.map((user) => _RecentUserTile(user: user)),
      ],
    );
  }
}

/// One row in "Recent Orders" — order number, service + weight,
/// total, and a status badge.
class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNumber,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.serviceName} · '
                  '${order.isItemized ? '${order.items.length} item type(s)' : ServiceUnitFormat.formatQuantity(order.serviceUnit, order.weight)}',
                  style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                PriceCalculator.formatCurrency(order.total),
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              StatusBadge(status: order.status.value),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row in "Recent Users" — avatar, name, email, role, and
/// registration date.
class _RecentUserTile extends StatelessWidget {
  const _RecentUserTile({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.primaryContainer,
            backgroundImage:
                user.profileImageUrl != null ? NetworkImage(user.profileImageUrl!) : null,
            child: user.profileImageUrl == null
                ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?')
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isEmpty ? '—' : user.name,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(user.email, style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(status: user.role == UserRole.admin ? 'Admin' : 'User'),
              const SizedBox(height: 6),
              Text(
                _formatShortDate(user.createdAt),
                style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Sep 12, 2026" — used only for the recent-users registration date.
String _formatShortDate(DateTime? date) {
  if (date == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}