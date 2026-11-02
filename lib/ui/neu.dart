import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/motion.dart';
import '../core/tokens.dart';

/// Soft raised surface (neumorphism): a dark shadow bottom-right and a faint
/// light one top-left. When [pressed] it settles down.
class NeuRaised extends StatelessWidget {
  const NeuRaised({
    super.key,
    required this.child,
    this.radius = NovaRadius.md,
    this.padding,
    this.pressed = false,
    this.small = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool pressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motionDuration(context, NovaDurations.fast),
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pressed
              ? const [NovaColors.surfaceLow, NovaColors.surface]
              : const [Color(0xFF16223D), NovaColors.surface],
        ),
        border: Border.all(
          color: NovaColors.white(pressed ? 0.03 : 0.07),
          width: 1,
        ),
        boxShadow: pressed
            ? NovaShadows.pressed
            : (small ? NovaShadows.raisedSmall : NovaShadows.raised),
      ),
      child: child,
    );
  }
}

/// Recessed surface for inputs and tracks, with a real inner shadow.
class NeuInset extends StatelessWidget {
  const NeuInset({
    super.key,
    required this.child,
    this.radius = NovaRadius.md,
    this.padding,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: _InsetPainter(radius),
        child: AnimatedContainer(
          duration: motionDuration(context, NovaDurations.fast),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? NovaColors.white(0.05),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InsetPainter extends CustomPainter {
  const _InsetPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060B16), Color(0xFF0B1426)],
        ).createShader(rect),
    );

    // Inner shadow: paint everything outside the shape, blurred and shifted,
    // clipped back to the shape.
    canvas.save();
    canvas.clipRRect(rrect);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(40))
      ..addRRect(rrect);
    canvas.drawPath(
      outside.shift(const Offset(2.5, 3)),
      Paint()
        ..color = const Color(0xCC020409)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InsetPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

enum NeuButtonKind { primary, secondary, danger }

/// Full-width (or compact) button. Primary is electric blue; secondary is a
/// raised neumorphic key.
class NeuButton extends StatefulWidget {
  const NeuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = NeuButtonKind.primary,
    this.loading = false,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NeuButtonKind kind;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final primary = widget.kind == NeuButtonKind.primary;
    final contentColor = primary
        ? Colors.white
        : (widget.kind == NeuButtonKind.danger
            ? NovaColors.danger
            : NovaColors.text);
    final height = widget.compact ? 40.0 : 52.0;

    final content = widget.loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: contentColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: contentColor),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaType.bodyStrong.copyWith(
                    color: contentColor,
                    fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          );

    final Widget surface = primary
        ? AnimatedContainer(
            duration: motionDuration(context, NovaDurations.fast),
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NovaRadius.md),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3380F0), NovaColors.accentDeep],
              ),
              border: Border.all(color: NovaColors.white(0.18), width: 1),
              boxShadow: _down
                  ? NovaShadows.glow(NovaColors.accent, alpha: 0.18, blur: 8)
                  : NovaShadows.glow(NovaColors.accent, alpha: 0.32),
            ),
            child: content,
          )
        : NeuRaised(
            pressed: _down,
            small: true,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: SizedBox(
              height: height - 2,
              child: Center(child: content),
            ),
          );

    final button = AnimatedScale(
      scale: (_down && enabled) ? 0.98 : 1.0,
      duration: motionDuration(context, const Duration(milliseconds: 110)),
      curve: Curves.easeOutCubic,
      child: Opacity(opacity: enabled || widget.loading ? 1 : 0.5, child: surface),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? widget.onPressed : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: enabled
            ? () {
                Haptics.tap();
                widget.onPressed!();
              }
            : null,
        child: widget.expand
            ? SizedBox(width: double.infinity, child: button)
            : button,
      ),
    );
  }
}

/// Round raised icon button with an optional unread badge.
class NeuIconButton extends StatefulWidget {
  const NeuIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
    this.badgeCount = 0,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool active;
  final int badgeCount;
  final double size;

  @override
  State<NeuIconButton> createState() => _NeuIconButtonState();
}

class _NeuIconButtonState extends State<NeuIconButton> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final face = NeuRaised(
      radius: NovaRadius.pill,
      small: true,
      pressed: _down,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Icon(
          widget.icon,
          size: 20,
          color: widget.active ? NovaColors.accent2 : NovaColors.text,
        ),
      ),
    );

    final withBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        face,
        if (widget.badgeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NovaColors.accent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: NovaColors.bg, width: 1.5),
              ),
              child: Text(
                widget.badgeCount > 9 ? '9+' : '${widget.badgeCount}',
                style: NovaType.micro.copyWith(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          onTap: enabled
              ? () {
                  Haptics.tap();
                  widget.onPressed!();
                }
              : null,
          child: withBadge,
        ),
      ),
    );
  }
}

