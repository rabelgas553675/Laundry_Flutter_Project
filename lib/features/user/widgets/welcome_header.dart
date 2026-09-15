import 'package:flutter/material.dart';

/// Greeting text block for the top of the User Dashboard.
///
/// Pure typography — no card, background, border, or shadow.
/// Renders:
///   "Hi {name}, " (bold, dark)  "Here's" (italic, dark blue)
///   "Our Laundry Services." (regular weight, dark)
///
/// Display-only widget: takes the name, doesn't know where it came from.
class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({super.key, required this.name});

  final String name;

  // Dark-blue accent used for the italic "Here's".
  static const Color _accentBlue = Color(0xFF0D47A1);
  static const Color _dark = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    // Only the first name/word is shown, e.g. "J.Snow Wick" -> "J.Snow".
    final firstName = trimmed.isNotEmpty ? trimmed.split(' ').first : 'there';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Line 1: "Hi {firstName}, Here's" — bold greeting sized up
          // relative to the tagline below.
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 36,
                height: 1.3,
                letterSpacing: 0.1,
                fontFamily: 'SF Pro Display', // swap for your app's sans-serif
              ),
              children: [
                TextSpan(
                  text: 'Hi $firstName, ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _dark,
                    fontStyle: FontStyle.normal,
                  ),
                ),
                const TextSpan(
                  text: "Here's",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: _accentBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Line 2: "Our Laundry Services." — smaller, lighter weight.
          const Text(
            'Our Laundry Services.',
            style: TextStyle(
              fontSize: 22,
              height: 1.3,
              letterSpacing: 0.1,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              color: _dark,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }
}