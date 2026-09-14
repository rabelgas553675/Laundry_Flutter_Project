import 'package:flutter/material.dart';

/// Shared header for the secondary auth screens (Login, Register,
/// Forgot Password) that reuses the same hero photograph, rounded
/// bottom corners, and gradient treatment as [WelcomeScreen] — so the
/// whole auth flow reads as one visual family instead of Welcome
/// being the only screen with the photo.
///
/// Unlike Welcome's hero (which sits above unrelated content), this
/// header carries its own title/subtitle directly over the image, and
/// an optional back button for screens reached by pushing forward
/// (Register, Forgot Password) rather than being the app's landing
/// screen.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final String subtitle;

  /// When provided, shows a circular back button top-left. Login is
  /// reached fresh from Welcome so it omits this; Register and Forgot
  /// Password are pushed on top of another screen so they pass
  /// `Navigator.pop`.
  final VoidCallback? onBack;

  static const double _radius = 36;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    // Shorter than Welcome's hero since this header shares the screen
    // with a form rather than being the primary visual, but it scales
    // down further on narrow phones the same way Welcome's does.
    final height = width <= 430 ? 280.0 : 320.0;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(_radius),
        bottomRight: Radius.circular(_radius),
      ),
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
            // Heavier gradient than Welcome's — title/subtitle text
            // sits directly on the photo here, so it needs guaranteed
            // contrast rather than a light top-only fade.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
            if (onBack != null)
              Positioned(
                top: 8,
                left: 8,
                child: SafeArea(
                  bottom: false,
                  child: _CircleIconButton(
                    icon: Icons.arrow_back,
                    onTap: onBack!,
                  ),
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}