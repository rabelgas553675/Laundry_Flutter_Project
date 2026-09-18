import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing_service.dart';
import '../../user/widgets/order_items_breakdown.dart';
import '../../user/widgets/order_list_tile.dart' show OrderStatusStyle, formatOrderDate;
import '../widgets/report_actions_row.dart';

const Color _kBrandBlue = Color(0xFF0D47A1);

/// PART 16 — full Admin view of a single order: customer information,
/// order details, delivery details, price breakdown, and status
/// controls.
///
/// Unlike PART 13's customer-facing [OrderDetailsScreen] (which only
/// tracks *status* live, via [OrderStatusTracker]), this whole screen
/// re-subscribes to [OrderRepository.streamOrderById] for its entire
/// body. That's deliberate: an Admin's status-change buttons need the
/// order's *current* status to know which transitions are still legal
/// (via [OrderRepository.allowedNextStatuses]), and re-streaming the
/// full document means this screen reflects a change instantly —
/// whether it came from this Admin's own tap below, or from a second
/// Admin acting on the same order from another device.
///
/// PART 19B adds [ReportActionsRow] — "Export PDF" / "Print" — for
/// this order's receipt. The receipt content itself is built by
/// [OrderReceiptData.fromOrder] (using this screen's already-loaded
/// [_customer]) and [PdfService]; this screen never lays out a PDF
/// or talks to the `printing` package directly.
///
/// Visual shell: frosted-glass cards over a soft gradient + blurred
/// brand-blue blobs, matching the language established in
/// `order_summary_screen.dart` / `user_dashboard.dart`.
class AdminOrderDetailsScreen extends StatefulWidget {
  const AdminOrderDetailsScreen({
    super.key,
    required this.order,
    this.customer,
    this.orderRepository,
    this.userRepository,
  });

  /// The order to show, as already known by [ManageOrdersScreen]'s
  /// list (used only to seed the document ID / initial paint — the
  /// live [StreamBuilder] below takes over immediately).
  final OrderModel order;

  /// Customer info already joined by [ManageOrdersScreen], if
  /// available — avoids a redundant Firestore read for the common
  /// case. Null falls back to [UserRepository.getUserById] below.
  final UserModel? customer;

  final OrderRepository? orderRepository;
  final UserRepository? userRepository;

  @override
  State<AdminOrderDetailsScreen> createState() => _AdminOrderDetailsScreenState();
}

class _AdminOrderDetailsScreenState extends State<AdminOrderDetailsScreen> {
  late final OrderRepository _orderRepository = widget.orderRepository ?? OrderRepository();
  late final UserRepository _userRepository = widget.userRepository ?? UserRepository();

  late final Stream<OrderModel?> _orderStream =
      _orderRepository.streamOrderById(widget.order.id ?? '');

  UserModel? _customer;
  bool _isLoadingCustomer = false;
  bool _isUpdatingStatus = false;

