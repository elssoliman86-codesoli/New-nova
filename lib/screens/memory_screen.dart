import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../platform/system_island_bridge.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';

/// What Soli remembers about the user. Stored only on this phone.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final TextEditingController _add = TextEditingController();
  List<Map<Object?, Object?>> _facts = const <Map<Object?, Object?>>[];
  bool _loading = true;
  bool _supported = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await SystemIslandBridge.memoryList();
      if (!mounted) return;
      setState(() {
        _facts = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _supported = false;
        _loading = false;
      });
    }
  }

  Future<void> _addFact() async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    _add.clear();
    try {
      await SystemIslandBridge.memoryAdd(text);
    } catch (_) {}
    await _load();
  }

  Future<void> _delete(Object? id) async {
    if (id is! num) return;
    try {
      await SystemIslandBridge.memoryDelete(id.toInt());
    } catch (_) {}
    await _load();
  }

  Future<void> _clear() async {
    try {
      await SystemIslandBridge.memoryClear();
    } catch (_) {}
    await _load();
    if (!mounted) return;
    AppScope.read(context).island.toast(
          'Memory cleared',
          icon: Icons.check_circle_rounded,
          tint: NovaColors.success,
        );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Soli memory',
      subtitle: 'Saved on this phone only',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          GlassSurface.solid(
            radius: NovaRadius.lg,
            padding: const EdgeInsets.all(NovaSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NeuField(
                  controller: _add,
                  label: 'Add a fact',
                  hint: 'مثلا: أنا طالب عمري ٢١ سنة',
                  icon: Icons.edit_note_rounded,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addFact(),
                ),
                const SizedBox(height: NovaSpace.md),
                NeuButton(
                  label: 'Save',
                  icon: Icons.save_rounded,
                  onPressed: _supported ? _addFact : null,
                ),
                const SizedBox(height: NovaSpace.sm),
                const Text(
                  'Say "احفظ المعلومة" or "remember this" and Soli stores it here. '
                  'The facts stay in a file on your phone. When you ask Soli something, '
                  'the facts that matter are sent with the question to your NVIDIA model.',
                  style: NovaType.caption,
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Saved facts'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(NovaSpace.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_supported)
            const Text('Memory works only on Android.', style: NovaType.caption)
          else if (_facts.isEmpty)
            const Text('Nothing saved yet.', style: NovaType.caption)
          else ...[
            GlassSurface.solid(
              radius: NovaRadius.lg,
              padding: const EdgeInsets.symmetric(vertical: NovaSpace.sm),
              child: Column(
                children: [
                  for (final fact in _facts)
                    ListTile(
                      title: Text('${fact['text'] ?? ''}', style: NovaType.body),
                      trailing: IconButton(
                        tooltip: 'Forget this',
                        icon: const Icon(Icons.delete_outline_rounded, color: NovaColors.danger),
                        onPressed: () => _delete(fact['id']),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NovaSpace.md),
            NeuButton(
              label: 'Forget everything',
              icon: Icons.delete_sweep_rounded,
              kind: NeuButtonKind.danger,
              onPressed: _clear,
            ),
          ],
        ],
      ),
    );
  }
}
