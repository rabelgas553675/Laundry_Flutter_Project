import 'package:flutter/material.dart';

import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';

/// PART 14+ — "Active Orders" dashboard card, now backed by real
/// Firestore data instead of [PlaceholderActiveOrder]/[OrderStage].
///
/// The reference design's progress bar has 4 stages (Picked / Washing
/// / Out for delivery / Delivered), but the real [OrderStatus] enum
/// has 6 non-terminal steps (pending → received → washing → drying →
/// ready → completed) plus a separate terminal [OrderStatus.cancelled].
/// So two statuses collapse onto each bar stage:
///
///   Picked            ← pending, received
///   Washing            ← washing, drying
///   Out for delivery   ← ready
///   Delivered          ← completed
///
/// [OrderStatus.cancelled] doesn't map onto this bar at all — a
/// cancelled order isn't "stuck" at whatever step it was cancelled
/// from, it's a separate terminal state (same reasoning
/// [OrderStatusTracker]'s `_CancelledBanner` already uses). Callers
/// should filter cancelled orders out before reaching this widget —
/// [ActiveOrdersSection] below does exactly that — but if one slips
/// through anyway, this card still renders sensibly rather than
/// crashing: red "Cancelled" badge, bar clamped to stage 0.
enum _BarStage { picked, washing, outForDelivery, delivered }

extension _BarStageLabel on _BarStage {
  String get label {
    switch (this) {
      case _BarStage.picked:
        return 'Picked';
      case _BarStage.washing:
        return 'Washing';
      case _BarStage.outForDelivery:
        return 'Out for delivery';
      case _BarStage.delivered:
        return 'Delivered';
    }
  }
}

_BarStage _barStageForStatus(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
    case OrderStatus.received:
      return _BarStage.picked;
    case OrderStatus.washing:
    case OrderStatus.drying:
      return _BarStage.washing;
    case OrderStatus.ready:
      return _BarStage.outForDelivery;
    case OrderStatus.completed:
      return _BarStage.delivered;
    case OrderStatus.cancelled:
      // Shouldn't reach the UI (see class doc above) — clamp to the
      // first stage rather than throwing.
      return _BarStage.picked;
  }
}

String _headlineForStatus(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return 'Your order has been placed.';
    case OrderStatus.received:
      return 'Your order is picked.';
    case OrderStatus.washing:
      return 'Your order is being washed.';
    case OrderStatus.drying:
      return 'Your order is drying.';
    case OrderStatus.ready:
      return 'Your order is out for delivery.';
    case OrderStatus.completed:
      return 'Your order has been delivered.';
    case OrderStatus.cancelled:
      return 'Your order was cancelled.';
  }
}

/// Formats [kg] without a trailing ".0" for whole-number weights
/// (e.g. `4` instead of `4.0`), but keeps one decimal place otherwise
/// (e.g. `4.5`) — [OrderModel.weight] is a `double` since the PART 10
/// form allows fractional kilograms.
String _weightLabel(double kg) {
  if (kg == kg.roundToDouble()) return kg.toInt().toString();
  return kg.toStringAsFixed(1);
}

/// Rough "time ago" for [dt] (usually [OrderModel.updatedAt], falling
/// back to [OrderModel.createdAt]) — replaces the old placeholder's
/// fabricated delivery ETA with something that's actually backed by a
/// real Firestore timestamp.
String? _relativeTime(DateTime? dt) {
  if (dt == null) return null;
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

/// Card matching the "Active Orders" reference design: a header row
/// with a "See all" link, then the order's headline + status badge,
/// a meta line (order number • weight • last updated), and a
/// segmented progress bar with stage labels underneath.
///
/// Takes a real [OrderModel] — the caller (typically
/// [ActiveOrdersSection]) is responsible for supplying a live,
/// non-cancelled order; this widget itself is a plain
/// [StatelessWidget] with no Firestore subscription of its own, same
/// division of responsibility as `_StatusProgress` inside
/// `OrderStatusTracker` (that widget's *parent* owns the stream).
class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({
    super.key,
    required this.order,
    this.onSeeAll,
    this.showHeader = true,
  });

  final OrderModel order;
  final VoidCallback? onSeeAll;

  /// Set false when rendering more than one card in a list — only
  /// the first card in that list should show the "Active Orders" /
  /// "See all" header row.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          // Header row: "Active Orders" + "See all"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Orders',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See all',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // The order card itself
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Headline + status badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _headlineForStatus(order.status),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 6),

              // Meta line: "Order #ORD-... • 4 kg • Updated 2 hr ago"
              Text(
                _metaLine(order),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),

              // Segmented progress bar
              _OrderProgressBar(stage: _barStageForStatus(order.status)),
            ],
          ),
        ),
      ],
    );
  }

  String _metaLine(OrderModel order) {
    final parts = <String>[
      'Order #${order.orderNumber}',
      '${_weightLabel(order.weight)} kg',
    ];
    final updated = _relativeTime(order.updatedAt ?? order.createdAt);
    if (updated != null) {
      parts.add('Updated $updated');
    }
    return parts.join(' • ');
  }
}

