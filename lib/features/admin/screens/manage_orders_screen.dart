import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../widgets/admin_order_card.dart';
import 'admin_order_details.dart';

const Color _kBrandBlue = Color(0xFF0D47A1);

/// PART 16 — Admin Order Management.
///
/// Reads the exact same two live Firestore streams PART 15's
/// [AdminDashboard] already uses ([OrderRepository.streamAllOrders]
/// and [UserRepository.streamAllUsers]) and joins them client-side
/// into `userId -> UserModel`, so every order card can show *who*
/// placed it without an extra read per order. Search and the status
/// tabs are both applied on top of that single joined snapshot — one
/// pair of listeners backs the whole screen, the same "one stream,
/// many views" shape [MyOrdersScreen] uses for its own tabs.
///
/// Reachable through the `manageOrders` route, which [RoleGuard]
/// (PART 05) already restricts to [UserRole.admin] — this screen does
/// no role checking of its own — and also embedded directly as one of
/// [AdminDashboard]'s bottom-nav tabs (see [embedded]).
///
/// Visual shell: frosted-glass background/app bar/search/tab pill,
/// matching the language established in `admin_order_details.dart`.
class ManageOrdersScreen extends StatefulWidget {
  const ManageOrdersScreen({
    super.key,
    this.orderRepository,
    this.userRepository,
    this.embedded = false,
  });

  /// Injectable for widget tests; defaults to real repositories
  /// backed by live Firestore, same pattern as every other screen in
  /// this project that takes an optional repository.
  final OrderRepository? orderRepository;
  final UserRepository? userRepository;

  /// When `true`, shown as one tab of [AdminDashboard]'s bottom-nav
  /// `IndexedStack` — no own `Scaffold`/`AppBar` is drawn in that
  /// case, and the status tab pill moves into the body instead of
  /// living in the glass app bar (there's no app bar to hang it off
  /// of).
  final bool embedded;

  @override
  State<ManageOrdersScreen> createState() => _ManageOrdersScreenState();
}

