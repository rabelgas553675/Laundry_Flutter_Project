import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../widgets/active_order_card.dart';
import '../widgets/offer_card.dart';
import '../widgets/service_selection_card.dart';
import '../widgets/welcome_header.dart';
import '../../../data/services/notification_service.dart';
import '../../../models/notification_model.dart';
import '../../../models/service_model.dart';
import '../../../models/user_model.dart';
import 'profile_screen.dart';
import 'explore_services_screen.dart';
import 'laundry_order_screen.dart';
import 'my_orders_screen.dart';
import 'notifications_screen.dart';
import 'offers_screen.dart';

/// Fixed content height of the app bar (excludes the status-bar inset,
/// which SafeArea adds on top of this).
const double _kAppBarContentHeight = 64;

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _navIndex = 0;
  bool _checkedPostLoginRedirect = false;

  final NotificationService _notificationService = NotificationService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedPostLoginRedirect) return;
    _checkedPostLoginRedirect = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    final fromLogin = args is Map && args['fromLogin'] == true;
    if (fromLogin && AuthState.instance.role == UserRole.admin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
      });
    }
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
    final user = AuthState.instance.userModel;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 900 ? 32.0 : 16.0;

    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;
    const gapBelowAppBar = 14.0;

    final tabs = <Widget>[
      _HomeTab(
        userName: user?.name ?? '',
        // ActiveOrdersSection (PART 14+) owns its own Firestore
        // subscription and needs the signed-in user's uid to know
        // whose orders to stream — same uid
        // _UnreadNotificationsIcon below already reads off
        // AuthState for the exact same reason.
        userId: AuthState.instance.firebaseUser?.uid,
        onServiceTap: (service) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LaundryOrderScreen(initialService: service),
          ),
        ),
        // "See all" next to "Our Services" — same pattern as
        // onServiceTap above, pushes the full Explore Services list.
        onSeeAllServices: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExploreServicesScreen()),
        ),
        // Offers is tab index 2 in `tabs` / `tabTitles` below.
        onSeeAllOffers: () => setState(() => _navIndex = 2),
        // "See all" inside the Active Orders card should jump to the
        // Orders tab (index 1), same pattern as onSeeAllOffers above.
        onSeeAllOrders: () => setState(() => _navIndex = 1),
      ),
      const MyOrdersScreen(embedded: true),
      const OffersScreen(embedded: true),
      const NotificationsScreen(embedded: true),
      const ProfileScreen(embedded: true),
    ];

    const tabTitles = <String>[
      'User Dashboard',
      'Orders',
      'Offers',
      'Notifications',
      'Profile',
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: _DashboardAppBar(
          title: tabTitles[_navIndex],
          onLogout: () => _handleLogout(context),
        ),
      ),
      body: Stack(
        children: [
          // Soft blurred color blobs behind everything, so the glass
          // app bar / bottom nav / service cards have something
          // colorful to diffuse instead of a flat surface fill.
          const Positioned.fill(child: _DashboardBackground()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
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
      bottomNavigationBar: _DashboardBottomNav(
        selectedIndex: _navIndex,
        onDestinationSelected: (index) => setState(() => _navIndex = index),
        notificationService: _notificationService,
      ),
    );
  }
}

/// The ambient backdrop the whole dashboard sits on: a light base wash
/// with a few large, heavily-blurred color blobs pinned near the
/// corners. This is what the frosted-glass app bar, bottom nav, and
/// service cards actually blur — without it behind them, BackdropFilter
/// has nothing colorful to diffuse and the "glass" just looks grey.
class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground();

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

/// Frosted-glass app bar: a blurred, semi-transparent dark bar (content
/// scrolling behind it shows through, softened) instead of a solid
/// near-opaque fill — matching the bottom nav's glass treatment.
class _DashboardAppBar extends StatelessWidget {
  const _DashboardAppBar({required this.title, required this.onLogout});