/// Small rounded badge — green "On-Process" for anything in progress,
/// a neutral "Delivered" once [OrderStatus.completed], and a red
/// "Cancelled" as a defensive fallback (see the class doc above for
/// why cancelled orders shouldn't normally reach this widget at all).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final MaterialColor color;
    final String text;

    switch (status) {
      case OrderStatus.completed:
        color = Colors.blueGrey;
        text = 'Delivered';
        break;
      case OrderStatus.cancelled:
        color = Colors.red;
        text = 'Cancelled';
        break;
      default:
        color = Colors.green;
        text = 'On-Process';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A horizontal track with 4 dots (one per [_BarStage]) connected by
/// a line. The portion of the line/dots up to and including the
/// current stage is filled with a soft light-purple gradient; the
/// rest stays a light neutral grey. Stage labels sit underneath each
/// dot.
class _OrderProgressBar extends StatelessWidget {
  const _OrderProgressBar({required this.stage});

  final _BarStage stage;

  // Soft light-purple used for the active portion of the progress
  // line and its dots — matches the accent color used elsewhere in
  // the app (e.g. the "Here's" text on the dashboard header).
  static const Color _activeColor = Color(0xFFB9A8F0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = _BarStage.values;
    final currentIndex = stage.index;
    // Fraction of the track that should be "filled" — dots divide the
    // track into (n-1) segments, so the fill runs from the first dot
    // through however many segments are complete.
    final fraction = stages.length <= 1 ? 1.0 : currentIndex / (stages.length - 1);

    const activeColor = _activeColor;
    const inactiveColor = Color(0xFFE3E3E8);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            const dotSize = 10.0;
            // Dot centers sit evenly across the width, inset by half a
            // dot on each side so the first/last dots aren't clipped.
            final usableWidth = trackWidth - dotSize;

            return SizedBox(
              height: dotSize,
              width: trackWidth,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Background (inactive) line
                  Positioned(
                    left: dotSize / 2,
                    right: dotSize / 2,
                    child: Container(height: 3, color: inactiveColor),
                  ),
                  // Foreground (active) line, gradient fill up to
                  // current stage
                  Positioned(
                    left: dotSize / 2,
                    width: usableWidth * fraction,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            activeColor,
                            activeColor.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Dots
                  for (var i = 0; i < stages.length; i++)
                    Positioned(
                      left: (usableWidth * (i / (stages.length - 1))),
                      child: _StageDot(
                        filled: i <= currentIndex,
                        size: dotSize,
                        color: activeColor,
                        inactiveColor: inactiveColor,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < stages.length; i++)
              Expanded(
                child: Text(
                  stages[i].label,
                  textAlign: i == 0
                      ? TextAlign.left
                      : (i == stages.length - 1 ? TextAlign.right : TextAlign.center),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: i == currentIndex ? FontWeight.w700 : FontWeight.w500,
                    color: i <= currentIndex
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({
    required this.filled,
    required this.size,
    required this.color,
    required this.inactiveColor,
  });

  final bool filled;
  final double size;
  final Color color;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.white,
        border: Border.all(
          color: filled ? color : inactiveColor,
          width: 2,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
    );
  }
}

/// Live "Active Orders" dashboard section — owns the Firestore
/// subscription so [ActiveOrderCard] itself can stay a plain,
/// stateless, easily-testable widget.
///
/// Subscribes once via a `late final` stream field rather than
/// calling [OrderRepository.streamOrdersForUser] inline inside
/// `build()` — the exact bug already fixed on
/// AdminDashboard/MyOrdersScreen/OrderStatusTracker: calling a
/// `stream*` method directly in `build` hands `StreamBuilder` a
/// brand-new `Stream` on every rebuild, forcing it to tear down and
/// resubscribe instead of just delivering the next event.
///
/// "Active" here means: not [OrderStatus.completed] and not
/// [OrderStatus.cancelled] — i.e. still somewhere on the pending →
/// ... → ready workflow. Filtering happens client-side over
/// [OrderRepository.streamOrdersForUser]'s already-live, already
/// newest-first list, so no separate query/index is needed.
class ActiveOrdersSection extends StatefulWidget {
  const ActiveOrdersSection({
    super.key,
    required this.userId,
    this.orderRepository,
    this.onSeeAll,
    this.maxCards = 1,
  });

  final String userId;

  /// Injectable for widget tests; defaults to a real
  /// [OrderRepository] backed by live Firestore — same pattern as
  /// [OrderStatusTracker].
  final OrderRepository? orderRepository;

  final VoidCallback? onSeeAll;

  /// How many active orders to render as cards. The reference design
  /// shows one; pass a higher number to show more (e.g. "2 in
  /// progress at once").
  final int maxCards;

  @override
  State<ActiveOrdersSection> createState() => _ActiveOrdersSectionState();
}

class _ActiveOrdersSectionState extends State<ActiveOrdersSection> {
  late final OrderRepository _orderRepository = widget.orderRepository ?? OrderRepository();

  late final Stream<List<OrderModel>> _ordersStream =
      _orderRepository.streamOrdersForUser(widget.userId);

  bool _isActive(OrderModel order) =>
      order.status != OrderStatus.completed && order.status != OrderStatus.cancelled;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError) {
          // Dashboard-level section: fail quietly rather than
          // pushing a full error card into the middle of the home
          // screen — the "My Orders" tab (backed by the same stream)
          // already surfaces a real error state if the connection is
          // actually down.
          return const SizedBox.shrink();
        }

        final orders = snapshot.data ?? const <OrderModel>[];
        final active = orders.where(_isActive).take(widget.maxCards).toList();

        if (active.isEmpty) {
          // Nothing in progress right now — no card to show. Could
          // be swapped for an empty-state prompt ("Place your first
          // order") if desired.
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < active.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              ActiveOrderCard(
                order: active[i],
                onSeeAll: widget.onSeeAll,
                // Only the first card shows "Active Orders" / "See all".
                showHeader: i == 0,
              ),
            ],
          ],
        );
      },
    );
  }
}