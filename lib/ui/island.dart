import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui_prefs.dart';
import 'glass.dart';
import 'neu.dart';

/// A button shown on a floating panel (for example Undo).
class IslandAction {
  const IslandAction({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
}

enum IslandKind { toast, menu }

/// One thing shown on the island: a short notification or an action menu.
class IslandItem {
  const IslandItem({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.icon,
    this.tint,
    this.action,
    this.actions = const <IslandAction>[],
  });

  final int id;
  final IslandKind kind;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? tint;

  /// Single trailing button on a toast.
  final IslandAction? action;

  /// Rows of a menu.
  final List<IslandAction> actions;
}

/// A long-running activity pinned to the island (the focus timer).
class IslandLive {
  const IslandLive({
    required this.title,
    required this.timeText,
    required this.progress,
    required this.running,
    required this.onToggle,
    required this.onStop,
  });

  final String title;
  final String timeText;
  final double progress;
  final bool running;
  final VoidCallback onToggle;
  final VoidCallback onStop;
}

/// Controls what the island shows. Owned by the app store, so screens
/// never need to know how the island is drawn.
class IslandController extends ChangeNotifier {
  /// When false, plain notifications are skipped. Toasts that carry an
  /// action (Undo) and menus are always shown.
  bool enabled = true;

  /// Current toast or menu. Takes priority over [live].
  IslandItem? get current => _current;

  /// The pinned live activity, if any. Updated by the store every second.
  final ValueNotifier<IslandLive?> live = ValueNotifier<IslandLive?>(null);

  bool get liveExpanded => _liveExpanded;

  IslandItem? _current;
  bool _liveExpanded = false;
  Timer? _timer;
  int _nextId = 1;
  bool _disposed = false;

  /// Short, self-dismissing notification.
  void toast(
    String title, {
    String? subtitle,
    IconData? icon,
    Color? tint,
    IslandAction? action,
    Duration? duration,
  }) {
    if (!enabled && action == null) return;
    _timer?.cancel();
    _current = IslandItem(
      id: _nextId++,
      kind: IslandKind.toast,
      title: title,
      subtitle: subtitle,
      icon: icon,
      tint: tint,
      action: action,
    );
    final shownFor =
        duration ?? (action != null ? const Duration(seconds: 5) : const Duration(milliseconds: 2600));
    _timer = Timer(shownFor, dismiss);
    notifyListeners();
  }

  /// Contextual action menu that stays until the user picks or dismisses.
  void showMenu({
    required String title,
    String? subtitle,
    IconData? icon,
    required List<IslandAction> actions,
  }) {
    if (actions.isEmpty) return;
    _timer?.cancel();
    _timer = null;
    Haptics.select();
    _current = IslandItem(
      id: _nextId++,
      kind: IslandKind.menu,
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
    );
    notifyListeners();
  }

  /// Hides the current toast or menu.
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  void expandLive() {
    if (live.value == null || _liveExpanded) return;
    _liveExpanded = true;
    notifyListeners();
  }

  void collapseLive() {
    if (!_liveExpanded) return;
    _liveExpanded = false;
    notifyListeners();
  }

  void toggleLive() => _liveExpanded ? collapseLive() : expandLive();

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    live.dispose();
    super.dispose();
  }
}

final Curve _springCurve = SpringCurve();

class _Spec {
  const _Spec(this.width, this.height, this.key, this.content);

  final double width;
  final double height;
  final Object key;
  final Widget content;
}

/// Hosts the island above everything else (including dialogs and sheets).
/// Install it in `MaterialApp.builder`.
class IslandHost extends StatefulWidget {
  const IslandHost({super.key, required this.controller, required this.child});

  final IslandController controller;
  final Widget child;

