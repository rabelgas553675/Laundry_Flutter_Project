import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/utils/service_unit.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../models/notification_model.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../widgets/dashboard_stat_card.dart';
import 'admin_order_details.dart';
import 'manage_orders_screen.dart';
import 'manage_promos_screen.dart';
import 'manage_services_screen.dart';
import 'reports_screen.dart';

/// Fixed content height of the glass app bar (excludes the status-bar
/// inset, which SafeArea adds on top of this) — identical value to
/// [UserDashboard]'s `_kAppBarContentHeight` so both dashboards' app
/// bars sit at the same height.
const double _kAppBarContentHeight = 64;

/// PART 15 — the real Admin Dashboard.
///
/// REDESIGN — this is now a persistent shell, the same shape as
/// [UserDashboard]: one glass top bar + one glass bottom nav that
/// never unmount, wrapping an `IndexedStack` of five tabs (Dashboard,
/// Manage Orders, Reports, Manage Services, Manage Promos). Switching
/// tabs no longer pushes a new route — it's an instant `setState`,
/// same as UserDashboard's Home/Orders/Offers/Notifications/Profile
/// tabs, so the top bar and bottom nav stay on screen the whole time
/// exactly like they do in the user-facing app.
///
/// THEME — the backdrop now matches [UserDashboard]'s blue-blob glass
/// background (`_DashboardBackground`) instead of the old grayscale
/// treatment, so both dashboards read as the same app/theme. All the
/// glass surfaces (app bar, bottom nav, stat cards, tiles) already
/// shared the same white-alpha/blur treatment — only the background
/// blobs' colors changed here.
///
/// Manage Users has no tab and no top-bar icon — it stays fully
/// functional via its existing `manageUsers` route, but this
/// dashboard no longer surfaces its own entry point to it.
///
/// ── LIVE NOTIFICATION BADGE (READ/UNREAD) ───────────────────────
/// The bell icon's badge now uses the exact same architecture as
/// [UserDashboard]'s `_UnreadNotificationsIcon`: it's a real,
/// persisted unread count sourced from
/// [NotificationService.streamUserNotifications], scoped to the
/// signed-in admin's own uid — not a derived/in-memory diff over the
/// orders list. Tapping the bell no longer "acknowledges" anything
/// locally; read state is only ever changed by
/// [NotificationService.markAsRead], the same as the customer-facing
/// screen, so it persists across screens, sessions, and devices.
///
/// [_AdminDashboardState] also owns a background subscription
/// ([_startAdminOrderWatch]) that is this dashboard's equivalent of
/// [NotificationsScreen]'s `_startOrderStatusSync`: it watches
/// [OrderRepository.streamAllOrders] and — because the Firestore
/// `notifications` create rule requires
/// `request.resource.data.userId == request.auth.uid` — self-writes a
/// notification addressed to the signed-in admin
/// ([NotificationService.notifyAdminOrderCreated] /
/// [NotificationService.notifyAdminOrderReady]) the moment it observes
/// a new order or an order becoming ready. This mirrors exactly how
/// the customer's own app is what creates the customer's own status
/// notifications — no Cloud Function or privileged write path exists
/// in this project, so "the recipient's own client creates its own
/// notifications" is the one architecture available, for both roles.
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
  int _navIndex = 0;

  static const _tabTitles = <String>[
    'Dashboard',
    'Manage Orders',
    'Reports',
    'Manage Services',
    'Manage Promos',
  ];

  // Background order→notification watcher — this dashboard's
  // equivalent of NotificationsScreen's `_startOrderStatusSync`. Lives
  // here (rather than inside AdminNotificationsScreen) so it keeps
  // running for the admin's whole session, the same way the
  // customer-facing watcher is kept alive by UserDashboard's
  // IndexedStack.
  final OrderRepository _watchOrderRepository = OrderRepository();
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<List<OrderModel>>? _orderWatchSubscription;
  String? _watchedAdminUserId;

  // This-session cache of "orderId|type" pairs already sent to
  // NotificationService — a cheap first-pass filter, exactly like
  // NotificationsScreen's `_handledStatusKeys`. NotificationService's
  // own Firestore-level duplicate check is still the real guard.
  final Set<String> _handledNotificationKeys = {};

  @override
  void initState() {
    super.initState();
    _startAdminOrderWatch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The signed-in admin's uid isn't guaranteed to be set yet at
    // initState time (AuthState may still be resolving), so re-check
    // here too — same pattern NotificationsScreen uses.
    _startAdminOrderWatch();
  }

  @override
  void dispose() {
    _orderWatchSubscription?.cancel();
    super.dispose();
  }

  /// Starts (or restarts, if the signed-in admin changed) the
  /// background subscription that turns "a new order was placed" /
  /// "an order became ready" into a real, persisted notification
  /// addressed to this admin account.
  void _startAdminOrderWatch() {
    final adminUserId = AuthState.instance.firebaseUser?.uid;
    if (adminUserId == null || adminUserId == _watchedAdminUserId) return;

    _watchedAdminUserId = adminUserId;
    _orderWatchSubscription?.cancel();
    _handledNotificationKeys.clear();
    _orderWatchSubscription = _watchOrderRepository.streamAllOrders().listen(
      (orders) {
        for (final order in orders) {
          _maybeNotifyAdmin(order, adminUserId);
        }
      },
      // A dropped connection here shouldn't crash the dashboard shell
      // — the visible Notifications screen's own StreamBuilder is
      // what tells the admin when something's wrong.
      onError: (Object _) {},
    );
  }

  /// Creates the admin-facing notification for [order]'s current
  /// status, if it's one of the two moments an admin needs a heads-up
  /// for (a brand-new order, or one that just became ready for
  /// pickup) and one doesn't already exist. Called for every order on
  /// every snapshot, but almost always a no-op thanks to
  /// [_handledNotificationKeys] and, underneath that,
  /// [NotificationService]'s own Firestore-level duplicate check.
  void _maybeNotifyAdmin(OrderModel order, String adminUserId) {
    final orderId = order.id;
    if (orderId == null) return;

    final NotificationType? type = switch (order.status) {
      OrderStatus.pending => NotificationType.orderCreated,
      OrderStatus.ready => NotificationType.ready,
      _ => null,
    };
    if (type == null) return;

    final key = '$orderId|${type.value}';
    if (_handledNotificationKeys.contains(key)) return;
    _handledNotificationKeys.add(key);

    // Fire-and-forget: a failure here (offline, permission hiccup)
    // shouldn't surface as an error on this dashboard — worst case,
    // the key stays out of the cache and the next snapshot retries it.
    final future = type == NotificationType.orderCreated
        ? _notificationService.notifyAdminOrderCreated(order: order, adminUserId: adminUserId)
        : _notificationService.notifyAdminOrderReady(order: order, adminUserId: adminUserId);
    future.catchError((Object _) {
      _handledNotificationKeys.remove(key);
      return null;
    });
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

  // Bell icon: just push the real Notifications screen — read state
  // is owned entirely by NotificationService/Firestore now, so there
  // is nothing left for this dashboard to "acknowledge" locally.
  void _handleNotificationsTap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AdminNotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 900 ? 32.0 : 16.0;

    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;
    const gapBelowAppBar = 14.0;

    final canPop = Navigator.of(context).canPop();

    // Built once, kept alive in the IndexedStack below — same "all
    // tabs instantiated up front" approach UserDashboard uses, so
    // each admin section keeps its own scroll position, search text,
    // and in-flight Firestore/Supabase listeners when you switch away
    // and back.
    final tabs = <Widget>[
      const _AdminHomeTab(),
      const ManageOrdersScreen(embedded: true),
      const ReportsScreen(embedded: true),
      const ManageServicesScreen(embedded: true),
      const ManagePromosScreen(embedded: true),
    ];

    final adminUserId = AuthState.instance.firebaseUser?.uid;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: adminUserId == null
            ? _AdminAppBar(
                title: _tabTitles[_navIndex],
                canPop: canPop,
                notificationCount: 0,
                onBack: () => Navigator.maybePop(context),
                onNotifications: () => _handleNotificationsTap(context),
                onLogout: () => _handleLogout(context),
              )
            : StreamBuilder<List<NotificationModel>>(
                // Same architecture as UserDashboard's
                // `_UnreadNotificationsIcon`: the badge count is a
                // live count of `!isRead` documents in the real
                // `notifications` collection, scoped to this admin's
                // own uid — not a locally-tracked diff.
                stream: _notificationService.streamUserNotifications(adminUserId),
                builder: (context, snapshot) {
                  final unreadCount = (snapshot.data ?? const <NotificationModel>[])
                      .where((n) => !n.isRead)
                      .length;
                  return _AdminAppBar(
                    title: _tabTitles[_navIndex],
                    canPop: canPop,
                    notificationCount: unreadCount,
                    onBack: () => Navigator.maybePop(context),
                    onNotifications: () => _handleNotificationsTap(context),
                    onLogout: () => _handleLogout(context),
                  );
                },
              ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AdminBackground()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    appBarTotalHeight + gapBelowAppBar,
                    horizontalPadding,
                    0,
                  ),
                  child: IndexedStack(index: _navIndex, children: tabs),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AdminBottomNav(
        selectedIndex: _navIndex,
        onDestinationSelected: (index) => setState(() => _navIndex = index),
      ),
    );
  }
}

