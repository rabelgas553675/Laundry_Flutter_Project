import 'package:flutter/material.dart';

/// A temporary placeholder screen used while a feature's real UI
/// has not been built yet.
///
/// Later parts of the build will replace usages of this widget with
/// actual screens (login, dashboards, etc). Keeping it centralized
/// here means routing can be wired up early without depending on
/// unfinished features.
class PlaceholderScreen extends StatefulWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.message,
  });

  final String title;
  final String? message;

  @override
  State<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

class _PlaceholderScreenState extends State<PlaceholderScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (widget.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.message!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}