  @override
  State<IslandHost> createState() => _IslandHostState();
}

class _IslandHostState extends State<IslandHost> {
  /// Last visible content, kept so the island can animate out.
  _Spec? _last;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final media = MediaQuery.of(context);
    final reduceMotion = UiPrefs.motionReduced(context);

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        ListenableBuilder(
          listenable: Listenable.merge([controller, controller.live]),
          builder: (context, _) {
            final item = controller.current;
            final live = controller.live.value;
            final maxWidth = math.min(media.size.width - 32, 380.0);

            _Spec? spec;
            if (item != null) {
              spec = item.kind == IslandKind.menu
                  ? _menuSpec(item, maxWidth)
                  : _toastSpec(item, maxWidth);
            } else if (live != null && controller.enabled) {
              spec = controller.liveExpanded
                  ? _liveExpandedSpec(live, maxWidth)
                  : _liveCompactSpec(live);
            }
            if (spec != null) _last = spec;

            final shown = spec;
            final visible = shown != null;
            final display = shown ?? _last;
            final showScrim = item?.kind == IslandKind.menu;

            return Stack(
              children: [
                if (showScrim)
                  Positioned.fill(
                    child: _Scrim(onTap: controller.dismiss),
                  ),
                if (display != null)
                  Positioned(
                    top: media.padding.top + 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _IslandBody(
                        spec: display,
                        visible: visible,
                        reduceMotion: reduceMotion,
                        onSwipeUp: () {
                          if (controller.current != null) {
                            controller.dismiss();
                          } else {
                            controller.collapseLive();
                          }
                        },
                        onSwipeDown: () {
                          if (controller.current == null) controller.expandLive();
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------ toast

  _Spec _toastSpec(IslandItem item, double maxWidth) {
    final hasSubtitle = (item.subtitle ?? '').isNotEmpty;
    final height = hasSubtitle ? 60.0 : 52.0;
    return _Spec(
      maxWidth,
      height,
      'toast-${item.id}',
      _ToastContent(
        item: item,
        width: maxWidth,
        height: height,
        onAction: () {
          final action = item.action;
          widget.controller.dismiss();
          action?.onTap();
        },
      ),
    );
  }

  // ------------------------------------------------------------- menu

  _Spec _menuSpec(IslandItem item, double maxWidth) {
    final height = 58.0 + 48.0 * item.actions.length;
    return _Spec(
      maxWidth,
      height,
      'menu-${item.id}',
      _MenuContent(
        item: item,
        width: maxWidth,
        height: height,
        onPick: (action) {
          widget.controller.dismiss();
          action.onTap();
        },
      ),
    );
  }

  // ------------------------------------------------------------- live

  _Spec _liveCompactSpec(IslandLive live) {
    const width = 176.0;
    const height = 40.0;
    return _Spec(
      width,
      height,
      'live-compact',
      _LiveCompactContent(
        live: live,
        width: width,
        height: height,
        onTap: widget.controller.expandLive,
      ),
    );
  }

  _Spec _liveExpandedSpec(IslandLive live, double maxWidth) {
    const height = 188.0;
    return _Spec(
      maxWidth,
      height,
      'live-expanded',
      _LiveExpandedContent(
        live: live,
        width: maxWidth,
        height: height,
        onCollapse: widget.controller.collapseLive,
      ),
    );
  }
}

/// Animated container that morphs between sizes with a spring and fades the
/// content when it changes.
class _IslandBody extends StatelessWidget {
  const _IslandBody({
    required this.spec,
    required this.visible,
    required this.reduceMotion,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  final _Spec spec;
  final bool visible;
  final bool reduceMotion;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  @override
  Widget build(BuildContext context) {
    final sizeDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 480);
    final fadeDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

    final island = AnimatedContainer(
      duration: sizeDuration,
      curve: _springCurve,
      width: spec.width,
      height: spec.height,
      child: GlassSurface.solid(
        radius: 26,
        elevated: true,
        fill: const Color(0xF2070B16),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: spec.width,
            maxWidth: spec.width,
            minHeight: spec.height,
            maxHeight: spec.height,
            child: AnimatedSwitcher(
              duration: fadeDuration,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: KeyedSubtree(key: ValueKey<Object>(spec.key), child: spec.content),
            ),
          ),
        ),
      ),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          duration: fadeDuration,
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          offset: visible ? Offset.zero : const Offset(0, -1.6),
          child: AnimatedOpacity(
            duration: fadeDuration,
            opacity: visible ? 1 : 0,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onVerticalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -200) {
                  onSwipeUp();
                } else if (v > 200) {
                  onSwipeDown();
                }
              },
              child: Material(type: MaterialType.transparency, child: island),
            ),
          ),
        ),
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motionDuration(context, NovaDurations.base),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Semantics(
        label: 'Dismiss menu',
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ColoredBox(color: NovaColors.black(0.4)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ content

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tint, this.size = 30});

  final IconData icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.16),
      ),
      child: Icon(icon, size: size * 0.58, color: tint),
    );
  }
}

class _ToastContent extends StatelessWidget {
  const _ToastContent({
    required this.item,
    required this.width,
    required this.height,
    required this.onAction,
  });

