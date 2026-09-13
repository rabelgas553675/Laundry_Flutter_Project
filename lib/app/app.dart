import 'package:flutter/material.dart';

import 'constants.dart';
import 'routes.dart';
import 'theme.dart';

/// Root widget of the Laundry Management System.
///
/// Wires together app-wide theming and named routes.
/// This is intentionally minimal at this stage — no auth,
/// no Firebase, no business logic. That comes in later parts.
class LaundryApp extends StatefulWidget {
  const LaundryApp({super.key});

  @override
  State<LaundryApp> createState() => _LaundryAppState();
}

class _LaundryAppState extends State<LaundryApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.home,
      routes: AppRoutes.routes,
    );
  }
}