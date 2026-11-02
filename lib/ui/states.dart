import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/ui_prefs.dart';
import 'glass.dart';
import 'neu.dart';

/// Friendly "nothing here yet" placeholder with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: icon,
      iconColor: NovaColors.accent2,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

/// Error message with a retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: Icons.error_outline_rounded,
      iconColor: NovaColors.danger,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
    );
  }
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NovaSpace.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Semantics(
            container: true,
            label: '$title. $message',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NeuRaised(
                  radius: NovaRadius.pill,
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: Icon(icon, size: 34, color: iconColor),
                  ),
                ),
                const SizedBox(height: NovaSpace.xxl),
                Text(title, textAlign: TextAlign.center, style: NovaType.headline),
                const SizedBox(height: NovaSpace.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: NovaType.bodyDim,
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: NovaSpace.xxl),
                  NeuButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    expand: false,
                    kind: NeuButtonKind.secondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while data loads. One animation controller drives every
/// row, and it is only running while the widget is on screen.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 5, this.rowHeight = 68});

  final int count;
  final double rowHeight;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = UiPrefs.motionReduced(context);
    if (reduce) {
      _controller.stop();
      _started = false;
    } else if (!_started) {
      _controller.repeat();
      _started = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: NovaLayout.pagePad),
          itemCount: widget.count,
          separatorBuilder: (_, __) => const SizedBox(height: NovaSpace.md),
          itemBuilder: (context, index) => AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Container(
                height: widget.rowHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(NovaRadius.md),
                  border: Border.all(color: NovaColors.white(0.05)),
                  gradient: LinearGradient(
                    begin: Alignment(-1.5 + t * 3, 0),
                    end: Alignment(-0.5 + t * 3, 0),
                    colors: [
                      NovaColors.white(0.03),
                      NovaColors.white(0.08),
                      NovaColors.white(0.03),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Centered loading indicator on a glass disc.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: label ?? 'Loading',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassSurface.solid(
              radius: NovaRadius.pill,
              elevated: true,
              child: const SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: NovaSpace.lg),
              Text(label!, style: NovaType.caption),
            ],
          ],
        ),
      ),
    );
  }
}
