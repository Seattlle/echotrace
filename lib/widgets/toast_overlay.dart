import 'dart:async';
import 'package:flutter/material.dart';

/// A utility class for showing custom toast messages using Overlay.
/// Requires the parent widget to include [TickerProviderStateMixin].
class ToastOverlay {
  final TickerProvider vsync;

  OverlayEntry? _entry;
  AnimationController? _controller;
  Timer? _timer;

  ToastOverlay(this.vsync);

  void show(
    BuildContext context,
    String message, {
    bool success = true,
    Duration duration = const Duration(seconds: 4),
  }) {
    _hideSync(); // Clear existing toast immediately

    final overlay = Overlay.of(context);

    _controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );

    final curved = CurvedAnimation(
      parent: _controller!,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _entry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context).colorScheme;
        final Color tone = success ? theme.primary : theme.error;
        final Color surface = theme.surface;
        final Color bg = Color.lerp(surface, tone, 0.16) ?? surface;
        final Color textColor = Color.lerp(tone, Colors.black, 0.1) ?? tone;

        return Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(curved),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tone.withValues(alpha: 0.28)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 18,
                            offset: const Offset(0, 11),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            success
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            color: textColor,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: hide,
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.all(4),
                            ),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_entry!);
    _controller!.forward();
    _timer = Timer(duration, hide);
  }

  void hide() {
    _timer?.cancel();
    _timer = null;

    if (_controller == null || _entry == null) return;

    _controller!.reverse().whenComplete(() {
      _hideSync();
    });
  }

  void _hideSync() {
    _entry?.remove();
    _entry = null;
    _controller?.dispose();
    _controller = null;
  }

  void dispose() {
    _timer?.cancel();
    _hideSync();
  }
}