  /// True while PART 19B's receipt PDF export/print is in flight —
  /// see [ReportActionsRow.isBusy].
  bool _isProcessingReceipt = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    if (_customer == null) {
      _loadCustomer();
    }
  }

  Future<void> _loadCustomer() async {
    setState(() => _isLoadingCustomer = true);
    try {
      final user = await _userRepository.getUserById(widget.order.userId);
      if (!mounted) return;
      setState(() => _customer = user);
    } catch (_) {
      // Non-fatal — the customer card below just shows a fallback.
    } finally {
      if (mounted) setState(() => _isLoadingCustomer = false);
    }
  }

  Future<bool> _confirmCancel() async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Cancel this order?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kBrandBlue),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This will mark the order as cancelled. This cannot be undone.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep Order'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.errorContainer,
                          foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Cancel Order'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _updateStatus(OrderModel order, OrderStatus newStatus) async {
    if (_isUpdatingStatus) return;

    if (newStatus == OrderStatus.cancelled) {
      final confirmed = await _confirmCancel();
      if (!confirmed) return;
    }

    setState(() => _isUpdatingStatus = true);
    try {
      await _orderRepository.updateOrderStatus(order: order, newStatus: newStatus);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order ${order.orderNumber} updated to ${OrderStatusStyle.of(newStatus).label}.',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to update the order status.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  /// PART 19B — Order Receipt PDF, built via
  /// [OrderReceiptData.fromOrder] (the *only* place that decides what
  /// "payment status" text a receipt shows, since [OrderModel] has no
  /// dedicated payment-status field) and [PdfService], then handed to
  /// [PrintingService] to export or print.
  Future<void> _handleReceiptAction({required OrderModel order, required bool openPrintDialog}) async {
    if (_isProcessingReceipt) return;
    setState(() => _isProcessingReceipt = true);
    try {
      final receipt = OrderReceiptData.fromOrder(order, customer: _customer);
      final bytes = await PdfService.buildOrderReceiptPdf(receipt);
      if (openPrintDialog) {
        await PrintingService.printPdf(bytes: bytes, documentName: 'Receipt ${order.orderNumber}');
      } else {
        await PrintingService.exportPdf(
          bytes: bytes,
          fileName: PdfService.receiptFileName(order.orderNumber),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to generate the receipt. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isProcessingReceipt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.order.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _GlassAppBar(title: widget.order.orderNumber),
      body: _DetailsBackground(
        child: SafeArea(
          child: orderId == null
              ? const ErrorState(
                  title: 'Order not found',
                  message: 'This order has no document ID and cannot be managed.',
                )
              : StreamBuilder<OrderModel?>(
                  stream: _orderStream,
                  initialData: widget.order,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const LoadingWidget(message: 'Loading order...');
                    }
                    if (snapshot.hasError) {
                      return const ErrorState(
                        message: 'Unable to load this order. Please check your connection.',
                      );
                    }

                    final order = snapshot.data;
                    if (order == null) {
                      return const ErrorState(
                        title: 'Order not found',
                        message: 'This order could not be found. It may have been removed.',
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _CustomerInfoCard(
                          customer: _customer,
                          userId: order.userId,
                          isLoading: _isLoadingCustomer,
                        ),
                        const SizedBox(height: 12),
                        _OrderInfoCard(order: order),
                        const SizedBox(height: 12),
                        _DeliveryInfoCard(order: order),
                        const SizedBox(height: 12),
                        _PriceBreakdownCard(order: order),
                        const SizedBox(height: 12),
                        _GlassCard(
                          child: ReportActionsRow(
                            isBusy: _isProcessingReceipt,
                            onExport: () => _handleReceiptAction(order: order, openPrintDialog: false),
                            onPrint: () => _handleReceiptAction(order: order, openPrintDialog: true),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _StatusUpdateCard(
                          order: order,
                          isUpdating: _isUpdatingStatus,
                          onSelectStatus: (status) => _updateStatus(order, status),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Soft gradient + blurred brand-blue blobs behind every card on this
/// screen — the same decorative language as the rest of the app's
/// frosted-glass screens.
class _DetailsBackground extends StatelessWidget {
  const _DetailsBackground({required this.child});

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
          top: -70,
          left: -60,
          child: _blob(_kBrandBlue.withValues(alpha: isDark ? 0.35 : 0.28), 220),
        ),
        Positioned(
          bottom: -100,
          right: -70,
          child: _blob(const Color(0xFF64B5F6).withValues(alpha: isDark ? 0.28 : 0.22), 260),
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

/// Frosted glass app bar — blurred backdrop, translucent fill, brand
/// blue title/back button.
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AppBar(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: _kBrandBlue)),
          backgroundColor: Colors.white.withValues(alpha: 0.55),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: _kBrandBlue),
          shape: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.6))),
        ),
      ),
    );
  }
}

/// Frosted glass card — replaces [AppCard] as this screen's shell.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.55),
            border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.6)),
            boxShadow: [
              BoxShadow(
                color: _kBrandBlue.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor, this.valueWeight});

  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight? valueWeight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: valueWeight ?? FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "View customer information" — name, email, phone, address for the
/// customer who placed this order. Falls back to a bare user ID while
/// [isLoading] is true or if no matching user document was found
/// (e.g. the account was later deleted).
class _CustomerInfoCard extends StatelessWidget {
  const _CustomerInfoCard({required this.customer, required this.userId, required this.isLoading});

  final UserModel? customer;
  final String userId;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _kBrandBlue.withValues(alpha: 0.15),
                backgroundImage:
                    customer?.profileImageUrl != null ? NetworkImage(customer!.profileImageUrl!) : null,
                child: customer?.profileImageUrl == null
                    ? Text(customer != null && customer!.name.isNotEmpty
                        ? customer!.name[0].toUpperCase()
                        : '?')
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    Text(
                      customer?.name.isNotEmpty == true ? customer!.name : 'Unknown customer',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _Row(label: 'Email', value: customer?.email.isNotEmpty == true ? customer!.email : '—'),
          _Row(label: 'Phone', value: customer?.phone.isNotEmpty == true ? customer!.phone : '—'),
          _Row(label: 'Address', value: customer?.address.isNotEmpty == true ? customer!.address : '—'),
          _Row(label: 'User ID', value: userId),
        ],
      ),
    );
  }
}

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final status = OrderStatusStyle.of(order.status);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order Details', style: Theme.of(context).textTheme.titleMedium),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(color: status.color, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Row(label: 'Order Number', value: order.orderNumber),
          _Row(label: 'Service', value: order.serviceName),
          // PART 3/5 fix — this screen was unconditionally showing
          // `order.weight` here (always 0 for an itemized Dry
          // Cleaning order, since that's priced per garment, not by
          // weight — see `OrderRepository.createOrder`), so every
          // Dry Cleaning order was showing an Admin "Weight: 0 pcs"
          // row. Branch on `order.isItemized` the same way
          // `order_details_screen.dart`'s customer-facing equivalent
          // already does: show the priced `"2 × Suit  ₱300"`
          // breakdown instead of a bogus weight/quantity row.
          if (order.isItemized) ...[
            const SizedBox(height: 4),
            Text(
              'Items',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            OrderItemsBreakdown(items: order.items),
          ] else
            _Row(
              label: order.serviceUnit.quantityFieldLabel,
              value: ServiceUnitFormat.formatQuantity(order.serviceUnit, order.weight),
            ),
          if (order.detergentName.isNotEmpty)
            _Row(label: 'Detergent', value: order.detergentName),
          if (!order.isItemized && order.items.isNotEmpty)
            _Row(
              label: 'Laundry Items',
              value: order.items.map((item) => item.itemName).join(', '),
            ),
          _Row(label: 'Placed On', value: formatOrderDate(order.createdAt)),
          _Row(label: 'Last Updated', value: formatOrderDate(order.updatedAt)),
        ],
      ),
    );
  }
}

