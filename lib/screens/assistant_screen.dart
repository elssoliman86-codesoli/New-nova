import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/app_store.dart';
import '../platform/system_island_bridge.dart';
import '../system/nvidia_api.dart';
import '../system/system_models.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';

/// Voice assistant: NVIDIA model, wake word, permissions and a test box.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _wake;
  final TextEditingController _command = TextEditingController();
  final TextEditingController _filter = TextEditingController();

  AppStore? _store;
  List<String>? _models;
  bool _loadingModels = false;
  String? _modelsError;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    final sys = AppScope.read(context).systemSettings;
    _key = TextEditingController(text: sys.aiKey);
    _model = TextEditingController(text: sys.aiModel);
    _wake = TextEditingController(text: sys.wakeWords);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store == null) {
      _store = AppScope.read(context);
      _store!.system.watch();
    }
  }

  @override
  void dispose() {
    _store?.system.unwatch();
    _key.dispose();
    _model.dispose();
    _wake.dispose();
    _command.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    AppScope.read(context).island.toast(
          message,
          icon: error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          tint: error ? NovaColors.danger : NovaColors.success,
        );
  }

  Future<void> _setEnabled(bool value) async {
    final store = AppScope.read(context);
    store.updateSystemSettings(store.systemSettings.copyWith(aiEnabled: value));
    if (!value) return;
    final needs = await store.system.run(() => SystemIslandBridge.requestPermissions(const ['assistant']));
    if (needs != null && mounted) _toast(needs, error: true);
    final err = await store.system.run(SystemIslandBridge.start);
    if (err != null && mounted) _toast('Start the island first: $err', error: true);
  }

  void _saveKey() {
    final store = AppScope.read(context);
    store.updateSystemSettings(store.systemSettings.copyWith(aiKey: _key.text.trim()));
    _toast(_key.text.trim().isEmpty ? 'Key removed' : 'API key saved');
  }

  void _useModel(String id) {
    final store = AppScope.read(context);
    _model.text = id;
    store.updateSystemSettings(store.systemSettings.copyWith(aiModel: id));
    _toast('Model: $id');
  }

  Future<void> _loadModels() async {
    final sys = AppScope.read(context).systemSettings;
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final list = await NvidiaApi.listModels(
        baseUrl: sys.aiBaseUrl,
        key: _key.text.trim().isEmpty ? sys.aiKey : _key.text.trim(),
      );
      if (!mounted) return;
      setState(() => _models = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _modelsError = 'Could not load models: $e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _send() async {
    final text = _command.text.trim();
    if (text.isEmpty) return;
    _command.clear();
    final store = AppScope.read(context);
    final err = await store.system.run(() => SystemIslandBridge.assistantSubmit(text));
    if (err != null && mounted) _toast(err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final sys = store.systemSettings;

    return ScreenScaffold(
      title: 'AI Assistant',
      subtitle: 'Voice commands with your NVIDIA model',
      body: ListenableBuilder(
        listenable: store.system,
        builder: (context, _) {
          final snap = store.system.snapshot;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              NovaLayout.pagePad,
              NovaSpace.sm,
              NovaLayout.pagePad,
              NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.keyboard_voice_rounded,
                    title: 'Voice assistant',
                    subtitle: sys.requireWake
                        ? 'Always listening for the wake word'
                        : 'Always listening, reacts to everything you say',
                    trailing: NeuToggle(
                      value: sys.aiEnabled,
                      semanticLabel: 'Voice assistant',
                      onChanged: _setEnabled,
                    ),
                  ),
                ],
              ),
              if (snap != null) ...[
                const SizedBox(height: NovaSpace.md),
                _StatusCard(snap: snap, enabled: sys.aiEnabled),
              ],
              const SectionHeader(title: 'NVIDIA API'),
              GlassSurface.solid(
                radius: NovaRadius.lg,
                padding: const EdgeInsets.all(NovaSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeuField(
                      controller: _key,
                      label: 'API key (nvapi-…)',
                      icon: Icons.key_rounded,
                      obscureText: !_showKey,
                      suffix: IconButton(
                        tooltip: _showKey ? 'Hide key' : 'Show key',
                        onPressed: () => setState(() => _showKey = !_showKey),
                        icon: Icon(
                          _showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: NovaColors.textDim,
                        ),
                      ),
                    ),
                    const SizedBox(height: NovaSpace.md),
                    NeuButton(label: 'Save key', icon: Icons.save_rounded, onPressed: _saveKey),
                    const SizedBox(height: NovaSpace.sm),
                    const Text(
                      'Get a free key at build.nvidia.com. It is kept only on this phone.',
                      style: NovaType.caption,
                    ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Model'),
              GlassSurface.solid(
                radius: NovaRadius.lg,
                padding: const EdgeInsets.all(NovaSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Using: ${sys.aiModel}', style: NovaType.bodyStrong),
                    const SizedBox(height: NovaSpace.md),
                    NeuField(
                      controller: _model,
                      label: 'Model id',
                      icon: Icons.memory_rounded,
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) _useModel(v.trim());
                      },
                    ),
                    const SizedBox(height: NovaSpace.md),
                    Row(
                      children: [
                        Expanded(
                          child: NeuButton(
                            label: 'Use this id',
                            kind: NeuButtonKind.secondary,
                            onPressed: _model.text.trim().isEmpty ? null : () => _useModel(_model.text.trim()),
                          ),
                        ),
                        const SizedBox(width: NovaSpace.md),
                        Expanded(
                          child: NeuButton(
                            label: _models == null ? 'Load models' : 'Reload',
                            icon: Icons.cloud_download_outlined,
                            loading: _loadingModels,
                            onPressed: _loadModels,
                          ),
                        ),
                      ],
                    ),
                    if (_modelsError != null) ...[
                      const SizedBox(height: NovaSpace.md),
                      Text(_modelsError!, style: NovaType.caption.copyWith(color: NovaColors.danger)),
                    ],
                    if (_models != null) ...[
                      const SizedBox(height: NovaSpace.md),
                      NeuField(
                        controller: _filter,
                        hint: 'Search ${_models!.length} models',
                        icon: Icons.search_rounded,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: NovaSpace.sm),
                      _ModelList(
                        models: _models!,
                        filter: _filter.text,
                        selected: sys.aiModel,
                        onPick: _useModel,
                      ),
                    ],
                  ],
                ),
              ),
              const SectionHeader(title: 'Listening'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.record_voice_over_rounded,
                    title: 'Wake word',
                    subtitle: 'Only act when you say it first',
                    trailing: NeuToggle(
                      value: sys.requireWake,
                      semanticLabel: 'Wake word',
                      onChanged: (v) => store.updateSystemSettings(sys.copyWith(requireWake: v)),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.volume_up_rounded,
                    title: 'Speak replies',
                    subtitle: 'Read the answer aloud',
                    trailing: NeuToggle(
                      value: sys.aiSpeak,
                      semanticLabel: 'Speak replies',
                      onChanged: (v) => store.updateSystemSettings(sys.copyWith(aiSpeak: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NovaSpace.md),
              GlassSurface.solid(
                radius: NovaRadius.lg,
                padding: const EdgeInsets.all(NovaSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Speech language', style: NovaType.label),
                    const SizedBox(height: NovaSpace.sm),
                    NeuSegmented<String>(
                      segments: const [
                        NeuSegment<String>(value: 'ar-EG', label: 'عربي مصري'),
                        NeuSegment<String>(value: 'ar-SA', label: 'عربي'),
                        NeuSegment<String>(value: 'en-US', label: 'English'),
                      ],
                      value: sys.aiLanguage,
                      onChanged: (v) => store.updateSystemSettings(sys.copyWith(aiLanguage: v)),
                    ),
                    const SizedBox(height: NovaSpace.lg),
                    NeuField(
                      controller: _wake,
                      label: 'Wake words (comma separated)',
                      icon: Icons.hearing_rounded,
                      onSubmitted: (v) => store.updateSystemSettings(sys.copyWith(wakeWords: v.trim())),
                      onChanged: (v) => store.updateSystemSettings(sys.copyWith(wakeWords: v.trim())),
                    ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Permissions'),
              _Permissions(snap: snap),
              const SectionHeader(title: 'Try it'),
              GlassSurface.solid(
                radius: NovaRadius.lg,
                padding: const EdgeInsets.all(NovaSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeuField(
                      controller: _command,
                      label: 'Type a command',
                      hint: 'شغل أغنية ...  |  افتح واتساب  |  ابحث عن ...',
                      icon: Icons.chat_bubble_outline_rounded,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                    const SizedBox(height: NovaSpace.md),
                    Row(
                      children: [
                        Expanded(
                          child: NeuButton(label: 'Send', icon: Icons.send_rounded, onPressed: _send),
                        ),
                        const SizedBox(width: NovaSpace.md),
                        Expanded(
                          child: NeuButton(
                            label: 'Talk now',
                            icon: Icons.mic_rounded,
                            kind: NeuButtonKind.secondary,
                            onPressed: () async {
                              final err = await store.system.run(SystemIslandBridge.assistantListen);
                              if (err != null && mounted) _toast(err, error: true);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (snap != null && snap.assistant.reply.isNotEmpty) ...[
                      const SizedBox(height: NovaSpace.md),
                      Text('Nova: ${snap.assistant.reply}', style: NovaType.body),
                    ],
                  ],
                ),
              ),
              const SectionHeader(title: 'What you can say'),
              const _Examples(),
            ],
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snap, required this.enabled});

  final SystemSnapshot snap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final a = snap.assistant;
    final String text;
    Color color = NovaColors.textDim;
    if (!enabled) {
      text = 'Off';
    } else if (!snap.permissions.microphone) {
      text = 'Needs the Microphone permission';
      color = NovaColors.warning;
    } else if (!a.hasKey) {
      text = 'Needs your NVIDIA API key';
      color = NovaColors.warning;
    } else if (!snap.service.running) {
      text = 'Island service is stopped. Start it from the Device tab.';
      color = NovaColors.warning;
    } else if (a.error.isNotEmpty) {
      text = a.error;
      color = NovaColors.danger;
    } else if (a.on) {
      text = a.state == 'listening' && a.wakeStatus.isNotEmpty
          ? a.wakeStatus
          : switch (a.state) {
        'awake' => 'Listening to you…',
        'thinking' => 'Thinking…',
        'speaking' => 'Speaking…',
        _ => 'Waiting for the wake word',
      };
      color = NovaColors.success;
    } else {
      text = 'Starting…';
    }
    return GlassSurface.solid(
      radius: NovaRadius.md,
      padding: const EdgeInsets.all(NovaSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: NovaSpace.sm),
              Expanded(child: Text(text, style: NovaType.bodyStrong.copyWith(color: color))),
            ],
          ),
          if (a.heard.isNotEmpty) ...[
            const SizedBox(height: NovaSpace.sm),
            Text('Last heard: ${a.heard}', style: NovaType.caption),
          ],
        ],
      ),
    );
  }
}

class _Permissions extends StatelessWidget {
  const _Permissions({required this.snap});

  final SystemSnapshot? snap;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.read(context);
    final p = snap?.permissions;

    Widget row(IconData icon, String title, String subtitle, bool ok, VoidCallback onTap) {
      return SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: ok
            ? const Icon(Icons.check_circle_rounded, color: NovaColors.success)
            : NeuButton(label: 'Allow', compact: true, expand: false, onPressed: onTap),
      );
    }

    return SettingsGroup(
      children: [
        row(Icons.mic_rounded, 'Microphone', 'Hear you all the time', p?.microphone ?? false,
            () => store.system.run(() => SystemIslandBridge.requestPermissions(const ['assistant']))),
        row(Icons.contacts_rounded, 'Contacts', 'Call or message people by name', p?.contacts ?? false,
            () => store.system.run(() => SystemIslandBridge.requestPermissions(const ['assistant']))),
        row(Icons.call_rounded, 'Phone calls', 'Start the call directly', p?.callPhone ?? false,
            () => store.system.run(() => SystemIslandBridge.requestPermissions(const ['assistant']))),
        row(Icons.accessibility_new_rounded, 'Accessibility', 'Read/translate the page and type for you',
            p?.accessibility ?? false, () => store.system.run(SystemIslandBridge.openAccessibilitySettings)),
      ],
    );
  }
}

class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.models,
    required this.filter,
    required this.selected,
    required this.onPick,
  });

  final List<String> models;
  final String filter;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final q = filter.trim().toLowerCase();
    final chat = models.where(NvidiaApi.looksLikeChatModel).toList();
    final shown = (q.isEmpty ? chat : models.where((m) => m.toLowerCase().contains(q)).toList());
    if (shown.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(NovaSpace.md),
        child: Text('No models match.', style: NovaType.caption),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final id = shown[i];
          final active = id == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(NovaRadius.sm),
            onTap: () => onPick(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      id,
                      style: NovaType.body.copyWith(
                        color: active ? NovaColors.accent2 : NovaColors.text,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (active) const Icon(Icons.check_rounded, color: NovaColors.accent2, size: 18),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples();

  static const List<String> _lines = [
    'نوفا، شغل أغنية عمرو دياب على يوتيوب',
    'نوفا، شغل فيديو عن طريقة عمل الكشري',
    'نوفا، اتصل بـ أحمد',
    'نوفا، ابعت لماما على واتساب إني جاي',
    'نوفا، افتح تليجرام / افتح الكتاب',
    'نوفا، اقرأ الصفحة / ترجم الصفحة / لخص الصفحة',
    'نوفا، اكتب وراي  (وبعدها قول "خلاص" عشان توقف)',
    'نوفا، ابحث في جوجل عن سعر الدولار',
    'نوفا، وقف الأغنية / الأغنية اللي بعدها',
  ];

  @override
  Widget build(BuildContext context) {
    return GlassSurface.solid(
      radius: NovaRadius.lg,
      padding: const EdgeInsets.all(NovaSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in _lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(line, style: NovaType.body),
            ),
          const SizedBox(height: NovaSpace.sm),
          const Text(
            'Listening uses Android speech recognition (needs internet). '
            'Typing and reading other apps need the Accessibility switch.',
            style: NovaType.caption,
          ),
        ],
      ),
    );
  }
}
