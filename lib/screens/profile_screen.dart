import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';
import '../ui/overlays.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editName(BuildContext context) async {
    final store = AppScope.read(context);
    final name = await showNovaDialog<String>(
      context,
      builder: (ctx) => _NameDialog(initial: store.profile.name),
    );
    if (name != null) store.updateName(name);
  }

  Future<void> _signOut(BuildContext context) async {
    final store = AppScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await showNovaConfirm(
      context,
      title: 'Sign out?',
      message: 'Your tasks stay on this device. Sign in again with the same '
          'email to continue.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!ok) return;
    navigator.popUntil((route) => route.isFirst);
    await store.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final profile = store.profile;
    final doneTasks = store.tasks.where((t) => t.done).length;

    return ScreenScaffold(
      showBack: false,
      title: 'Profile',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          navClearance(context),
        ),
        children: [
          FadeIn(
            child: GlassSurface(
              radius: NovaRadius.xl,
              padding: const EdgeInsets.all(NovaSpace.xl),
              child: Row(
                children: [
                  Avatar(name: profile.name, size: 64),
                  const SizedBox(width: NovaSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isEmpty ? 'Nova user' : profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaType.headline.copyWith(fontSize: 19),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaType.bodyDim,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NovaSpace.lg),
          FadeIn(
            delay: const Duration(milliseconds: 60),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Completed',
                    value: '$doneTasks',
                    icon: Icons.check_circle_outline_rounded,
                    color: NovaColors.success,
                  ),
                ),
                const SizedBox(width: NovaSpace.md),
                Expanded(
                  child: StatTile(
                    label: 'Focus',
                    value: formatMinutes(store.totalFocusMinutes),
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Account'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.person_outline_rounded,
                title: 'Edit name',
                subtitle: profile.name,
                onTap: () => _editName(context),
              ),
              SettingsRow(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: store.unreadCount > 0
                    ? '${store.unreadCount} unread'
                    : 'All caught up',
                onTap: () => pushNova(context, (_) => const NotificationsScreen()),
              ),
              SettingsRow(
                icon: Icons.tune_rounded,
                title: 'Settings',
                subtitle: 'Feedback, display and goals',
                onTap: () => pushNova(context, (_) => const SettingsScreen()),
              ),
            ],
          ),
          const SizedBox(height: NovaSpace.xl),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.logout_rounded,
                title: 'Sign out',
                danger: true,
                onTap: () => _signOut(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: NovaDialogCard(
        icon: Icons.person_outline_rounded,
        title: 'Edit name',
        content: NeuField(
          controller: _controller,
          hint: 'Your name',
          icon: Icons.badge_outlined,
          autofocus: true,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _save(),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Enter your name' : null,
        ),
        actions: [
          NeuButton(label: 'Save', onPressed: _save),
          NeuButton(
            label: 'Cancel',
            kind: NeuButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
