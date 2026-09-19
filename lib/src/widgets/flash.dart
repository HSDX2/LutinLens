import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:librecamera/src/utils/preferences.dart';
// Removed unused imports

class FlashModeWidget extends StatefulWidget {
  const FlashModeWidget({
    Key? key,
    required this.controller,
    required this.isRearCameraSelected,
    required this.isVideoCameraSelected,
  }) : super(key: key);

  final CameraController? controller;
  final bool isRearCameraSelected;
  final bool isVideoCameraSelected;

  @override
  State<FlashModeWidget> createState() => _FlashModeWidgetState();
}

class _FlashModeWidgetState extends State<FlashModeWidget> {
  void _toggleFlashMode() {
    if (widget.controller != null && widget.controller!.value.isInitialized) {
      if (widget.controller?.value.flashMode == FlashMode.off) {
        _onSetFlashModeButtonPressed(
            widget.isVideoCameraSelected ? FlashMode.torch : FlashMode.always);
      } else if (widget.controller?.value.flashMode == FlashMode.always) {
        _onSetFlashModeButtonPressed(
            widget.isVideoCameraSelected ? FlashMode.off : FlashMode.auto);
      } else if (widget.controller?.value.flashMode == FlashMode.auto) {
        _onSetFlashModeButtonPressed(
            widget.isVideoCameraSelected ? FlashMode.off : FlashMode.torch);
      } else if (widget.controller?.value.flashMode == FlashMode.torch) {
        _onSetFlashModeButtonPressed(FlashMode.off);
      }
    } else {
      null;
    }
  }

  void _onSetFlashModeButtonPressed(FlashMode mode) {
    _setFlashMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      debugPrint('Flash mode set to ${mode.toString().split('.').last}');
    });
  }

  Future<void> _setFlashMode(FlashMode mode) async {
    if (widget.controller == null || !widget.controller!.value.isInitialized) {
      return;
    }

    try {
      await widget.controller!.setFlashMode(mode);
      Preferences.setFlashMode(mode.name);
    } on CameraException catch (e) {
      debugPrint('Error: ${e.code}\nError Message: ${e.description}');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isVideoCameraSelected) {
      if (widget.controller?.value.flashMode == FlashMode.always) {
        _onSetFlashModeButtonPressed(FlashMode.off);
      } else if (widget.controller?.value.flashMode == FlashMode.auto) {
        _onSetFlashModeButtonPressed(FlashMode.off);
      }
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: widget.isRearCameraSelected ? _toggleFlashMode : null,
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Icon(
              _getFlashlightIcon(
                  flashMode: widget.controller != null
                      ? widget.controller!.value.isInitialized
                          ? widget.controller!.value.flashMode
                          : getFlashMode()
                      : FlashMode.off),
              size: 24,
              color: widget.isRearCameraSelected 
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _getFlashlightIcon({required FlashMode flashMode}) {
  switch (flashMode) {
    case FlashMode.always:
      return Icons.flash_on;
    case FlashMode.off:
      return Icons.flash_off;
    case FlashMode.auto:
      return Icons.flash_auto;
    case FlashMode.torch:
      return Icons.highlight;
  }
}

FlashMode getFlashMode() {
  final flashModeString = Preferences.getFlashMode();
  FlashMode flashMode = FlashMode.off;
  for (var mode in FlashMode.values) {
    if (mode.name == flashModeString) flashMode = mode;
  }
  return flashMode;
}
