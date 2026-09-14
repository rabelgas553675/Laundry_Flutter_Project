import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../app/constants.dart';
import '../../../app/routes.dart';

/// Cold-start Welcome / Landing Screen.
/// 
/// Serves as the first visual impression for unauthenticated visitors.
/// Dynamically scales across mobile, tablet, and desktop breakpoints.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const double _badgeSize = 80;
  static const double _maxContentWidth = 1440;

  static const double _mobileMax = 430;
  static const double _largeMobileMax = 767;
  static const double _tabletMax = 1023;
  static const double _laptopMax = 1279;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final device = _DeviceType.fromWidth(width);

    final horizontalPadding = _horizontalPadding(device);
    final heroHeight = _heroHeight(device, size);
    final buttonMaxWidth = _buttonMaxWidth(device);
    final titleSize = _clampFont(width, min: 24, max: 36);
    final subtitleSize = _clampFont(width, min: 14, max: 17);
    final heroRadius = device == _DeviceType.mobile ? 32.0 : 48.0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroHeader(height: heroHeight, radius: heroRadius),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        _badgeSize / 2 + 24,
                        horizontalPadding,
                        32,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            children: [
                              Text(
                                AppConstants.appName,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Effortless laundry care, delivered to your door.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: subtitleSize,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 40),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: buttonMaxWidth,
                                ),
                                child: Column(
                                  children: [
                                    _PrimaryPillButton(
                                      label: 'Login',
                                      onPressed: () => Navigator.pushNamed(
                                        context,
                                        AppRoutes.login,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    _SecondaryPillButton(
                                      label: 'Register',
                                      onPressed: () => Navigator.pushNamed(
                                        context,
                                        AppRoutes.register,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: colorScheme.primary,
                                        shape: const StadiumBorder(),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                      ),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            content: const Text(
                                              "Guest browsing isn't available yet — please log in or create an account.",
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'Continue as guest',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: heroHeight - (_badgeSize / 2),
                left: 0,
                right: 0,
                child: Center(child: _LogoBadge(size: _badgeSize)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _horizontalPadding(_DeviceType device) {
    switch (device) {
      case _DeviceType.mobile:
        return 20;
      case _DeviceType.largeMobile:
        return 24;
      case _DeviceType.tablet:
        return 36;
      case _DeviceType.laptop:
        return 48;
      case _DeviceType.desktop:
        return 64;
    }
  }

  static double _buttonMaxWidth(_DeviceType device) {
    switch (device) {
      case _DeviceType.mobile:
      case _DeviceType.largeMobile:
        return double.infinity;
      case _DeviceType.tablet:
        return 400;
      case _DeviceType.laptop:
        return 320;
      case _DeviceType.desktop:
        return 280;
    }
  }

  static double _heroHeight(_DeviceType device, Size screenSize) {
    double height;
    switch (device) {
      case _DeviceType.mobile:
        height = (screenSize.width * 0.65).clamp(220, 280);
        break;
      case _DeviceType.largeMobile:
        height = (screenSize.width * 0.55).clamp(260, 320);
        break;
      case _DeviceType.tablet:
        height = 340;
        break;
      case _DeviceType.laptop:
        height = 380;
        break;
      case _DeviceType.desktop:
        height = 440;
        break;
    }
    return height > screenSize.height * 0.48 ? screenSize.height * 0.48 : height;
  }

  static double _clampFont(
    double width, {
    required double min,
    required double max,
  }) {
    const minW = 340.0;
    const maxW = 1440.0;
    final t = ((width - minW) / (maxW - minW)).clamp(0.0, 1.0);
    return min + (max - min) * t;
  }
}

enum _DeviceType {
  mobile,
  largeMobile,
  tablet,
  laptop,
  desktop;

  static _DeviceType fromWidth(double width) {
    if (width <= WelcomeScreen._mobileMax) return _DeviceType.mobile;
    if (width <= WelcomeScreen._largeMobileMax) return _DeviceType.largeMobile;
    if (width <= WelcomeScreen._tabletMax) return _DeviceType.tablet;
    if (width <= WelcomeScreen._laptopMax) return _DeviceType.laptop;
    return _DeviceType.desktop;
  }
}

/// Dynamic Hero Image section with frosted glass controls.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.height, required this.radius});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/laundry_hero.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0.35, -0.1),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.2),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: _FrostedGlassLanguagePill(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        content: const Text(
                          'Only English is available right now.',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrostedGlassLanguagePill extends StatelessWidget {
  const _FrostedGlassLanguagePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.white.withValues(alpha: 0.15),
          shape: StadiumBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'English',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular app mark with a floating card effect and soft drop shadow.
class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF2C3440), const Color(0xFF14181F)]
                : [const Color(0xFF1F2937), const Color(0xFF111827)],
          ),
        ),
        child: Icon(
          Icons.local_laundry_service_rounded,
          color: Colors.white,
          size: size * 0.44,
        ),
      ),
    );
  }
}

class _PrimaryPillButton extends StatelessWidget {
  const _PrimaryPillButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : const Color(0xFF111827),
          foregroundColor: isDark ? const Color(0xFF111827) : Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SecondaryPillButton extends StatelessWidget {
  const _SecondaryPillButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1.5,
          ),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}