  final IslandItem item;
  final double width;
  final double height;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tint = item.tint ?? NovaColors.accent;
    final action = item.action;
    final subtitle = item.subtitle ?? '';

    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        liveRegion: true,
        label: subtitle.isEmpty ? item.title : '${item.title}. $subtitle',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (item.icon != null) ...[
                _IconBadge(icon: item.icon!, tint: tint),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaType.bodyStrong,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaType.caption,
                      ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 8),
                _PillButton(
                  label: action.label,
                  icon: action.icon,
                  onTap: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tinted button used inside the island.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        height: NovaLayout.minTap - 4,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NovaRadius.pill),
          color: NovaColors.accent.withValues(alpha: 0.18),
          border: Border.all(color: NovaColors.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: NovaColors.accent2),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: NovaType.label.copyWith(color: NovaColors.accent2),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({
    required this.item,
    required this.width,
    required this.height,
    required this.onPick,
  });

  final IslandItem item;
  final double width;
  final double height;
  final ValueChanged<IslandAction> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: SizedBox(
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaType.label.copyWith(color: NovaColors.textDim),
                  ),
                ),
              ),
            ),
            for (final action in item.actions)
              _MenuRow(action: action, onTap: () => onPick(action)),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.action, required this.onTap});

  final IslandAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final danger = action.label.toLowerCase().startsWith('delete');
    final color = danger ? NovaColors.danger : NovaColors.text;
    return Pressable(
      pressedScale: 0.98,
      semanticLabel: action.label,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (action.icon != null) ...[
                Icon(action.icon, size: 20, color: danger ? color : NovaColors.accent2),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaType.body.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveCompactContent extends StatelessWidget {
  const _LiveCompactContent({
    required this.live,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final IslandLive live;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: 'Focus timer ${live.timeText}. ${live.running ? 'Running' : 'Paused'}. Tap to expand.',
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  live.running ? Icons.timer_rounded : Icons.pause_rounded,
                  size: 18,
                  color: live.running ? NovaColors.accent2 : NovaColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    live.timeText,
                    maxLines: 1,
                    style: NovaType.bodyStrong.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CustomPaint(
                    painter: _MiniRingPainter(live.progress),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveExpandedContent extends StatelessWidget {
  const _LiveExpandedContent({
    required this.live,
    required this.width,
    required this.height,
    required this.onCollapse,
  });

  final IslandLive live;
  final double width;
  final double height;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  const Icon(Icons.timer_rounded, size: 18, color: NovaColors.accent2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      live.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaType.label.copyWith(color: NovaColors.textDim),
                    ),
                  ),
                  Pressable(
                    semanticLabel: 'Collapse',
                    onTap: () {
                      Haptics.tap();
                      onCollapse();
                    },
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 22,
                        color: NovaColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(child: Text(live.timeText, style: NovaType.timer)),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: clampDouble(live.progress, 0.0, 1.0),
                minHeight: 6,
                backgroundColor: NovaColors.white(0.08),
                color: NovaColors.accent2,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: NeuButton(
                    label: live.running ? 'Pause' : 'Resume',
                    icon: live.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    kind: NeuButtonKind.secondary,
                    compact: true,
                    onPressed: live.onToggle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeuButton(
                    label: 'Stop',
                    icon: Icons.stop_rounded,
                    kind: NeuButtonKind.danger,
                    compact: true,
                    onPressed: live.onStop,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  const _MiniRingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(1.5);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = NovaColors.white(0.12);
    canvas.drawArc(inset, 0, math.pi * 2, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = NovaColors.accent2;
    canvas.drawArc(inset, -math.pi / 2, math.pi * 2 * clampDouble(progress, 0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
