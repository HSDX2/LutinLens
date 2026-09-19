import 'package:flutter/material.dart';
import 'package:librecamera/src/lut/lut_preview_manager.dart';
import 'package:librecamera/src/utils/lut_manager.dart';
import 'package:librecamera/src/utils/preferences.dart';

/// 底部弹出的 LUT 预设滚轮
class LutPresetWheel extends StatefulWidget {
  final bool isVisible;
  final VoidCallback? onDismiss;

  const LutPresetWheel({
    super.key,
    this.isVisible = false,
    this.onDismiss,
  });

  @override
  State<LutPresetWheel> createState() => _LutPresetWheelState();
}

class _LutPresetWheelState extends State<LutPresetWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slide;
  List<LutFile> _luts = [];
  String _currentName = Preferences.getSelectedLutName();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slide = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _loadLuts();
    if (widget.isVisible) _controller.forward();
  }

  Future<void> _loadLuts() async {
    try {
      // 改为直接从 assets 读取 LUT 列表
      final luts = await LutManager.getAllAssetLuts();
      final none = LutFile(name: '无', path: '', description: 'No LUT');
      final withNone = [none, ...luts];
      if (mounted) {
        setState(() {
          _luts = withNone;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(LutPresetWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slide.value * 220),
          child: Opacity(opacity: 1 - _slide.value, child: child),
        );
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LUT 预设',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  tooltip: '关闭',
                )
              ],
            ),
          ),
          SizedBox(
            height: 84,
            child: _buildListArea(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildListArea() {
    if (_loading) {
      return const Center(
        child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator()),
      );
    }

    if (_luts.isEmpty) {
      return const Center(
        child: Text('未找到任何 LUT 资源', style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: _luts.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final lut = _luts[index];
        final selected = (_currentName.isEmpty && lut.path.isEmpty) || lut.name == _currentName;
        return _LutChip(
          label: lut.name,
          selected: selected,
          onTap: () => _applyLut(lut),
        );
      },
    );
  }

  // 不再支持安装拷贝，使用 assets 静态资源

  Future<void> _applyLut(LutFile lut) async {
    try {
      if (lut.path.isEmpty) {
        // 选择“无”
        await Preferences.setSelectedLutName('');
        await Preferences.setSelectedLutPath('');
        await Preferences.setLutEnabled(false);
        LutPreviewManager.instance.disableLut();
        setState(() => _currentName = '');
      } else {
        // 停止图像流，安全切换 LUT
        await LutPreviewManager.instance.stopImageStream();
        await LutPreviewManager.instance.setCurrentLut(lut.path);

        // 持久化选择
        await Preferences.setSelectedLutName(lut.name);
        await Preferences.setSelectedLutPath(lut.path);
        await Preferences.setLutEnabled(true);

        setState(() => _currentName = lut.name);

        // 稍作延迟后恢复流，避免切换抖动
        Future.delayed(const Duration(milliseconds: 200), () {
          LutPreviewManager.instance.resumeImageStream();
        });
      }
    } catch (e) {
      // 出错也尽量恢复
      LutPreviewManager.instance.resumeImageStream();
    }
  }
}

class _LutChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LutChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
