import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_state.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../models/notification_model.dart';
import '../../../models/order_model.dart';
import 'order_details_screen.dart';

/// PART 14.4 — the customer-facing Notifications tab, and the "full
/// integration" piece that finally connects PART 14.1's live order
/// tracker to PART 14.3's [NotificationService].
///
/// Two independent jobs live in this one screen, matching the part's
/// own final-breakdown table ("notifications_screen.dart — UI + full
/// integration"):
///
/// 1. **Display** — a real-time list of this customer's notifications
///    via [NotificationService.streamUserNotifications], with
///    read/unread state, tap-to-mark-read, and tap-to-open-order.
/// 2. **Sync** — a second, invisible subscription
///    ([_watchOrderStatusChanges]) on this customer's *orders*
///    ([OrderRepository.streamOrdersForUser]) that is what actually
///    creates each status-change notification the moment Firestore
///    reports a new status — no Admin screen exists yet to call
///    [NotificationService.notifyStatusChange] directly (that's PART
///    16), so the customer's own app is what watches for the change
///    and creates the notification for it.
///
/// This screen is kept alive for the whole session by
/// [UserDashboard]'s `IndexedStack` (every tab is built once and kept
/// in the tree, not rebuilt on tab switch), so job 2 keeps running
/// even while the customer is looking at a different tab — the same
/// reason [OrderStatusTracker] can update live without this screen
/// being the one on screen.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.notificationService,
    this.orderRepository,
  });

  /// Injectable for widget tests; defaults to a real
  /// [NotificationService] backed by live Firestore, same pattern as
  /// every other screen in this project that takes an optional
  /// service/repository.
  final NotificationService? notificationService;
  final OrderRepository? orderRepository;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationService _notificationService =
      widget.notificationService ?? NotificationService();
  late final OrderRepository _orderRepository = widget.orderRepository ?? OrderRepository();

  /// Subscribed once here — not created inline in `build()` — for the
  /// same reason [OrderStatusTracker] does this: handing a
  /// `StreamBuilder` a brand-new `Stream` object on every rebuild
  /// makes it tear down and resubscribe instead of delivering the
  /// next event.
  Stream<List<NotificationModel>>? _notificationsStream;
  String? _streamedUserId;

  /// The order-status watcher (job 2 above). Lives independently of
  /// the notifications `StreamBuilder` — it keeps running even if
  /// this screen's list is mid-error or mid-loading.
  StreamSubscription<List<OrderModel>>? _orderSyncSubscription;

  /// This-session cache of "orderId|type" pairs already sent to
  /// [NotificationService.notifyStatusChange]. [NotificationService]
  /// itself is the real duplicate guard (it checks Firestore before
  /// every write, so it's safe even across app restarts or two
  /// devices open at once) — this set is purely a cheap first-pass
  /// filter so a snapshot that fires for an unrelated field change on
  /// an order already at a known status doesn't re-query Firestore
  /// for nothing.
  final Set<String> _handledStatusKeys = {};

  bool _isMarkingRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AuthState.instance.firebaseUser?.uid;
    if (userId != null && userId != _streamedUserId) {
      _streamedUserId = userId;
      _notificationsStream = _notificationService.streamUserNotifications(userId);
      _startOrderStatusSync(userId);
    }
  }

  @override
  void dispose() {
    _orderSyncSubscription?.cancel();
    super.dispose();
  }

  // -------------------- Job 2: order status → notification --------------------

  /// Starts (or restarts, if the signed-in user changed) the
  /// background subscription that turns a live order-status change
  /// into a notification.
  void _startOrderStatusSync(String userId) {
    _orderSyncSubscription?.cancel();
    _handledStatusKeys.clear();
    _orderSyncSubscription = _orderRepository.streamOrdersForUser(userId).listen(
      (orders) {
        for (final order in orders) {
          _maybeNotifyStatus(order);
        }
      },
      // A dropped connection or a missing index here shouldn't crash
      // the app in the background — the visible notifications list
      // below already tells the customer when something's wrong via
      // its own StreamBuilder.
      onError: (Object _) {},
    );
  }

  /// Creates the status-change notification for [order]'s *current*
  /// status if one doesn't already exist. Called for every order on
  /// every snapshot, but almost always a no-op thanks to
  /// [_handledStatusKeys] and, underneath that,
  /// [NotificationService]'s own Firestore-level duplicate check.
  ///
  /// [NotificationService.notificationTypeForStatus] returns null for
  /// [OrderStatus.pending] (that moment is handled once at order
  /// creation — see [notifyOrderCreated] in the summary screen) and
  /// [OrderStatus.cancelled] (out of scope until PART 16), so those
  /// two statuses never reach [NotificationService.notifyStatusChange]
  /// at all — this is this screen's "handle cancelled orders
  /// separately" requirement: a cancelled order simply generates no
  /// status notification here, the same way it generates no step in
  /// [OrderStatusTracker]'s normal progress line.
  void _maybeNotifyStatus(OrderModel order) {
    final orderId = order.id;
    if (orderId == null) return; // missing order information — nothing to key on

    final type = NotificationService.notificationTypeForStatus(order.status);
    if (type == null) return;

    final key = '$orderId|${type.value}';
    if (_handledStatusKeys.contains(key)) return;
    _handledStatusKeys.add(key);

    // Fire-and-forget: a failure here (offline, permission hiccup)
    // shouldn't surface as an error on this screen — worst case, the
    // key stays out of the cache and the next snapshot retries it.
    _notificationService.notifyStatusChange(order: order, type: type).catchError((Object _) {
      _handledStatusKeys.remove(key);
      return null;
    });
  }

  // -------------------- Job 1: display --------------------

  Future<void> _openNotification(NotificationModel notification) async {
    if (_isMarkingRead) return;

    if (!notification.isRead && notification.notificationId != null) {
      setState(() => _isMarkingRead = true);
      try {
        await _notificationService.markAsRead(notification.notificationId!);
      } catch (_) {
        // Non-fatal — the notification just stays marked unread; the
        // customer can still open the order below.
      } finally {
        if (mounted) setState(() => _isMarkingRead = false);
      }
    }

    if (!mounted) return;

    if (notification.orderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This notification has no linked order.')),
      );
      return;
    }

    OrderModel? order;
    try {
      order = await _orderRepository.getOrderByDocId(notification.orderId);
    } on FirebaseException {
      order = null;
    }

    if (!mounted) return;

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That order could not be found.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? userId = AuthState.instance.firebaseUser?.uid;
    final stream = _notificationsStream;

    if (userId == null || stream == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const ErrorState(message: 'Your session has expired. Please log in again.'),
      );
    }

    // Captured as a definitely-non-null local so the retry callback
    // below (used inside a nested StreamBuilder closure) doesn't rely
    // on flow-analysis promotion carrying through the closure.
    final String currentUserId = userId;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<NotificationModel>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Unable to load notifications. Please check your connection.',
              onRetry: () => setState(() {
                _notificationsStream =
                    _notificationService.streamUserNotifications(currentUserId);
              }),
            );
          }

          final notifications = snapshot.data ?? const <NotificationModel>[];
          if (notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'No notifications yet',
              message: 'Updates about your orders will show up here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _NotificationTile(
                notification: notifications[index],
                onTap: () => _openNotification(notifications[index]),
              );
            },
          );
        },
      ),
    );
  }
}

