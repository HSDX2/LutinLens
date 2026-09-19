import 'package:flutter/material.dart';
import 'package:librecamera/src/utils/lut_manager.dart';
import 'package:librecamera/src/lut/lut_preview_manager.dart';
import 'package:librecamera/src/utils/preferences.dart';

/// 与自动对焦二级菜单风格一致的 LUT 控制（选择 + 强度）
class LutControlWidget extends StatefulWidget {
  const LutControlWidget({super.key});

  @override
  State<LutControlWidget> createState() => _LutControlWidgetState();
}

class _LutControlWidgetState extends State<LutControlWidget> {
  List<LutFile> _luts = [];
  LutFile? _selectedLut;
  double _strength = 1.0;
  bool _loading = true;

  final List<double> _strengthPresets = const [0.0, 0.3, 0.7, 1.0];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final luts = await LutManager.getAllAssetLuts();
    final savedName = Preferences.getSelectedLutName();
    final strength = Preferences.getLutMixStrength();
    final enabled = Preferences.getLutEnabled();
    // 插入“无”选项在最前
    final none = LutFile(name: '无', path: '', description: 'No LUT');
    final withNone = [none, ...luts];
    LutFile? selected;
    if (!enabled) {
      selected = none;
    } else if (savedName.isNotEmpty) {
      selected = withNone.where((e) => e.name == savedName).firstOrNull;
    }
    selected ??= withNone.firstOrNull; // 默认“无”
    debugPrint('[LUT][UI] 载入 LUT 控件: count=${withNone.length}, saved=$savedName, enabled=$enabled, selected=${selected?.name}, strength=$strength');
    setState(() {
      _luts = withNone;
      _selectedLut = selected;
      _strength = strength;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Row(
      children: [
        const Icon(Icons.filter, color: Colors.blue),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<LutFile>(
            iconEnabledColor: Colors.blue,
            value: _selectedLut,
            selectedItemBuilder: (context) => _luts
                .map((lut) => DropdownMenuItem<LutFile>(
                      value: lut,
                      child: Text(
                        lut.name,
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                      ),
                    ))
                .toList(),
            items: _luts
                .map((lut) => DropdownMenuItem<LutFile>(
                      value: lut,
                      child: Text(
                        lut.name,
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                      ),
                    ))
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _selectedLut = value);
              if (value.path.isEmpty) {
                // 选择“无”
                await Preferences.setSelectedLutName('');
                await Preferences.setSelectedLutPath('');
                await Preferences.setLutEnabled(false);
                LutPreviewManager.instance.disableLut();
              } else {
                await Preferences.setSelectedLutName(value.name);
                await Preferences.setSelectedLutPath(value.path);
                await Preferences.setLutEnabled(true);
                debugPrint('[LUT][UI] 选择 LUT: ${value.name}, path=${value.path}');
                await LutPreviewManager.instance.setCurrentLut(value.path);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.tune, color: Colors.blue),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<double>(
            iconEnabledColor: Colors.blue,
            value: _closestPreset(_strength),
            selectedItemBuilder: (context) => _strengthPresets
                .map((v) => DropdownMenuItem<double>(
                      value: v,
                      child: Text(
                        _labelForStrength(v),
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                      ),
                    ))
                .toList(),
            items: _strengthPresets
                .map((v) => DropdownMenuItem<double>(
                      value: v,
                      child: Text(
                        _labelForStrength(v),
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                      ),
                    ))
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _strength = value);
              debugPrint('[LUT][UI] 设置强度: $value');
              LutPreviewManager.instance.setMixStrength(value);
            },
          ),
        ),
      ],
    );
  }

  String _labelForStrength(double v) {
    final pct = (v * 100).toInt();
    switch (pct) {
      case 0:
        return '关闭';
      case 30:
        return '轻微';
      case 70:
        return '中等';
      case 100:
        return '完整';
      default:
        return '$pct%';
    }
  }

  double _closestPreset(double v) {
    double best = _strengthPresets.first;
    double bestDiff = (v - best).abs();
    for (final s in _strengthPresets) {
      final d = (v - s).abs();
      if (d < bestDiff) {
        best = s;
        bestDiff = d;
      }
    }
    return best;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
