import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui_prefs.dart';
import 'glass.dart';
import 'neu.dart';

/// Glass confirmation dialog. Returns true when the user confirms.
Future<bool> showNovaConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final result = await showNovaDialog<bool>(
    context,
    builder: (ctx) => NovaDialogCard(
      icon: icon,
      iconColor: destructive ? NovaColors.danger : NovaColors.accent2,
      title: title,
      message: message,
      actions: [
        NeuButton(
          label: cancelLabel,
          kind: NeuButtonKind.secondary,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        NeuButton(
          label: confirmLabel,
          kind: destructive ? NeuButtonKind.danger : NeuButtonKind.primary,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Opens [builder] in a dimmed, scale-and-fade dialog.
Future<T?> showNovaDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final reduce = UiPrefs.motionReducedNow(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Dismiss',
    barrierColor: NovaColors.black(0.55),
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NovaSpace.xxl),
          child: Material(type: MaterialType.transparency, child: builder(ctx)),
        ),
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Standard dialog body: icon, title, message and a row of buttons.
class NovaDialogCard extends StatelessWidget {
  const NovaDialogCard({
    super.key,
    required this.title,
    required this.actions,
    this.message,
    this.icon,
    this.iconColor = NovaColors.accent2,
    this.content,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Color iconColor;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: GlassSurface(
        radius: NovaRadius.xl,
        blur: 24,
        fill: const Color(0xE6101A2E),
        padding: const EdgeInsets.all(NovaSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null)
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withValues(alpha: 0.14),
                  ),
                  child: Icon(icon, size: 26, color: iconColor),
                ),
              ),
            if (icon != null) const SizedBox(height: NovaSpace.lg),
            Semantics(
              header: true,
              child: Text(title, textAlign: TextAlign.center, style: NovaType.headline),
            ),
            if (message != null) ...[
              const SizedBox(height: NovaSpace.sm),
              Text(message!, textAlign: TextAlign.center, style: NovaType.bodyDim),
            ],
            if (content != null) ...[
              const SizedBox(height: NovaSpace.lg),
              content!,
            ],
            const SizedBox(height: NovaSpace.xxl),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: NovaSpace.md),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Glass bottom sheet that rises with the keyboard and has a drag handle.
Future<T?> showNovaSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
}) {
  final reduce = UiPrefs.motionReducedNow(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: NovaColors.black(0.5),
    sheetAnimationStyle: reduce
        ? const AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero)
        : const AnimationStyle(
            duration: Duration(milliseconds: 340),
            reverseDuration: Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          ),
    builder: (ctx) => NovaSheetFrame(scrollable: scrollable, child: builder(ctx)),
  );
}

class NovaSheetFrame extends StatelessWidget {
  const NovaSheetFrame({super.key, required this.child, this.scrollable = true});

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inner = Padding(
      padding: EdgeInsets.fromLTRB(
        NovaLayout.pagePad,
        NovaSpace.sm,
        NovaLayout.pagePad,
        NovaSpace.xxl + media.padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: NovaSpace.lg),
              decoration: BoxDecoration(
                color: NovaColors.white(0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (scrollable)
            Flexible(child: SingleChildScrollView(child: child))
          else
            child,
        ],
      ),
    );

    return AnimatedPadding(
      duration: motionDuration(context, const Duration(milliseconds: 120)),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(NovaRadius.xl)),
          child: BackdropFilter(
            filter: UiPrefs.blurReduced(context)
                ? ImageFilter.blur()
                : ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: UiPrefs.blurReduced(context)
                    ? NovaColors.bg3
                    : const Color(0xE60E1729),
                border: Border(top: BorderSide(color: NovaColors.white(0.14))),
              ),
              child: inner,
            ),
          ),
        ),
      ),
    );
  }
}