/// Ambient backdrop for the Admin Dashboard — now the exact same
/// treatment as [UserDashboard]'s `_DashboardBackground`: a light blue
/// base wash with a dark-blue-to-light-blue gradient blob top-right, a
/// solid dark-blue blob left-mid, and a light-blue blob bottom-right,
/// all heavily blurred. This gives the glass app bar / bottom nav /
/// cards the same colorful backdrop to diffuse that the user-facing
/// dashboard has, instead of the previous flat grayscale look.
class _AdminBackground extends StatelessWidget {
  const _AdminBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Top-right dark-blue-to-light-blue blob
          Positioned(
            top: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff0D47A1), Color(0xffB3E5FC)],
                  ),
                ),
              ),
            ),
          ),
          // Left-side dark-blue blob, roughly mid-height
          Positioned(
            top: 260,
            left: -90,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff0D47A1).withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          // Bottom-right light-blue blob, sits behind the bottom nav
          Positioned(
            bottom: -60,
            right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff8EC5FC).withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted-glass app bar matching [UserDashboard]'s `_DashboardAppBar`
/// layout and blur treatment. The title now tracks whichever tab is
/// selected (Dashboard / Manage Orders / Reports / Manage Services /
/// Manage Promos), and — same as UserDashboard — is followed by a thin
/// divider and the HYDRO logo lockup via [_BrandAppBarLabel], so every
/// admin tab carries the same brand mark the user-facing tabs do.
///
/// Two action icons now: Notifications, then Logout. Tapping the bell
/// pushes [AdminNotificationsScreen]. The bell now also carries a
/// small red count badge (via [notificationCount]) showing how many
/// pending orders are UNREAD — see [AdminDashboard]'s class doc
/// comment for why. Manage Users has no icon here anymore (still
/// reachable via its own route, just not surfaced from this
/// dashboard).
class _AdminAppBar extends StatelessWidget {
  const _AdminAppBar({
    required this.title,
    required this.canPop,
    required this.notificationCount,
    required this.onBack,
    required this.onNotifications,
    required this.onLogout,
  });

