import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../widgets/active_order_card.dart';
import '../widgets/offer_card.dart';
import '../widgets/service_selection_card.dart';
import '../widgets/welcome_header.dart';
import '../../../data/repositories/service_repository.dart';
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

/// Tab index of the Profile screen inside [UserDashboard]'s `tabs` /
/// `tabTitles` lists — used by the app bar's profile button so tapping
/// it jumps straight to Profile regardless of which tab is active.
const int _kProfileTabIndex = 4;

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

    // Shown per-tab in the app bar, next to the logo/"HYDRO" brand
    // mark — every tab now carries the same brand lockup, not just
    // Home (see _BrandAppBarLabel).
    const tabTitles = <String>[
      'Our Services',
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
          userName: user?.name ?? '',
          onLogout: () => _handleLogout(context),
          // Tapping the profile avatar/name jumps straight to the
          // Profile tab, same pattern as onSeeAllOffers/onSeeAllOrders
          // above — no separate navigation route needed since Profile
          // already lives in `tabs`.
          onProfileTap: () => setState(() => _navIndex = _kProfileTabIndex),
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
///
/// Layout is a strict `Left icon → Title+Brand → [flexible space] →
/// Profile → Logout` row: the accent bar sits flush near the left edge
/// with only small consistent padding, the title+brand label is pinned
/// immediately beside it via `Alignment.centerLeft` (so it can never
/// drift into empty space), and the profile/logout gap on the right
/// uses the same spacing value on both sides.
///
/// Every tab (Home, Orders, Offers, Notifications, Profile) shows the
/// same lockup: `[tab title] | [logo] HYDRO`.
class _DashboardAppBar extends StatelessWidget {
  const _DashboardAppBar({
    required this.title,
    required this.userName,
    required this.onLogout,
    required this.onProfileTap,
  });

  final String title;
  final String userName;
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;

  // Single spacing constant reused for every gap in this bar (left
  // edge → icon, icon → title, and profile → logout) so the whole row
  // reads as one consistent rhythm instead of mismatched paddings.
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
                // Small, equal left/right padding — this is the only
                // space between the bar's edges and its content on
                // either side, so there's nowhere left for a stray gap
                // to hide.
                padding: const EdgeInsets.symmetric(horizontal: _gap + 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // "Left icon" — the accent bar, flush against the
                    // padding above with no extra margin of its own.
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: _gap),
                    // Title + brand mark sit immediately beside the
                    // icon — Alignment.centerLeft pins them to the
                    // start of this Expanded box regardless of their
                    // own intrinsic width, so they can never read as
                    // floating with empty space before them.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _BrandAppBarLabel(
                          key: ValueKey(title),
                          title: title,
                        ),
                      ),
                    ),
                    _ProfileButton(
                      userName: userName,
                      onTap: onProfileTap,
                    ),
                    const SizedBox(width: _gap),
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

/// App bar label shown on every tab: the current tab's title (animated
/// in on change via [_SlidingTitle]), a thin divider, then the compact
/// logo mark + "HYDRO" wordmark — so "Our Services", "Orders",
/// "Offers", "Notifications" and "Profile" all carry the same brand
/// lockup.
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
  // the full lockup — matches WelcomeHeader's icon-only crop so the
  // two brand marks line up visually.
  static const double _logoAspectRatio = 1.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: _SlidingTitle(
            text: title,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
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

/// Tappable profile entry point in the app bar: a circular avatar
/// (first initial of the signed-in user's name, or a person icon if no
/// name is available yet) plus the user's first name. Tapping anywhere
/// on it — avatar or name — jumps to the Profile tab via [onTap].
///
/// The name label shrinks/hides on very narrow widths (via Flexible +
/// ellipsis) so it never pushes the logout button off-screen; the
/// avatar itself is always shown.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.userName, required this.onTap});

  final String userName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trimmed = userName.trim();
    final firstName = trimmed.isNotEmpty ? trimmed.split(' ').first : '';
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 130),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.85),
                  ),
                  alignment: Alignment.center,
                  child: initial.isNotEmpty
                      ? Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                ),
                if (firstName.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              ],
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
///
/// Stateful (rather than the original Stateless version) because it
/// now owns the search bar: [_searchController]/[_query] drive a
/// live, client-side filter over the active service catalog, shown in
/// place of the usual Active Orders / Our Services / Offers content
/// whenever there's a non-empty query — same "single fetched list,
/// filtered locally" pattern [ExploreServicesScreen] and
/// [ManageOrdersScreen] already use elsewhere in this app.
class _HomeTab extends StatefulWidget {
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
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final ServiceRepository _repository = ServiceRepository();
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  late Future<List<ServiceModel>> _servicesFuture = _loadServices();

