import 'package:flutter/material.dart';

class LoadingWidget extends StatefulWidget {
  const LoadingWidget({super.key, this.message});

  final String? message;

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (widget.message != null) ...[
            const SizedBox(height: 16),
            Text(widget.message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}