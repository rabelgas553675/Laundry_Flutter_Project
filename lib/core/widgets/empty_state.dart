import 'package:flutter/material.dart';

class EmptyState extends StatefulWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 56, color: colors.outline),
            const SizedBox(height: 16),
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (widget.message != null) ...[
              const SizedBox(height: 8),
              Text(widget.message!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
            if (widget.actionLabel != null && widget.onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: widget.onAction, child: Text(widget.actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}