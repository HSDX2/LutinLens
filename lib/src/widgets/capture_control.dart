import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:librecamera/main.dart';

class CaptureControlWidget extends StatefulWidget {
  const CaptureControlWidget({
    Key? key,
    required this.controller,
    required this.onTakePictureButtonPressed,
    required this.onNewCameraSelected,
    required this.leadingWidget,
    required this.isRearCameraSelected,
    required this.setIsRearCameraSelected,
  }) : super(key: key);

  final CameraController? controller;
  final VoidCallback onTakePictureButtonPressed;
  final Function(CameraDescription) onNewCameraSelected;
  final Widget leadingWidget;
  final bool isRearCameraSelected;
  final Function() setIsRearCameraSelected;

  @override
  State<CaptureControlWidget> createState() => _CaptureControlWidgetState();
}

class _CaptureControlWidgetState extends State<CaptureControlWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController animationController;
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  @override
  void initState() {
    animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    super.initState();
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  Widget captureButton() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(36),
          onTap: () => widget.onTakePictureButtonPressed(),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Icon(
              Icons.camera_alt,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget switchButton() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainer,
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
          onTap: () {
            widget.onNewCameraSelected(
                cameras[widget.isRearCameraSelected ? 1 : 0]);
            widget.setIsRearCameraSelected();

            animationController.reset();
            animationController.forward();
          },
          child: AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(animationController.value * 6),
                child: Icon(
                  widget.isRearCameraSelected
                      ? Icons.camera_front_outlined
                      : Icons.camera_rear_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          widget.leadingWidget,
          captureButton(),
          FutureBuilder(
            future: deviceInfo.androidInfo,
            builder: (context, snapshot) {
              return switchButton();
            },
          ),
        ],
      ),
    );
  }
}
