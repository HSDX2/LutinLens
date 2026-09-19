import 'package:flutter/material.dart';
import 'lut_preview_manager.dart';

/// LUT混合强度快速控制组件
class LutMixControl extends StatefulWidget {
  final bool isVisible;
  final VoidCallback? onDismiss;

  const LutMixControl({
    super.key,
    this.isVisible = false,
    this.onDismiss,
  });

  @override
  State<LutMixControl> createState() => _LutMixControlState();
}

class _LutMixControlState extends State<LutMixControl>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  double _mixStrength = 1.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _mixStrength = LutPreviewManager.instance.mixStrength;
    
    if (widget.isVisible) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(LutMixControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 200),
          child: Opacity(
            opacity: 1.0 - _slideAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LUT 强度',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.filter_b_and_w,
                  color: Colors.white70,
                  size: 20,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.grey[600],
                      thumbColor: Colors.blue,
                      overlayColor: Colors.blue.withValues(alpha: 0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _mixStrength,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (value) {
                        setState(() {
                          _mixStrength = value;
                        });
                        LutPreviewManager.instance.setMixStrength(value);
                      },
                    ),
                  ),
                ),
                const Icon(
                  Icons.filter,
                  color: Colors.white70,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${(_mixStrength * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPresetButton('关闭', 0.0),
                _buildPresetButton('轻微', 0.3),
                _buildPresetButton('中等', 0.7),
                _buildPresetButton('完整', 1.0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton(String label, double value) {
    final isSelected = (_mixStrength - value).abs() < 0.05;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _mixStrength = value;
        });
        LutPreviewManager.instance.setMixStrength(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