  final String title;
  final VoidCallback onLogout;

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
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: _SlidingTitle(
                        text: title,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _GlassIconButton(onPressed: onLogout),
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

class _SlidingTitle extends StatefulWidget {
  const _SlidingTitle({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_SlidingTitle> createState() => _SlidingTitleState();
}

class _SlidingTitleState extends State<_SlidingTitle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _SlidingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.text.runes.map(String.fromCharCode).toList();
    final total = letters.length.clamp(1, 1000);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(letters.length, (i) {
        final start = (i / total) * 0.6;
        final end = (start + 0.4).clamp(0.0, 1.0);
        final curved = CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        );

        return AnimatedBuilder(
          animation: curved,
          builder: (context, child) {
            final value = curved.value;
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 12),
                child: child,
              ),
            );
          },
          child: Text(letters[i], style: widget.style),
        );
      }),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded, color: Colors.black87, size: 19),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _DashboardBottomNav extends StatelessWidget {
  const _DashboardBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.notificationService,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final NotificationService notificationService;

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'Home'),
    (Icons.list_alt_rounded, 'Orders'),
    (Icons.local_offer_rounded, 'Offers'),
    (Icons.notifications_rounded, 'Notifications'),
    (Icons.person_rounded, 'Profile'),
  ];

  static const int _notificationsIndex = 3;

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
                  flex: 1,
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
                              index == _notificationsIndex
                                  ? _UnreadNotificationsIcon(
                                      notificationService: notificationService,
                                      color: isSelected ? Colors.black : Colors.black87,
                                      filled: true,
                                    )
                                  : Icon(
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

class _UnreadNotificationsIcon extends StatelessWidget {
  const _UnreadNotificationsIcon({
    required this.notificationService,
    required this.color,
    required this.filled,
  });

  final NotificationService notificationService;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final userId = AuthState.instance.firebaseUser?.uid;
    final baseIcon = Icon(Icons.notifications_rounded, size: 20, color: color);
    if (userId == null) return baseIcon;

    return StreamBuilder<List<NotificationModel>>(
      stream: notificationService.streamUserNotifications(userId),
      builder: (context, snapshot) {
        final unreadCount = (snapshot.data ?? const <NotificationModel>[])
            .where((n) => !n.isRead)
            .length;
        if (unreadCount == 0) return baseIcon;
        return Badge(
          label: Text(unreadCount > 9 ? '9+' : '$unreadCount'),
          backgroundColor: Colors.redAccent,
          child: baseIcon,
        );
      },
    );
  }
}

/// The actual "Home" tab content — pulled out so build() above stays
/// readable and IndexedStack can keep all five tabs alive.
class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.userName,
    required this.userId,
    this.onServiceTap,
    this.onSeeAllServices,
    this.onSeeAllOffers,
    this.onSeeAllOrders,
  });

  final String userName;

  /// Signed-in user's Firestore/Firebase Auth uid — needed by
  /// [ActiveOrdersSection] to know whose orders to stream. Null only
  /// if somehow reached while signed out (shouldn't happen behind an
  /// authenticated route, but handled defensively below rather than
  /// assumed away).
  final String? userId;

  final ValueChanged<ServiceModel>? onServiceTap;
  final VoidCallback? onSeeAllServices;
  final VoidCallback? onSeeAllOffers;
  final VoidCallback? onSeeAllOrders;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        WelcomeHeader(name: userName),
        const SizedBox(height: 20),
        // PART 14+ — replaced the static `PlaceholderActiveOrder`
        // sample with the real, live-streaming ActiveOrdersSection:
        // it owns its own Firestore subscription
        // (OrderRepository.streamOrdersForUser) and renders whichever
        // orders are actually in progress for this user, instead of
        // always showing the same hardcoded "Order #4782 — Picked"
        // card regardless of what's really happening.
        if (userId != null)
          ActiveOrdersSection(
            userId: userId!,
            onSeeAll: onSeeAllOrders,
          ),
        const SizedBox(height: 16),
        ServiceSelectionCard(
          onServiceTap: onServiceTap,
          onSeeAll: onSeeAllServices,
        ),
        const SizedBox(height: 20),
        CurrentOffersSection(onSeeAll: onSeeAllOffers),
      ],
    );
  }
}