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
import 'laundry_order_screen.dart';
import 'my_orders_screen.dart';
import 'notifications_screen.dart';
import 'offers_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _navIndex = 0;
  bool _checkedPostLoginRedirect = false;

  // PART 14.4 — shared instance so the unread-count badge below and
  // NotificationsScreen's own list are reading the exact same
  // real-time stream setup (same service, same query), not two
  // independent Firestore listeners.
  final NotificationService _notificationService = NotificationService();

  // Same post-login admin bounce logic carried over from before Part 06 —
  // untouched, still needed by RoleGuard / LoginScreen's fromLogin arg.
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

    final tabs = <Widget>[
      _HomeTab(
        userName: user?.name ?? '',
        onServiceTap: (service) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LaundryOrderScreen(initialService: service),
          ),
        ),
      ),
      const MyOrdersScreen(), // was: EmptyState placeholder (Part 13)
      const OffersScreen(), // was: EmptyState placeholder (Part 18A)
      const NotificationsScreen(), // was: EmptyState placeholder (Part 14.4)
      const ProfileScreen(), // was: EmptyState placeholder
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: IndexedStack(index: _navIndex, children: tabs),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (index) => setState(() => _navIndex = index),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'Orders'),
          const NavigationDestination(icon: Icon(Icons.local_offer_outlined), label: 'Offers'),
          NavigationDestination(
            icon: _UnreadNotificationsIcon(notificationService: _notificationService),
            label: 'Notifications',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// PART 14.4 — wraps the bottom nav's bell icon with a small unread
/// count badge, fed by [NotificationService.streamUserNotifications]
/// — the same real-time stream [NotificationsScreen] itself renders,
/// so the badge disappears the instant a notification is marked read
/// and appears the instant a new one is created, without ever
/// needing the Notifications tab to be the one currently open.
class _UnreadNotificationsIcon extends StatelessWidget {
  const _UnreadNotificationsIcon({required this.notificationService});

  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    final userId = AuthState.instance.firebaseUser?.uid;
    if (userId == null) return const Icon(Icons.notifications_outlined);

    return StreamBuilder<List<NotificationModel>>(
      stream: notificationService.streamUserNotifications(userId),
      builder: (context, snapshot) {
        final unreadCount = (snapshot.data ?? const <NotificationModel>[])
            .where((n) => !n.isRead)
            .length;
        if (unreadCount == 0) {
          return const Icon(Icons.notifications_outlined);
        }
        return Badge(
          label: Text(unreadCount > 9 ? '9+' : '$unreadCount'),
          child: const Icon(Icons.notifications_outlined),
        );
      },
    );
  }
}

/// The actual "Home" tab content — pulled out so build() above stays
/// readable and IndexedStack can keep all five tabs alive.
class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.userName, this.onServiceTap});

  final String userName;
  final ValueChanged<ServiceModel>? onServiceTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        WelcomeHeader(name: userName),
        const SizedBox(height: 20),
        const ActiveOrderCard(
          order: PlaceholderActiveOrder(
            orderNumber: 'ORD-20260910-0001',
            serviceName: 'Standard Wash',
            status: 'Washing',
            weightKg: 5,
          ),
        ),
        const SizedBox(height: 16),
        ServiceSelectionCard(onServiceTap: onServiceTap),
        const SizedBox(height: 16),
        Text('Current Offers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...kPlaceholderOffers.map(
          (offer) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OfferCard(offer: offer),
          ),
        ),
      ],
    );
  }
}