/// A single notification row: icon, title, message, order number,
/// date/time, and an unread indicator. Purely presentational — all
/// behavior (mark-as-read, navigation) is owned by the parent screen.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.orderCreated:
        return Icons.receipt_long_outlined;
      case NotificationType.received:
        return Icons.inventory_2_outlined;
      case NotificationType.washing:
        return Icons.local_laundry_service_outlined;
      case NotificationType.drying:
        return Icons.dry_outlined;
      case NotificationType.ready:
        return Icons.check_circle_outline;
      case NotificationType.completed:
        return Icons.task_alt_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUnread = !notification.isRead;

    return Material(
      color: isUnread ? colors.primaryContainer.withValues(alpha: 0.35) : colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.primary.withValues(alpha: 0.12),
                child: Icon(_iconFor(notification.type), color: colors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8, top: 4),
                            decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${notification.orderNumber} · ${_formatDateTime(notification.createdAt)}',
                      style: textTheme.bodySmall?.copyWith(color: colors.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same manual "Sep 12, 2026 · 3:45 PM" formatting `order_list_tile.dart`
/// uses, kept local to this file rather than shared — a null
/// [DateTime] here means the server timestamp hasn't round-tripped
/// back down yet (right after creation), so "Just now" is accurate
/// rather than a fallback.
String _formatDateTime(DateTime? date) {
  if (date == null) return 'Just now';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final period = date.hour >= 12 ? 'PM' : 'AM';
  final minute = date.minute.toString().padLeft(2, '0');
  return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour12:$minute $period';
}