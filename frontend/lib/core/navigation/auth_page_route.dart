import 'package:flutter/material.dart';

/// Custom page route with smooth fade + slide transition animation.
///
/// Used for transitions between login and register screens to create
/// a polished, modern feel.
class FadeSlidePageRoute<T> extends PageRouteBuilder<T> {
  FadeSlidePageRoute({
    required super.pageBuilder,
    super.settings,
    Duration? transitionDuration,
    Duration? reverseTransitionDuration,
    this.slideDirection = SlideDirection.right,
  })  : _transitionDuration =
            transitionDuration ?? const Duration(milliseconds: 400),
        _reverseTransitionDuration =
            reverseTransitionDuration ?? const Duration(milliseconds: 300),
        super(
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade transition
            final fadeTween = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
              ),
            );

            // Slide transition
            final slideTween = Tween<Offset>(
              begin: _getSlideBeginStatic(slideDirection),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
              ),
            );

            // Scale transition (subtle)
            final scaleTween = Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
              ),
            );

            return FadeTransition(
              opacity: fadeTween,
              child: SlideTransition(
                position: slideTween,
                child: ScaleTransition(
                  scale: scaleTween,
                  child: child,
                ),
              ),
            );
          },
        );

  /// Duration for forward transition.
  final Duration _transitionDuration;

  /// Duration for reverse transition (going back).
  final Duration _reverseTransitionDuration;

  /// Direction of the slide animation.
  final SlideDirection slideDirection;

  @override
  Duration get transitionDuration => _transitionDuration;

  @override
  Duration get reverseTransitionDuration => _reverseTransitionDuration;

  static Offset _getSlideBeginStatic(SlideDirection direction) {
    switch (direction) {
      case SlideDirection.left:
        return const Offset(-0.3, 0.0);
      case SlideDirection.right:
        return const Offset(0.3, 0.0);
      case SlideDirection.up:
        return const Offset(0.0, 0.3);
      case SlideDirection.down:
        return const Offset(0.0, -0.3);
    }
  }
}

/// Direction of slide animation.
enum SlideDirection {
  left,
  right,
  up,
  down,
}

/// Helper method to navigate with smooth fade + slide transition.
Future<T?> navigateWithFadeSlide<T>(
  BuildContext context,
  Widget page, {
  SlideDirection direction = SlideDirection.right,
}) {
  return Navigator.of(context).push<T>(
    FadeSlidePageRoute<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      slideDirection: direction,
    ),
  );
}

/// Helper method to replace current route with smooth fade + slide transition.
Future<T?> replaceWithFadeSlide<T>(
  BuildContext context,
  Widget page, {
  SlideDirection direction = SlideDirection.right,
}) {
  return Navigator.of(context).pushReplacement<T, void>(
    FadeSlidePageRoute<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      slideDirection: direction,
    ),
  );
}