  final String title;
  final bool canPop;
  final int notificationCount;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onLogout;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _kAppBarContentHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gap + 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (canPop)
                      _GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onPressed: onBack,
                      )
                    else
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _BrandAppBarLabel(
                          key: ValueKey(title),
                          title: title,
                        ),
                      ),
                    ),
                    _GlassIconButton(
                      icon: Icons.notifications_outlined,
                      tooltip: notificationCount > 0
                          ? '$notificationCount new order(s)'
                          : 'Notifications',
                      badgeCount: notificationCount,
                      onPressed: onNotifications,
                    ),
                    const SizedBox(width: _gap),
                    _GlassIconButton(
                      icon: Icons.logout_rounded,
                      tooltip: 'Log out',
                      onPressed: onLogout,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// App bar label shown on every admin tab: the current tab's title
/// (fades/slides in on change), a thin divider, then the compact logo
/// mark + "HYDRO" wordmark — identical lockup to [UserDashboard]'s
/// `_BrandAppBarLabel`, so the two dashboards carry the same brand
/// mark in the same spot.
class _BrandAppBarLabel extends StatelessWidget {
  const _BrandAppBarLabel({
    super.key,
    required this.title,
  }) : logoAsset = 'assets/images/logo.png',
       logoHeight = 26;

  final String title;
  final String logoAsset;
  final double logoHeight;

  // Aspect ratio of just the washer icon mark (roughly square), not
  // the full lockup — matches UserDashboard's own crop so the two
  // brand marks line up visually.
  static const double _logoAspectRatio = 1.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              title,
              key: ValueKey(title),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Thin divider so the tab title and the brand mark read as
        // two related but distinct pieces, not run-together text.
        Container(
          width: 1,
          height: 16,
          color: Colors.black.withValues(alpha: 0.15),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: logoHeight * _logoAspectRatio,
          height: logoHeight,
          child: Image.asset(
            logoAsset,
            alignment: Alignment.centerLeft,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  Icons.local_laundry_service_outlined,
                  size: 20,
                  color: Colors.black45,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'HYDRO',
          style: TextStyle(
            fontSize: logoHeight * 0.54,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            height: 1.0,
            color: const Color(0xff2E75B6),
          ),
        ),
      ],
    );
  }
}

