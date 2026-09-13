// Part 05.4 — Testing & Verification
//
// End-to-end test of the role-based authentication system:
//   Test 1 — User registration → lands on Login (not auto-authenticated
//            into the app), then logs in with those same credentials →
//            User Dashboard, with role = user written to Firestore
//            automatically.
//   Test 2 — Admin login → lands on the Admin Dashboard.
//            (Requires an existing account whose Firestore `role` field
//            has been manually set to "admin" — see docs/PART_05_4_TESTING.md.)
//   Test 3 — Logout clears auth state and blocks re-entry into protected
//            screens (verified here by trying to pop back after logout).
//   Test 4 — Unauthorized access: a normal `user` account that tries to
//            open the admin route directly gets redirected to the User
//            Dashboard, never reaching the Admin screen.
//
// This talks to a REAL Firebase project (or the local Firebase Auth /
// Firestore emulators — recommended, see the doc below), so it is not
// run as part of `flutter test`. Run it with:
//
//   flutter test integration_test/role_based_auth_test.dart -d <device-id>
//
// Update the constants below to match your test environment before running.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:laundry_flutter/app/app.dart';
import 'package:laundry_flutter/core/widgets/app_text_field.dart';

/// --- Test environment configuration -----------------------------------
final String _newUserEmail =
    'qa+${DateTime.now().millisecondsSinceEpoch}@laundryapp.test';
const String _newUserPassword = 'Test1234!';
const String _newUserName = 'QA Test User';
const String _newUserPhone = '09171234567';
const String _newUserAddress = '123 Test St, Sample City';

const String adminEmail = 'admin@laundryapp.test';
const String adminPassword = 'Test1234!';
/// ------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 05.4 — Role-based authentication', () {
    testWidgets(
        'Test 1 — Register → Login screen → role=user → User Dashboard',
        (tester) async {
      await tester.pumpWidget(const LaundryApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();

      await _enterField(tester, 'Full Name', _newUserName);
      await _enterField(tester, 'Email', _newUserEmail);
      await _enterField(tester, 'Phone', _newUserPhone);
      await _enterField(tester, 'Address', _newUserAddress);
      await _enterField(tester, 'Password', _newUserPassword);
      await _enterField(tester, 'Confirm Password', _newUserPassword);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Registration now signs the auto-authenticated account back out and
      // lands on Login — it should NOT skip straight into the dashboard.
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('User Dashboard'), findsNothing);

      // Confirm the account + Firestore profile (role = user) actually
      // work by logging in with the same credentials.
      await _enterField(tester, 'Email', _newUserEmail);
      await _enterField(tester, 'Password', _newUserPassword);
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('User Dashboard'), findsOneWidget);
    });

    testWidgets('Test 2 — Admin login → Admin Dashboard', (tester) async {
      await tester.pumpWidget(const LaundryApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      await _enterField(tester, 'Email', adminEmail);
      await _enterField(tester, 'Password', adminPassword);
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Admin Dashboard'), findsOneWidget);
    });

    testWidgets('Test 3 — Logout clears session and blocks re-entry',
        (tester) async {
      await tester.pumpWidget(const LaundryApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      await _enterField(tester, 'Email', adminEmail);
      await _enterField(tester, 'Password', adminPassword);
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('Admin Dashboard'), findsOneWidget);

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Welcome back'), findsOneWidget);
      expect(Navigator.canPop(tester.element(find.byType(Scaffold).first)),
          isFalse);
    });

    testWidgets(
        'Test 4 — Normal user hitting the admin route is redirected',
        (tester) async {
      await tester.pumpWidget(const LaundryApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      await _enterField(tester, 'Email', _newUserEmail);
      await _enterField(tester, 'Password', _newUserPassword);
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('User Dashboard'), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/admin-dashboard');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('User Dashboard'), findsOneWidget);
      expect(find.text('Admin Dashboard'), findsNothing);
    });
  });
}

Future<void> _enterField(
    WidgetTester tester, String label, String value) async {
  final finder = find.widgetWithText(AppTextField, label);
  await tester.enterText(finder, value);
  await tester.pump();
}