  Future<List<ServiceModel>> _loadServices() async {
    await _repository.seedDefaultServicesIfEmpty();
    return _repository.getActiveServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
  }

  /// Matches on both service name and description, same fields
  /// [ExploreServicesScreen]'s category-keyword matching and
  /// [_filterBySearch] in `manage_promos_screen.dart` key off of —
  /// so searching "delicate", for example, still finds Premium Wash
  /// even though the word isn't in its name.
  List<ServiceModel> _filterServices(List<ServiceModel> services, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return services;
    return services.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        WelcomeHeader(
          name: widget.userName,
          controller: _searchController,
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 10),
        if (isSearching)
          _SearchResults(
            servicesFuture: _servicesFuture,
            query: _query,
            filter: _filterServices,
            onServiceTap: widget.onServiceTap,
          )
        else ...[
          // PART 14+ — replaced the static `PlaceholderActiveOrder`
          // sample with the real, live-streaming ActiveOrdersSection:
          // it owns its own Firestore subscription
          // (OrderRepository.streamOrdersForUser) and renders
          // whichever orders are actually in progress for this user,
          // instead of always showing the same hardcoded "Order #4782
          // — Picked" card regardless of what's really happening.
          if (widget.userId != null)
            ActiveOrdersSection(
              userId: widget.userId!,
              onSeeAll: widget.onSeeAllOrders,
            ),
          const SizedBox(height: 16),
          ServiceSelectionCard(
            onServiceTap: widget.onServiceTap,
            onSeeAll: widget.onSeeAllServices,
          ),
          const SizedBox(height: 20),
          CurrentOffersSection(onSeeAll: widget.onSeeAllOffers),
        ],
      ],
    );
  }
}

/// Live search results shown under the search bar once the admin/user
/// has typed something — a plain vertical list rather than
/// [ServiceSelectionCard]'s horizontal carousel, since search results
/// read better top-to-bottom and can be any length.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.servicesFuture,
    required this.query,
    required this.filter,
    this.onServiceTap,
  });

  final Future<List<ServiceModel>> servicesFuture;
  final String query;
  final List<ServiceModel> Function(List<ServiceModel>, String) filter;
  final ValueChanged<ServiceModel>? onServiceTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceModel>>(
      future: servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              title: 'Unable to search right now',
              message: 'Please check your connection and try again.',
              icon: Icons.wifi_off_rounded,
            ),
          );
        }

        final results = filter(snapshot.data ?? const <ServiceModel>[], query);

        if (results.isEmpty) {
          return EmptyState(
            title: 'No services match "$query"',
            message: 'Try a different name, e.g. "wash" or "dry cleaning".',
            icon: Icons.search_off_rounded,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${results.length} result${results.length == 1 ? '' : 's'} for "$query"',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            ...results.map(
              (service) => _SearchResultTile(
                service: service,
                onTap: onServiceTap == null ? null : () => onServiceTap!(service),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.service, this.onTap});

  final ServiceModel service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final priceText =
        '\$${service.pricePerKg.toStringAsFixed(2)} ${ServiceUnitFormat.perUnitPhrase(service.unit)}';

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_laundry_service_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  service.description,
                  style: textTheme.bodySmall?.copyWith(color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  priceText,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xff9e1e77),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.black38),
        ],
      ),
    );
  }
}