/// Small circular glass button — same treatment as UserDashboard's
/// logout button, generalized to take any icon/tooltip. Optionally
/// carries a small red count badge (top-right corner) when
/// [badgeCount] is greater than zero — used for the bell icon's
/// unread-order count. Counts of 100+ display as "99+" so the badge
/// never grows wide enough to break the circular button's layout.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badgeCount,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final showBadge = (badgeCount ?? 0) > 0;
    final badgeLabel = (badgeCount ?? 0) > 99 ? '99+' : '${badgeCount ?? 0}';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: tooltip,
                icon: Icon(icon, color: Colors.black87, size: 19),
                onPressed: onPressed,
              ),
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            top: -2,
            right: -2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xffFF4D67),
                  shape: badgeLabel.length > 2 ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: badgeLabel.length > 2 ? BorderRadius.circular(9) : null,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Glass bottom navigation bar — 5 items (Dashboard, Orders, Reports,
/// Services, Promos), same pill-shaped, blurred, capsule-select
/// styling as UserDashboard's `_DashboardBottomNav`. Since every
/// destination is an embedded tab rather than a pushed screen,
/// [selectedIndex] always reflects exactly which section is on
/// screen.
class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _items = <(IconData, String)>[
    (Icons.space_dashboard_rounded, 'Dashboard'),
    (Icons.receipt_long_rounded, 'Orders'),
    (Icons.bar_chart_rounded, 'Reports'),
    (Icons.local_laundry_service_rounded, 'Services'),
    (Icons.local_offer_rounded, 'Promos'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: List.generate(_items.length, (index) {
                final (icon, label) = _items[index];
                final isSelected = index == selectedIndex;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onDestinationSelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.85)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                        border: isSelected
                            ? Border.all(color: Colors.white.withValues(alpha: 0.6))
                            : null,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isSelected ? 14 : 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: isSelected ? Colors.black : Colors.black87,
                              ),
                              ClipRect(
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  child: isSelected
                                      ? Padding(
                                          padding: const EdgeInsets.only(left: 8),
                                          child: Text(
                                            label,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Dashboard" tab's content: owns the two live Firestore streams
/// (orders, users) that back the stat cards / status summary / recent
/// orders list — pulled out of [_AdminDashboardState] itself now that
/// the dashboard is just one of five tabs rather than the whole
/// screen. The users stream is still needed for the "Total Users"
/// stat card even though the standalone "Recent Users" list has been
/// removed.
class _AdminHomeTab extends StatefulWidget {
  const _AdminHomeTab();

  @override
  State<_AdminHomeTab> createState() => _AdminHomeTabState();
}

class _AdminHomeTabState extends State<_AdminHomeTab> {
  final OrderRepository _orderRepository = OrderRepository();
  final UserRepository _userRepository = UserRepository();

  // Cached as state fields (not created inline in `build()`) so
  // StreamBuilder keeps one live subscription per stream instead of
  // resubscribing — and flickering back to loading — on every emit.
  late Stream<List<OrderModel>> _ordersStream = _orderRepository.streamAllOrders();
  late Stream<List<UserModel>> _usersStream = _userRepository.streamAllUsers();

  void _retryOrders() {
    setState(() => _ordersStream = _orderRepository.streamAllOrders());
  }

  void _retryUsers() {
    setState(() => _usersStream = _userRepository.streamAllUsers());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: _ordersStream,
      builder: (context, orderSnapshot) {
        if (orderSnapshot.connectionState == ConnectionState.waiting) {
          return const _GlassStatePanel(
            child: LoadingWidget(message: 'Loading orders...'),
          );
        }
        if (orderSnapshot.hasError) {
          return _GlassStatePanel(
            child: ErrorState(
              message: 'Unable to load orders. Please try again.',
              onRetry: _retryOrders,
            ),
          );
        }

        final orders = orderSnapshot.data ?? const <OrderModel>[];

        return StreamBuilder<List<UserModel>>(
          stream: _usersStream,
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _GlassStatePanel(
                child: LoadingWidget(message: 'Loading users...'),
              );
            }
            if (userSnapshot.hasError) {
              return _GlassStatePanel(
                child: ErrorState(
                  message: 'Unable to load users. Please try again.',
                  onRetry: _retryUsers,
                ),
              );
            }

            final users = userSnapshot.data ?? const <UserModel>[];
            return _DashboardContent(orders: orders, users: users);
          },
        );
      },
    );
  }
}

/// Wraps a loading/error/empty state widget (which are plain, shared
/// across the whole app) in a glass panel so it still reads as
/// belonging to the Admin section's frosted-glass background instead
/// of floating as a bare opaque block. The underlying state widgets
/// ([LoadingWidget]/[ErrorState]/[EmptyState]) are left completely
/// untouched — they're shared with the rest of the app — this only
/// adds the glass frame around them, scoped to this file.
class _GlassStatePanel extends StatelessWidget {
  const _GlassStatePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        borderRadius: 24,
        child: child,
      ),
    );
  }
}

