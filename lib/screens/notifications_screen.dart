import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/models.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';
import '../ui/states.dart';

/// History of everything Nova told you: completed tasks, focus sessions and
/// system messages. Items are marked as read once the page has opened.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Ids that were unread when the page opened, so they stay highlighted
  /// while you read them.
  late final Set<String> _unreadAtOpen = AppScope.read(context)
      .notifications
      .where((n) => !n.read)
      .map((n) => n.id)
      .toSet();

  @override
  void initState() {
    super.initState();
    // Reading the field above captures the unread set before it is cleared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).markAllRead();
    });
  }

  IconData _iconFor(NotifKind kind) {
    switch (kind) {
      case NotifKind.task:
        return Icons.check_circle_outline_rounded;
      case NotifKind.focus:
        return Icons.timer_outlined;
      case NotifKind.system:
        return Icons.auto_awesome_rounded;
    }
  }

  Color _colorFor(NotifKind kind) {
    switch (kind) {
      case NotifKind.task:
        return NovaColors.success;
      case NotifKind.focus:
        return NovaColors.accent2;
      case NotifKind.system:
        return NovaColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final items = store.notifications;

    return ScreenScaffold(
      title: 'Notifications',
      actions: [
        NeuIconButton(
          icon: Icons.delete_sweep_outlined,
          tooltip: 'Clear all notifications',
          onPressed: items.isEmpty ? null : store.clearNotifications,
        ),
      ],
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'You are all caught up',
              message: 'Completed tasks and focus sessions will show up here.',
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                NovaLayout.pagePad,
                NovaSpace.sm,
                NovaLayout.pagePad,
                NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: NovaSpace.md),
              itemBuilder: (context, index) {
                final note = items[index];
                final unread = _unreadAtOpen.contains(note.id);
                final color = _colorFor(note.kind);
                return Semantics(
                  container: true,
                  label: '${note.title}. ${note.body}. ${timeAgo(note.at)}'
                      '${unread ? '. Unread' : ''}',
                  child: ExcludeSemantics(
                    child: GlassSurface.solid(
                      radius: NovaRadius.md,
                      padding: const EdgeInsets.all(NovaSpace.lg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.15),
                            ),
                            child: Icon(_iconFor(note.kind), size: 20, color: color),
                          ),
                          const SizedBox(width: NovaSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(note.title, style: NovaType.bodyStrong),
                                    ),
                                    if (unread)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: NovaColors.accent,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(note.body, style: NovaType.bodyDim),
                                const SizedBox(height: NovaSpace.sm),
                                Text(
                                  timeAgo(note.at),
                                  style: NovaType.caption
                                      .copyWith(color: NovaColors.textFaint),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