class _DeliveryInfoCard extends StatelessWidget {
  const _DeliveryInfoCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final isPickup = order.isPickup;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isPickup ? Icons.delivery_dining_outlined : Icons.storefront_outlined,
                  size: 20, color: _kBrandBlue),
              const SizedBox(width: 8),
              Text(isPickup ? 'Pickup' : 'Drop-off', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (isPickup) ...[
            _Row(label: 'Address', value: order.address ?? '—'),
            _Row(label: 'Phone', value: order.pickupPhone ?? '—'),
            _Row(label: 'Landmark', value: order.pickupLandmark ?? '—'),
            _Row(label: 'Location', value: order.location ?? '—'),
          ] else
            const _Row(label: 'Method', value: 'Drop-off at shop'),
        ],
      ),
    );
  }
}

class _PriceBreakdownCard extends StatelessWidget {
  const _PriceBreakdownCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Price Summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Row(label: 'Subtotal', value: PriceCalculator.formatCurrency(order.subtotal)),
          _Row(label: 'Detergent Fee', value: PriceCalculator.formatCurrency(order.detergentFee)),
          if (order.isPickup)
            _Row(label: 'Pickup Fee', value: PriceCalculator.formatCurrency(order.pickupFee)),
          if (order.discount > 0)
            _Row(
              label: 'Discount',
              value: '-${PriceCalculator.formatCurrency(order.discount)}',
              valueColor: _kBrandBlue,
            ),
          const Divider(height: 20),
          _Row(
            label: 'Total',
            value: PriceCalculator.formatCurrency(order.total),
            valueColor: _kBrandBlue,
            valueWeight: FontWeight.w700,
          ),
        ],
      ),
    );
  }
}

/// "Update order status" — one button per status [order] may legally
/// move to next (via [OrderRepository.allowedNextStatuses]), so an
/// Admin can never tap their way into an illegal transition (e.g.
/// Pending -> Drying) in the first place. [OrderRepository
/// .updateOrderStatus] still re-validates server-side-of-the-call, so
/// a stale screen (two Admins acting on the same order at once) can't
/// force one through either.
class _StatusUpdateCard extends StatelessWidget {
  const _StatusUpdateCard({
    required this.order,
    required this.isUpdating,
    required this.onSelectStatus,
  });

  final OrderModel order;
  final bool isUpdating;
  final ValueChanged<OrderStatus> onSelectStatus;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final currentStyle = OrderStatusStyle.of(order.status);
    final allowed = OrderRepository.allowedNextStatuses(order.status)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Update Order Status', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Current status:',
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: currentStyle.color, size: 20),
              const SizedBox(width: 8),
              Text(
                currentStyle.label,
                style: textTheme.titleSmall?.copyWith(
                  color: currentStyle.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (allowed.isEmpty)
            Text(
              'This order has reached a final status and can no longer be updated.',
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: allowed.map((status) {
                final style = OrderStatusStyle.of(status);
                final isCancel = status == OrderStatus.cancelled;
                if (isCancel) {
                  return OutlinedButton.icon(
                    onPressed: isUpdating ? null : () => onSelectStatus(status),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel Order'),
                  );
                }
                return FilledButton.icon(
                  onPressed: isUpdating ? null : () => onSelectStatus(status),
                  style: FilledButton.styleFrom(backgroundColor: style.color),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text('Mark as ${style.label}'),
                );
              }).toList(),
            ),
          if (isUpdating) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}