/// Stat cards row + search + Order Status Summary + Notifications
/// (renamed from "Recent Orders").
///
/// The "Recent Users" list has been removed entirely — [users] is
/// still passed in only so the stat cards row can show the "Total
/// Users" count.
///
/// Stateful: it owns the search query that live-filters the
/// Notifications (order) list below, the same "type and the list
/// narrows" pattern the user-side Home tab already uses for services.
class _DashboardContent extends StatefulWidget {
  const _DashboardContent({
    required this.orders,
    required this.users,
  });

  final List<OrderModel> orders;
  final List<UserModel> users;

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  /// Matches an order by its order number or the service it's for —
  /// the two things an admin would actually type in to find one.
  List<OrderModel> _filterOrders(List<OrderModel> orders, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return orders;
    return orders
        .where((o) =>
            o.orderNumber.toLowerCase().contains(q) ||
            o.serviceName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    final users = widget.users;

    final totalUsers = users.length;
    final totalOrders = orders.length;
    final pendingOrders =
        orders.where((o) => o.status == OrderStatus.pending).length;

    final totalRevenue = orders
    .where((o) => o.status == OrderStatus.completed)
    .fold<double>(0, (runningTotal, o) => runningTotal + o.total);

    // Stat cards and the Order Status Summary always reflect the full,
    // unfiltered data — only the Notifications list below narrows down
    // as the admin types, same as search elsewhere in this app never       
    // hides aggregate totals, only the browsable list under them.
    final isSearching = _query.trim().isNotEmpty;
    final recentOrders = _filterOrders(orders, _query).take(5).toList();

    final statusCounts = <OrderStatus, int>{
      for (final status in OrderStatus.values)
        status: orders.where((o) => o.status == status).length,
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _StatCardsRow(
          totalUsers: totalUsers,
          totalOrders: totalOrders,
          pendingOrders: pendingOrders,
          totalRevenue: totalRevenue,
        ),
        const SizedBox(height: 20),
        _AdminSearchBar(
          controller: _searchController,
          onChanged: _onSearchChanged,
          onClear: _clearSearch,
          showClear: isSearching,
        ),
        const SizedBox(height: 24),
        _SectionHeader(title: 'Order Status Summary'),
        const SizedBox(height: 8),
        _OrderStatusSummaryCard(statusCounts: statusCounts),
        const SizedBox(height: 24),
        _SectionHeader(title: 'Notifications'),
        const SizedBox(height: 8),
        if (recentOrders.isEmpty)
          GlassContainer(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EmptyState(
              title: isSearching ? 'No matching orders' : 'No orders yet',
              message: isSearching
                  ? 'Try a different order number or service name.'
                  : 'Placed orders will show up here.',
              icon: Icons.receipt_long_outlined,
            ),
          )
        else
          ...recentOrders.map((order) => _RecentOrderTile(order: order)),
      ],
    );
  }
}

/// A static, non-scrolling row of the four stat cards — all visible
/// at once, no swipe/arrows needed. Each card stretches to fully fill
/// its quarter of the row (only a slim gap between them) rather than
/// being uniformly scaled down and left floating with empty space
/// around it, so the cards read as big, edge-to-edge tiles.
class _StatCardsRow extends StatelessWidget {
  const _StatCardsRow({
    required this.totalUsers,
    required this.totalOrders,
    required this.pendingOrders,
    required this.totalRevenue,
  });

  final int totalUsers;
  final int totalOrders;
  final int pendingOrders;
  final double totalRevenue;

