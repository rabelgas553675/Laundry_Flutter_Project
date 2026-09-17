import 'dart:ui';
import 'package:flutter/material.dart';

/// Glass-style search bar shown at the top of the Home tab, replacing
/// the old logo + "HYDRO" wordmark lockup. `name` is kept as a
/// parameter (unused visually) so existing call sites like
/// `WelcomeHeader(name: userName)` keep compiling without changes.
class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({
    super.key,
    this.name,
    this.onChanged,
    this.onTap,
    this.controller,
    this.hintText = 'Search',
    this.maxHeight = 56,
  });

  final String? name;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final String hintText;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final double barHeight = maxHeight;

    return SizedBox(
      height: maxHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(barHeight / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: barHeight,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: barHeight * 0.45,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: onTap,
                      child: TextField(
                        controller: controller,
                        onChanged: onChanged,
                        readOnly: onTap != null,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: const TextStyle(
                            color: Colors.black45,
                            fontSize: 15,
                          ),
                          filled: false,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  // Clear ("x") button — only meaningful when this is a
                  // real, writable search field (has a controller and
                  // isn't just a read-only tap-to-open trigger), and only
                  // shown once there's actually something to clear.
                  if (controller != null && onTap == null)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller!,
                      builder: (context, value, _) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            controller!.clear();
                            onChanged?.call('');
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.close_rounded,
                              size: barHeight * 0.4,
                              color: Colors.black45,
                            ),
                          ),
                        );
                      },
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