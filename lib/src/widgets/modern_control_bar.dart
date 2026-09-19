import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// Modern Material 3 control bar for camera modes
class ModernControlBar extends StatefulWidget {
  final CameraController? controller;
  
  const ModernControlBar({
    Key? key,
    this.controller,
  }) : super(key: key);

  @override
  State<ModernControlBar> createState() => _ModernControlBarState();
}

class _ModernControlBarState extends State<ModernControlBar> {
  int selectedMode = 0; // 0: Photo, 1: Video, 2: Portrait

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment<int>(
            value: 0,
            icon: Icon(Icons.camera_alt_outlined),
            label: Text('照片'),
          ),
          ButtonSegment<int>(
            value: 1,
            icon: Icon(Icons.videocam_outlined),
            label: Text('视频'),
          ),
          ButtonSegment<int>(
            value: 2,
            icon: Icon(Icons.portrait_outlined),
            label: Text('人像'),
          ),
        ],
        selected: {selectedMode},
        onSelectionChanged: (Set<int> newSelection) {
          setState(() {
            selectedMode = newSelection.first;
          });
          _handleModeChange(selectedMode);
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _handleModeChange(int mode) {
    // Handle camera mode change
    switch (mode) {
      case 0:
        // Photo mode
        debugPrint('切换到拍照模式');
        break;
      case 1:
        // Video mode
        debugPrint('切换到录像模式');
        break;
      case 2:
        // Portrait mode
        debugPrint('切换到人像模式');
        break;
    }
  }
}