class _ManageOrdersScreenState extends State<ManageOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final OrderRepository _orderRepository =
      widget.orderRepository ?? OrderRepository();
  late final UserRepository _userRepository =
      widget.userRepository ?? UserRepository();

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Bumped by the ErrorState "Retry" buttons to force both
  /// StreamBuilders to resubscribe — same pattern as
  /// [AdminDashboard]'s `_retryToken`.
  int _retryToken = 0;

  /// One tab per status, "All" first — matches this part's filter
  /// list exactly (All, Pending, Received, Washing, Drying, Ready,
  /// Completed, Cancelled). Index 0 is "All"; index `i` (i >= 1) maps
  /// to `OrderStatus.values[i - 1]`.
  static const _tabs = [
    'All',
    'Pending',
    'Received',
    'Washing',
    'Drying',
    'Ready',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Tab filter — client-side over the single joined snapshot, same
  /// reasoning [MyOrdersScreen] already gives for doing this instead
  /// of four/eight separate Firestore queries.
  List<OrderModel> _filterByTab(List<OrderModel> orders, int tabIndex) {
    if (tabIndex == 0) return orders;
    final status = OrderStatus.values[tabIndex - 1];
    return orders.where((o) => o.status == status).toList();
  }

  /// Search filter — matches on order number, service name, and the
  /// joined customer's name/email, so an Admin can find an order by
  /// whichever detail they remember about it.
  List<OrderModel> _filterBySearch(
    List<OrderModel> orders,
    Map<String, UserModel> usersById,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return orders;

    return orders.where((order) {
      final customer = usersById[order.userId];
      return order.orderNumber.toLowerCase().contains(q) ||
          order.serviceName.toLowerCase().contains(q) ||
          (customer?.name.toLowerCase().contains(q) ?? false) ||
          (customer?.email.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _openOrder(OrderModel order, UserModel? customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AdminOrderDetailsScreen(order: order, customer: customer),
      ),
    );
  }

  Widget _buildGlassTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: _kBrandBlue,
            borderRadius: BorderRadius.circular(999),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: _kBrandBlue.withValues(alpha: 0.75),
          tabs: _tabs.map((label) => Tab(text: label)).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search by order number, service, or customer',
          prefixIcon: const Icon(Icons.search, color: _kBrandBlue),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                ),
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = _buildGlassTabBar();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.embedded
          ? null
          : _GlassAppBar(title: 'Manage Orders', tabBar: tabBar),
      body: _OrdersBackground(
        child: SafeArea(
          top: !widget.embedded,
          child: Column(
            children: [
              // No app bar to hang the tab pill off of when embedded,
              // so it renders here instead, above the search field —
              // same visual position it occupies in the glass app bar
              // when standalone, just moved into the body.
              if (widget.embedded) tabBar,
              _buildSearchField(),
              Expanded(
                child: StreamBuilder<List<OrderModel>>(
                  key: ValueKey('orders-$_retryToken'),
                  stream: _orderRepository.streamAllOrders(),
                  builder: (context, orderSnapshot) {
                    if (orderSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const LoadingWidget(message: 'Loading orders...');
                    }
                    if (orderSnapshot.hasError) {
                      return ErrorState(
                        message: 'Unable to load orders. Please try again.',
                        onRetry: () => setState(() => _retryToken++),
                      );
                    }

                    final orders = orderSnapshot.data ?? const <OrderModel>[];

                    return StreamBuilder<List<UserModel>>(
                      key: ValueKey('users-$_retryToken'),
                      stream: _userRepository.streamAllUsers(),
                      builder: (context, userSnapshot) {
                        if (userSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const LoadingWidget(
                            message: 'Loading customers...',
                          );
                        }
                        if (userSnapshot.hasError) {
                          return ErrorState(
                            message: 'Unable to load customer information. Please try again.',
                            onRetry: () => setState(() => _retryToken++),
                          );
                        }

                        final users = userSnapshot.data ?? const <UserModel>[];
                        final usersById = {for (final u in users) u.uid: u};

                        if (orders.isEmpty) {
                          return const EmptyState(
                            title: 'No orders yet',
                            message: 'Placed orders will show up here.',
                            icon: Icons.receipt_long_outlined,
                          );
                        }

                        return TabBarView(
                          controller: _tabController,
                          children: List.generate(_tabs.length, (tabIndex) {
                            final byTab = _filterByTab(orders, tabIndex);
                            final filtered = _filterBySearch(
                              byTab,
                              usersById,
                              _query,
                            );

                            if (filtered.isEmpty) {
                              return EmptyState(
                                title: _query.isEmpty
                                    ? 'No orders in this category yet.'
                                    : 'No orders match your search.',
                                icon: Icons.filter_list_off,
                              );
                            }

                            return RefreshIndicator(
                              onRefresh: () async => setState(() {}),
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final order = filtered[index];
                                  final customer = usersById[order.userId];
                                  return AdminOrderCard(
                                    order: order,
                                    customer: customer,
                                    onTap: () => _openOrder(order, customer),
                                  );
                                },
                              ),
                            );
                          }),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft gradient + blurred brand-blue blobs behind the list — same
/// decorative language as [AdminOrderDetailsScreen]'s background.
class _OrdersBackground extends StatelessWidget {
  const _OrdersBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF0A1128), Color(0xFF0D1B3E)]
                  : const [Color(0xFFEAF2FF), Color(0xFFF7FAFF)],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: _blob(
            _kBrandBlue.withValues(alpha: isDark ? 0.35 : 0.28),
            220,
          ),
        ),
        Positioned(
          bottom: -110,
          left: -70,
          child: _blob(
            const Color(0xFF64B5F6).withValues(alpha: isDark ? 0.28 : 0.22),
            260,
          ),
        ),
        child,
      ],
    );
  }

  Widget _blob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// Frosted glass app bar with the status tab pill built into its
/// bottom edge, so the whole toolbar + tabs region reads as one
/// glass surface.
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassAppBar({required this.title, required this.tabBar});

  final String title;
  final Widget tabBar;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + 56);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: kToolbarHeight,
                  child: Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _kBrandBlue,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                tabBar,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