/// Recessed track with a raised knob. The knob lights up in electric blue.
class NeuToggle extends StatelessWidget {
  const NeuToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(context, NovaDurations.base);
    return Semantics(
      toggled: value,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onChanged(!value);
        },
        child: SizedBox(
          width: 56,
          height: NovaLayout.minTap,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: 52,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: value
                    ? NovaColors.accent.withValues(alpha: 0.22)
                    : NovaColors.surfaceLow,
                border: Border.all(
                  color: value
                      ? NovaColors.accent.withValues(alpha: 0.55)
                      : NovaColors.white(0.08),
                  width: 1,
                ),
              ),
              child: AnimatedAlign(
                duration: duration,
                curve: Curves.easeOutBack,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: duration,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: value
                          ? const [NovaColors.accent2, NovaColors.accent]
                          : const [Color(0xFF22304F), Color(0xFF141F38)],
                    ),
                    boxShadow: value
                        ? NovaShadows.glow(NovaColors.accent, alpha: 0.5, blur: 10)
                        : NovaShadows.raisedSmall,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round task checkbox: recessed when empty, glowing blue when checked.
class NeuCheck extends StatelessWidget {
  const NeuCheck({
    super.key,
    required this.checked,
    required this.onChanged,
    this.size = 26,
    this.semanticLabel,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(context, NovaDurations.base);
    return Semantics(
      checked: checked,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: () => onChanged(!checked),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onChanged(!checked);
        },
        child: SizedBox(
          width: NovaLayout.minTap,
          height: NovaLayout.minTap,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: checked
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [NovaColors.accent2, NovaColors.accent],
                      )
                    : null,
                color: checked ? null : NovaColors.surfaceLow,
                border: Border.all(
                  color: checked
                      ? NovaColors.white(0.25)
                      : NovaColors.white(0.16),
                  width: 1.2,
                ),
                boxShadow: checked
                    ? NovaShadows.glow(NovaColors.accent, alpha: 0.4, blur: 10)
                    : null,
              ),
              child: AnimatedOpacity(
                duration: duration,
                opacity: checked ? 1 : 0,
                child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recessed text input with an optional label above and an inline error.
/// Works with or without a surrounding [Form].
class NeuField extends StatefulWidget {
  const NeuField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.icon,
    this.obscureText = false,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.suffix,
    this.autofocus = false,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final bool obscureText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final int? minLines;
  final Widget? suffix;
  final bool autofocus;
  final bool enabled;
  final TextCapitalization textCapitalization;

  @override
  State<NeuField> createState() => _NeuFieldState();
}

class _NeuFieldState extends State<NeuField> {
  TextEditingController? _own;
  bool _focused = false;

  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: _controller.text,
      validator: widget.validator,
      builder: (state) {
        final hasError = state.hasError;
        final Color? borderColor = hasError
            ? NovaColors.danger.withValues(alpha: 0.8)
            : (_focused ? NovaColors.accent2.withValues(alpha: 0.8) : null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  widget.label!,
                  style: NovaType.label.copyWith(color: NovaColors.textDim),
                ),
              ),
            NeuInset(
              borderColor: borderColor,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: _focused ? NovaColors.accent2 : NovaColors.textDim,
                      ),
                    ),
                  Expanded(
                    child: Focus(
                      onFocusChange: (focused) {
                        if (mounted) setState(() => _focused = focused);
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: widget.focusNode,
                        obscureText: widget.obscureText,
                        keyboardType: widget.keyboardType,
                        textInputAction: widget.textInputAction,
                        textCapitalization: widget.textCapitalization,
                        autofillHints: widget.autofillHints,
                        autofocus: widget.autofocus,
                        enabled: widget.enabled,
                        maxLines: widget.maxLines,
                        minLines: widget.minLines,
                        style: NovaType.body,
                        cursorColor: NovaColors.accent2,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          hintText: widget.hint,
                          hintStyle: NovaType.body
                              .copyWith(color: NovaColors.textFaint),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onChanged: (value) {
                          state.didChange(value);
                          widget.onChanged?.call(value);
                        },
                        onSubmitted: widget.onSubmitted,
                      ),
                    ),
                  ),
                  if (widget.suffix != null) widget.suffix!,
                ],
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 6),
                child: Text(
                  state.errorText ?? '',
                  style: NovaType.caption.copyWith(color: NovaColors.danger),
                ),
              ),
          ],
        );
      },
    );
  }
}

class NeuSegment<T> {
  const NeuSegment({required this.value, required this.label, this.color});

  final T value;
  final String label;
  final Color? color;
}

/// Segmented control: recessed track with a raised sliding thumb.
class NeuSegmented<T> extends StatelessWidget {
  const NeuSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<NeuSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final found = segments.indexWhere((s) => s.value == value);
    final index = found < 0 ? 0 : found;
    final duration = motionDuration(context, NovaDurations.base);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 4px padding and a 1px border on each side of the track.
        final inner = constraints.maxWidth - 10;
        final segmentWidth = inner / segments.length;
        return NeuInset(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 44,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  left: index * segmentWidth,
                  top: 0,
                  width: segmentWidth,
                  height: 44,
                  child: const NeuRaised(
                    radius: NovaRadius.sm,
                    small: true,
                    child: SizedBox.expand(),
                  ),
                ),
                Row(
                  children: [
                    for (final segment in segments)
                      Expanded(
                        child: Pressable(
                          pressedScale: 0.98,
                          semanticLabel: segment.label,
                          onTap: () {
                            Haptics.tap();
                            onChanged(segment.value);
                          },
                          child: Center(
                            child: Text(
                              segment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NovaType.label.copyWith(
                                color: segment.value == value
                                    ? (segment.color ?? NovaColors.accent2)
                                    : NovaColors.textDim,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