  // Taller row so each stretched card has enough room to lay out its
  // icon/value/label without wrapping or overflowing; only a slim gap
  // between cards rather than the previous large empty margins.
  static const double _rowHeight = 172;
  static const double _cardSpacing = 6;

  // Relative width each card gets in the row. Total Revenue is given
  // extra flex — its value is almost always the longest string of the
  // four ("₱5,680.00" vs a bare number) — so it has enough room for
  // the full amount instead of getting ellipsized.
  static const int _defaultFlex = 4;
  static const int _revenueFlex = 6;

  /// Drops a trailing ".00" from a formatted currency string (e.g.
  /// "₱5,680.00" → "₱5,680") when the amount is a whole number, so
  /// the value is a few characters shorter and easier to fit without
  /// losing any actual precision — cents still show normally whenever
  /// the amount actually has them (e.g. "₱5,680.50").
  static String _compactCurrency(double amount) {
    final formatted = PriceCalculator.formatCurrency(amount);
    if (amount == amount.truncateToDouble() && formatted.endsWith('.00')) {
      return formatted.substring(0, formatted.length - 3);
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final cards = <(Widget, int)>[
      (
        DashboardStatCard(
          label: 'Total Users',
          value: '$totalUsers',
          icon: Icons.people_outline,
        ),
        _defaultFlex,
      ),
      (
        DashboardStatCard(
          label: 'Total Orders',
          value: '$totalOrders',
          icon: Icons.receipt_long_outlined,
        ),
        _defaultFlex,
      ),
      (
        DashboardStatCard(
          label: 'Pending Orders',
          value: '$pendingOrders',
          icon: Icons.pending_actions_outlined,
          iconColor: Colors.orange,
        ),
        _defaultFlex,
      ),
      (
        DashboardStatCard(
          label: 'Total Revenue',
          value: _compactCurrency(totalRevenue),
          icon: Icons.payments_outlined,
          iconColor: Colors.green,
        ),
        _revenueFlex,
      ),
    ];

    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i != 0) const SizedBox(width: _cardSpacing),
            Expanded(flex: cards[i].$2, child: cards[i].$1),
          ],
        ],
      ),
    );
  }
}

/// The "Order Status Summary" card redesigned to match the reference
/// layout: a glass panel holding a wrapping grid of tiles, each with
/// a status icon, a small colored dot, the status label, and the
/// count on the line beneath — instead of the old inline row of
/// count + [StatusBadge] pills.
class _OrderStatusSummaryCard extends StatelessWidget {
  const _OrderStatusSummaryCard({required this.statusCounts});

  final Map<OrderStatus, int> statusCounts;

  // Icon + accent color per status, matching the reference design's
  // per-status glyphs (timer for pending, a package for received, a
  // washer for washing, and so on).
  static const Map<OrderStatus, (IconData, Color)> _visuals = {
    OrderStatus.pending: (Icons.timer_outlined, Color(0xffF5A623)),
    OrderStatus.received: (Icons.inventory_2_outlined, Color(0xff8B5CF6)),
    OrderStatus.washing: (Icons.local_laundry_service_outlined, Color(0xff2196F3)),
    OrderStatus.drying: (Icons.air_rounded, Color(0xff2DBE9A)),
    OrderStatus.ready: (Icons.checkroom_outlined, Color(0xff8B5CF6)),
    OrderStatus.completed: (Icons.check_box_outlined, Color(0xff34C759)),
    OrderStatus.cancelled: (Icons.close_rounded, Color(0xffFF4D67)),
  };

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Wrap(
        spacing: 28,
        runSpacing: 20,
        children: statusCounts.entries.map((entry) {
          final visual = _visuals[entry.key];
          return _StatusSummaryTile(
            icon: visual?.$1 ?? Icons.info_outline,
            color: visual?.$2 ?? Colors.grey,
            label: entry.key.value,
            count: entry.value,
            // Only "pending" gets its label tinted in the reference
            // design — every other label stays the default dark text
            // with just its dot colored.
            highlightLabel: entry.key == OrderStatus.pending,
          );
        }).toList(),
      ),
    );
  }
}

