import 'package:flutter/material.dart';

import '../../../core/services/auth_state.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import '../widgets/order_list_tile.dart';
import 'order_details_screen.dart';

/// PART 13 — the customer's order history, split into tabs. All
/// filtering by "own orders only" happens at the query level in
/// [OrderRepository.streamOrdersForUser] (filtered by the
/// authenticated user's ID); tab filtering (Pending / Processing /
/// Ready / Completed) happens client-side over that one stream so a
/// single Firestore listener backs the whole screen.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  final OrderRepository _orderRepository = OrderRepository();
  late final TabController _tabController;

  static const _tabs = ['All', 'Pending', 'Processing', 'Ready', 'Completed'];

  /// Cached here — not built inline in [build] — for the same reason
  /// `NotificationsScreen` caches its own stream: handing
  /// `StreamBuilder` a brand-new `Stream` object on every rebuild
  /// makes it tear down and resubscribe from Firestore instead of
  /// just delivering the next event, which both wastes a listener and
  /// can destabilize the shared Firestore client's internal state.
  /// Only recreated if the signed-in user actually changes.
  Stream<List<OrderModel>>? _ordersStream;
  String? _streamedUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AuthState.instance.firebaseUser?.uid;
    if (userId != null && userId != _streamedUserId) {
      _streamedUserId = userId;
      _ordersStream = _orderRepository.streamOrdersForUser(userId);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// PART 13 — "Processing" groups received/washing/drying into one
  /// tab, matching the workflow stages between Pending and Ready.
  /// Compares against [OrderStatus] enum values, not raw strings,
  /// since that's what [OrderModel.status] actually is.
  List<OrderModel> _filter(List<OrderModel> orders, int tabIndex) {
    switch (tabIndex) {
      case 1:
        return orders.where((o) => o.status == OrderStatus.pending).toList();
      case 2:
        return orders
            .where((o) => [
                  OrderStatus.received,
                  OrderStatus.washing,
                  OrderStatus.drying,
                ].contains(o.status))
            .toList();
      case 3:
        return orders.where((o) => o.status == OrderStatus.ready).toList();
      case 4:
        return orders.where((o) => o.status == OrderStatus.completed).toList();
      case 0:
      default:
        return orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = AuthState.instance.firebaseUser?.uid;
    final stream = _ordersStream;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: (userId == null || stream == null)
          ? const ErrorState(message: 'Your session has expired. Please log in again.')
          : StreamBuilder<List<OrderModel>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingWidget();
                }
                if (snapshot.hasError) {
                  return ErrorState(
                    message: 'Unable to load your orders. Please try again.',
                    onRetry: () => setState(() {
                      _ordersStream = _orderRepository.streamOrdersForUser(userId);
                    }),
                  );
                }

                final orders = snapshot.data ?? const <OrderModel>[];
                if (orders.isEmpty) {
                  return const EmptyState(
                    title: "You haven't placed any orders yet.",
                    icon: Icons.receipt_long_outlined,
                  );
                }

                return TabBarView(
                  controller: _tabController,
                  children: List.generate(_tabs.length, (tabIndex) {
                    final filtered = _filter(orders, tabIndex);
                    if (filtered.isEmpty) {
                      return const EmptyState(
                        title: 'No orders in this category yet.',
                        icon: Icons.filter_list_off,
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async => setState(() {}),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return OrderListTile(
                            order: order,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderDetailsScreen(order: order),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                );
              },
            ),
    );
  }
}