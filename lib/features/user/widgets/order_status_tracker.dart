import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import 'order_list_tile.dart' show OrderStatusStyle;

/// PART 14.1 — real-time order status tracker.
///
/// Takes only an [orderId] (the Firestore document ID) rather than a
/// static [OrderModel], and owns its own live Firestore subscription
/// via [OrderRepository.streamOrderById]. That's what makes this a
/// genuine *tracker* rather than a plain status label: whenever an
/// Admin changes this order's status in Firestore (PART 16), this
/// widget's [StreamBuilder] rebuilds on its own — no pull-to-refresh,
/// no re-navigating into the screen, nothing the customer has to do.
///
/// Deliberately read-only per this part's spec: no status-changing
/// buttons, no Admin controls, no notification wiring yet (that's
/// PART 14.2–14.4). This widget's only job is "show me where my order
/// is right now, live."
class OrderStatusTracker extends StatefulWidget {
  const OrderStatusTracker({super.key, required this.orderId, this.orderRepository});

  /// Firestore document ID of the order to track — *not* the
  /// human-readable `orderNumber`, since [OrderRepository.streamOrderById]
  /// reads by document ID the same way [OrderDatasource.getOrderByDocId]
  /// already does elsewhere in the app.
  final String orderId;

  /// Injectable for widget tests; defaults to a real [OrderRepository]
  /// backed by live Firestore, same pattern as every other screen in
  /// this project that takes an optional repository.
  final OrderRepository? orderRepository;

  @override
  State<OrderStatusTracker> createState() => _OrderStatusTrackerState();
}

class _OrderStatusTrackerState extends State<OrderStatusTracker> {
  late final OrderRepository _orderRepository = widget.orderRepository ?? OrderRepository();

  /// Subscribed once here — not called inline inside `build()` — so
  /// this widget doesn't repeat the exact bug just fixed on
  /// [AdminDashboard]/[MyOrdersScreen]: calling a `stream*` repository
  /// method directly in `build` hands the `StreamBuilder` a brand-new
  /// `Stream` object on every rebuild, which makes it tear down and
  /// resubscribe instead of just delivering the next event. That would
  /// be especially bad here, since this widget's entire purpose is to
  /// rebuild often as new statuses arrive.
  late final Stream<OrderModel?> _orderStream =
      _orderRepository.streamOrderById(widget.orderId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrderModel?>(
      stream: _orderStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingWidget(message: 'Loading order status...');
        }

        if (snapshot.hasError) {
          return const ErrorState(
            message: 'Unable to load order status. Please check your connection.',
          );
        }

        final order = snapshot.data;
        if (order == null) {
          return const ErrorState(
            title: 'Order not found',
            message: 'This order could not be found. It may have been removed.',
          );
        }

        if (order.status == OrderStatus.cancelled) {
          return const _CancelledBanner();
        }

        return _StatusProgress(currentStatus: order.status);
      },
    );
  }
}

/// The six ordinary workflow steps, in order. [OrderStatus.cancelled]
/// is deliberately excluded — it's a separate terminal state handled
/// by [_CancelledBanner], not a step on this line.
const _kWorkflowSteps = [
  OrderStatus.pending,
  OrderStatus.received,
  OrderStatus.washing,
  OrderStatus.drying,
  OrderStatus.ready,
  OrderStatus.completed,
];

/// Current-status header + the full step-by-step progress line —
/// previous steps checked off, the current step highlighted, future
/// steps dimmed.
class _StatusProgress extends StatelessWidget {
  const _StatusProgress({required this.currentStatus});

  final OrderStatus currentStatus;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final currentIndex = _kWorkflowSteps.indexOf(currentStatus);
    final currentStyle = OrderStatusStyle.of(currentStatus);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: currentStyle.color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Status',
                      style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    Text(
                      currentStyle.label,
                      style: textTheme.titleMedium?.copyWith(
                        color: currentStyle.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // currentIndex is -1 only if currentStatus somehow isn't one
          // of the six workflow steps — can't happen for a live order
          // (cancelled is filtered out before this widget is built),
          // but guard against it so a bad/legacy status document
          // renders every step as "not yet reached" instead of
          // crashing on a negative index below.
          for (var i = 0; i < _kWorkflowSteps.length; i++)
            _StepRow(
              step: _kWorkflowSteps[i],
              isDone: currentIndex >= 0 && i < currentIndex,
              isCurrent: i == currentIndex,
              isLast: i == _kWorkflowSteps.length - 1,
            ),
        ],
      ),
    );
  }
}

/// One row of the vertical step line: a circle (checked / highlighted
/// / empty) connected to the next row by a vertical bar, plus the
/// step's label.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
  });

  final OrderStatus step;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = OrderStatusStyle.of(step);
    final isReached = isDone || isCurrent;
    final circleColor = isReached ? style.color : colors.outlineVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isReached ? circleColor : Colors.transparent,
                  border: Border.all(color: circleColor, width: 2),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : isCurrent
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          )
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone ? circleColor : colors.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 2),
              child: Text(
                style.label,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isReached ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of [_StatusProgress] whenever the order's status is
/// [OrderStatus.cancelled] — per this part's spec, cancelled orders
/// are a separate final state, not "stuck" at whichever workflow step
/// they were on when cancelled, so no partial progress line is drawn.
class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cancel_outlined, color: colors.error, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order Cancelled',
                  style: textTheme.titleMedium?.copyWith(
                    color: colors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This order was cancelled and will not proceed further.',
                  style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}