/// One tile in [_OrderStatusSummaryCard]: `icon  •label` on the first
/// line, the count directly beneath. A zero count renders faded so
/// the eye is drawn to statuses that actually have orders in them.
class _StatusSummaryTile extends StatelessWidget {
  const _StatusSummaryTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.highlightLabel,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final bool highlightLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: highlightLabel ? color : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: count > 0 ? Colors.black87 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A fully functional search field, glass-styled to match the rest of
/// this dashboard, sitting above "Order Status Summary". Typing here
/// live-filters the Notifications (order) list further down — see
/// [_DashboardContentState._filterOrders] — by order number or
/// service name.
class _AdminSearchBar extends StatelessWidget {
  const _AdminSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.showClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool showClear;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search orders...',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.45)),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.black54, size: 20),
              suffixIcon: showClear
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.black54, size: 18),
                      tooltip: 'Clear search',
                      onPressed: onClear,
                    )
                  : null,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small section label used above each block in the dashboard tab
/// ("Order Status Summary", "Notifications") — plain text (not its
/// own glass panel) so it reads as a heading sitting on the glass
/// background, matching how UserDashboard labels its own sections.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        borderRadius: 18,
        blur: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.serviceName} · '
                    '${order.isItemized ? '${order.items.length} item type(s)' : ServiceUnitFormat.formatQuantity(order.serviceUnit, order.weight)}',
                    style: textTheme.bodyMedium?.copyWith(color: Colors.black54),
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
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                StatusBadge(status: order.status.value),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatShortDate(DateTime? date) {
  if (date == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// -----------------------------------------------------------------
/// Notifications screen, pushed when the bell icon is tapped.
/// -----------------------------------------------------------------
///
/// Same notification architecture as the customer-facing
/// [NotificationsScreen] — [NotificationModel] +
/// [NotificationService], not a screen-local re-derivation of the
/// orders list:
///
/// * **Display** — a real-time list of this admin account's own
///   notifications via [NotificationService.streamUserNotifications],
///   scoped to the signed-in admin's uid exactly the way the
///   customer screen scopes to the customer's uid. The *creation* of
///   those notifications (a new order arriving, an order becoming
///   ready) happens in the background in [_AdminDashboardState]
///   (`_startAdminOrderWatch`) — the same "watcher lives above this
///   screen so it survives the screen being popped" split the
///   customer app uses (there it's [NotificationsScreen] itself that
///   owns the watcher, because nothing above it needs to keep
///   running independently; here [AdminDashboard] already needs to
///   keep the watcher alive for the bell badge, so this screen simply
///   doesn't duplicate it).
/// * **Read state** — persisted in Firestore via
///   [NotificationService.markAsRead], never a local in-memory set.
///   Tapping a notification here behaves exactly like tapping one on
///   the customer screen.
/// * **Navigation** — tapping a notification loads the linked order
///   ([OrderRepository.getOrderByDocId]) and opens the admin's own
///   order-detail screen for it, the admin equivalent of the customer
///   screen opening [OrderDetailsScreen].
///
/// This screen owns no notification-service logic of its own — it
/// only subscribes, renders, and delegates back to
/// [NotificationService]/[OrderRepository].
class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({
    super.key,
    this.notificationService,
    this.orderRepository,
  });

  /// Injectable for widget tests; defaults to a real
  /// [NotificationService]/[OrderRepository] backed by live Firestore
  /// — same pattern [NotificationsScreen] uses.
  final NotificationService? notificationService;
  final OrderRepository? orderRepository;

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  late final NotificationService _notificationService =
      widget.notificationService ?? NotificationService();
  late final OrderRepository _orderRepository = widget.orderRepository ?? OrderRepository();

  /// Subscribed once — not created inline in `build()` — so a
  /// `StreamBuilder` rebuild doesn't hand it a brand-new `Stream`
  /// object and force a needless resubscribe. Same reasoning as
  /// [NotificationsScreen]'s `_notificationsStream`.
  Stream<List<NotificationModel>>? _notificationsStream;
  String? _streamedAdminUserId;

  bool _isMarkingRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final adminUserId = AuthState.instance.firebaseUser?.uid;
    if (adminUserId != null && adminUserId != _streamedAdminUserId) {
      _streamedAdminUserId = adminUserId;
      _notificationsStream = _notificationService.streamUserNotifications(adminUserId);
    }
  }

  Future<void> _openNotification(NotificationModel notification) async {
    if (_isMarkingRead) return;

    if (!notification.isRead && notification.notificationId != null) {
      setState(() => _isMarkingRead = true);
      try {
        await _notificationService.markAsRead(notification.notificationId!);
      } catch (_) {
        // Non-fatal — the notification just stays marked unread; the
        // admin can still open the order below.
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
      MaterialPageRoute(builder: (_) => AdminOrderDetailsScreen(order: order!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;

    final adminUserId = AuthState.instance.firebaseUser?.uid;
    final stream = _notificationsStream;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: _NotificationsAppBar(onBack: () => Navigator.maybePop(context)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AdminBackground()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, appBarTotalHeight + 14, 16, 16),
                  child: adminUserId == null || stream == null
                      ? const _GlassStatePanel(
                          child: ErrorState(
                            message: 'Your session has expired. Please log in again.',
                          ),
                        )
                      : StreamBuilder<List<NotificationModel>>(
                          stream: stream,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const _GlassStatePanel(
                                child: LoadingWidget(message: 'Loading notifications...'),
                              );
                            }
                            if (snapshot.hasError) {
                              return _GlassStatePanel(
                                child: ErrorState(
                                  message: 'Unable to load notifications. Please try again.',
                                  onRetry: () => setState(() {
                                    _notificationsStream =
                                        _notificationService.streamUserNotifications(adminUserId);
                                  }),
                                ),
                              );
                            }

                            final notifications = snapshot.data ?? const <NotificationModel>[];

                            if (notifications.isEmpty) {
                              return const _GlassStatePanel(
                                child: EmptyState(
                                  title: 'No notifications',
                                  message: "You're all caught up.",
                                  icon: Icons.notifications_none_rounded,
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: notifications.length,
                              itemBuilder: (context, index) {
                                final notification = notifications[index];
                                return _NotificationTile(
                                  notification: notification,
                                  onTap: () => _openNotification(notification),
                                );
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal glass app bar for the Notifications screen — just a back
/// button and a title, same blur/border treatment as the main
/// [_AdminAppBar] so the screen still feels like part of this app.
class _NotificationsAppBar extends StatelessWidget {
  const _NotificationsAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _kAppBarContentHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon + tint for each [NotificationType], for the admin's glass
/// tile below. Mirrors the customer-facing [NotificationsScreen]'s
/// `_NotificationTile._iconFor`, with an admin-appropriate icon set
/// (order-created and ready are the two an admin watcher actually
/// fires, but every type is covered so the tile never has to guess).
IconData _adminNotificationIcon(NotificationType type) {
  switch (type) {
    case NotificationType.orderCreated:
      return Icons.timer_outlined;
    case NotificationType.received:
      return Icons.inventory_2_outlined;
    case NotificationType.washing:
      return Icons.local_laundry_service_outlined;
    case NotificationType.drying:
      return Icons.dry_outlined;
    case NotificationType.ready:
      return Icons.checkroom_outlined;
    case NotificationType.completed:
      return Icons.task_alt_outlined;
  }
}

Color _adminNotificationColor(NotificationType type) {
  switch (type) {
    case NotificationType.orderCreated:
      return const Color(0xffF5A623);
    case NotificationType.ready:
      return const Color(0xff8B5CF6);
    case NotificationType.received:
    case NotificationType.washing:
    case NotificationType.drying:
    case NotificationType.completed:
      return const Color(0xff2E7D32);
  }
}

/// Tappable notification row, driven entirely by a [NotificationModel]
/// — same data source as the customer-facing screen's tile, just
/// styled to match this app's glass-card look. Tapping it is handled
/// by the parent screen (it's what calls
/// [NotificationService.markAsRead] and navigates), this widget only
/// renders whichever `isRead` state the model already carries: a
/// translucent dark scrim fades in over the glass card and the text
/// dims, so a read notification visibly sits "behind glass" compared
/// to an unread one.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final NotificationModel notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isRead = notification.isRead;
    final iconColor = _adminNotificationColor(notification.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              GlassContainer(
                borderRadius: 18,
                blur: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: isRead ? 0.08 : 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _adminNotificationIcon(notification.type),
                        size: 20,
                        color: isRead ? iconColor.withValues(alpha: 0.55) : iconColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isRead ? Colors.black54 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${notification.message}\n${notification.orderNumber}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: isRead ? Colors.black38 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatShortDate(notification.createdAt),
                      style: textTheme.bodySmall?.copyWith(
                        color: isRead ? Colors.black26 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              // Dark scrim — fades in once `isRead` is true (persisted
              // via NotificationService.markAsRead, not a local flag),
              // sits on top of the glass card without changing its own
              // layout, so this is the one thing that visually says
              // "already read".
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isRead ? 1 : 0,
                child: IgnorePointer(
                  child: Container(color: Colors.black.withValues(alpha: 0.10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}