import 'package:flutter/material.dart';

/// Greeting banner at the top of the User Dashboard.
/// Pure display widget — takes the name, doesn't know where it came from.
class WelcomeHeader extends StatefulWidget {
  const WelcomeHeader({super.key, required this.name});

  final String name;

  @override
  State<WelcomeHeader> createState() => _WelcomeHeaderState();
}

class _WelcomeHeaderState extends State<WelcomeHeader> {
  String get _initial =>
      widget.name.trim().isNotEmpty ? widget.name.trim()[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: colors.primaryContainer,
          child: Text(
            _initial,
            style: textTheme.titleLarge?.copyWith(color: colors.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: textTheme.bodyMedium),
              Text(
                widget.name.isNotEmpty ? widget.name : 'there',
                style: textTheme.headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}