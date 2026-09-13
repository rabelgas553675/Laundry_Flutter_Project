import 'package:flutter/material.dart';

class ErrorState extends StatefulWidget {
  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: colors.error),
            const SizedBox(height: 16),
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(widget.message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}