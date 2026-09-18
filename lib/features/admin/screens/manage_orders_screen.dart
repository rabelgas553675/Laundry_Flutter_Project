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
  /// case, and the status [TabBar] moves into the body instead of
  /// living in `AppBar.bottom` (there's no AppBar to hang it off of).
  final bool embedded;

  @override
  State<ManageOrdersScreen> createState() => _ManageOrdersScreenState();
}

class _ManageOrdersScreenState extends State<ManageOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final OrderRepository _orderRepository = widget.orderRepository ?? OrderRepository();
  late final UserRepository _userRepository = widget.userRepository ?? UserRepository();

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
        builder: (_) => AdminOrderDetailsScreen(order: order, customer: customer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Built once per build() and placed in exactly one of the two
    // spots below (AppBar.bottom when standalone, inline in the body
    // when embedded) — never both at once, so there's no duplicate
    // widget-in-tree issue despite the single shared instance.
    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: true,
      tabs: _tabs.map((label) => Tab(text: label)).toList(),
    );

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Manage Orders'),
              bottom: tabBar,
            ),
      body: SafeArea(
        top: !widget.embedded,
        child: Column(
          children: [
            // No AppBar to hang the TabBar off of when embedded, so
            // it renders here instead, above the search field — same
            // visual position it occupies via AppBar.bottom when
            // standalone, just moved into the body.
            if (widget.embedded)
              Material(
                color: Colors.transparent,
                child: tabBar,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by order number, service, or customer',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<OrderModel>>(
                key: ValueKey('orders-$_retryToken'),
                stream: _orderRepository.streamAllOrders(),
                builder: (context, orderSnapshot) {
                  if (orderSnapshot.connectionState == ConnectionState.waiting) {
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
                      if (userSnapshot.connectionState == ConnectionState.waiting) {
                        return const LoadingWidget(message: 'Loading customers...');
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
                          final filtered = _filterBySearch(byTab, usersById, _query);

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
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    );
  }
}