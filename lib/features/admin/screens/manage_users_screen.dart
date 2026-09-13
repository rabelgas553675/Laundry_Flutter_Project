import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_state.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../models/user_model.dart';
import '../widgets/admin_user_card.dart';
import '../widgets/user_form_dialog.dart';

/// PART 17 — Admin User Management.
///
/// Reads the same live [UserRepository.streamAllUsers] stream PART
/// 15's Admin Dashboard already uses, filtered client-side by the
/// search box — the same "one stream, many views" shape [ManageOrdersScreen]
/// uses for its own search+tabs (PART 16).
///
/// Admin can: view users, search users, add users, edit users, and
/// activate/deactivate accounts — matching this part's spec exactly.
/// An Admin can never deactivate or demote their own account from
/// here (see [AdminUserCard.isSelf] / [UserFormDialog._isEditingSelf])
/// so they can't accidentally lock themselves out of Admin tools.
///
/// Reachable only through the `manageUsers` route, which [RoleGuard]
/// (PART 05) restricts to [UserRole.admin] — this screen does no role
/// checking of its own.
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key, this.userRepository, this.authRepository});

  /// Injectable for widget tests; defaults to real repositories
  /// backed by live Firestore/Firebase Auth.
  final UserRepository? userRepository;
  final AuthRepository? authRepository;

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  late final UserRepository _userRepository = widget.userRepository ?? UserRepository();
  late final AuthRepository _authRepository = widget.authRepository ?? AuthRepository();

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Bumped by the ErrorState "Retry" button to force the
  /// StreamBuilder to resubscribe — same pattern as
  /// [ManageOrdersScreen]'s `_retryToken`.
  int _retryToken = 0;

  /// uid of the user whose activate/deactivate toggle is mid-flight.
  String? _togglingUserId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<UserModel> _filterBySearch(List<UserModel> users, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return users;
    return users.where((u) {
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.phone.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openAddDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => UserFormDialog(
        userRepository: _userRepository,
        authRepository: _authRepository,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User added.')));
    }
  }

  Future<void> _openEditDialog(UserModel user) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => UserFormDialog(
        existing: user,
        userRepository: _userRepository,
        authRepository: _authRepository,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated.')));
    }
  }

  Future<void> _toggleActive(UserModel user) async {
    setState(() => _togglingUserId = user.uid);
    try {
      await _userRepository.updateUserByAdmin(user.copyWith(isActive: !user.isActive));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            user.isActive ? '${user.name} has been deactivated.' : '${user.name} has been activated.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to update this account.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _togglingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selfUid = AuthState.instance.userModel?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add User'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or phone',
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
              child: StreamBuilder<List<UserModel>>(
                key: ValueKey('users-$_retryToken'),
                stream: _userRepository.streamAllUsers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingWidget(message: 'Loading users...');
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message: 'Unable to load users. Please try again.',
                      onRetry: () => setState(() => _retryToken++),
                    );
                  }

                  final users = snapshot.data ?? const <UserModel>[];
                  final filtered = _filterBySearch(users, _query);

                  if (users.isEmpty) {
                    return EmptyState(
                      title: 'No users yet',
                      message: 'Newly registered customers will show up here.',
                      icon: Icons.people_outline,
                      actionLabel: 'Add User',
                      onAction: _openAddDialog,
                    );
                  }

                  if (filtered.isEmpty) {
                    return const EmptyState(
                      title: 'No users match your search.',
                      icon: Icons.filter_list_off,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => setState(() => _retryToken++),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final user = filtered[index];
                        return AdminUserCard(
                          user: user,
                          isSelf: user.uid == selfUid,
                          isUpdating: _togglingUserId == user.uid,
                          onEdit: () => _openEditDialog(user),
                          onToggleActive: () => _toggleActive(user),
                        );
                      },
                    ),
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