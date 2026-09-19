import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

//import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_android_volume_keydown/flutter_android_volume_keydown.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import 'package:librecamera/main.dart';
import 'package:librecamera/src/widgets/resolution.dart';
import 'package:librecamera/src/widgets/timer.dart';
// import 'package:permission_handler/permission_handler.dart';
//import 'package:qr_code_scanner/qr_code_scanner.dart' as qr;

import 'package:librecamera/src/pages/settings_page.dart';
import 'package:librecamera/src/utils/preferences.dart';
import 'package:librecamera/src/widgets/exposure.dart';
import 'package:librecamera/src/widgets/flash.dart';
import 'package:librecamera/src/widgets/focus.dart';
import 'package:librecamera/src/widgets/capture_control.dart';
import 'package:librecamera/src/lut/lut_preview_manager.dart';
import 'package:librecamera/src/lut/cube_loader.dart';
import 'package:librecamera/src/lut/software_lut_processor.dart';
import 'package:librecamera/src/lut/gpu_lut_still_renderer.dart';
import 'package:librecamera/src/widgets/lut_controls.dart';
import 'package:librecamera/src/services/ai_suggestion_service.dart';
// import 'package:librecamera/src/widgets/gallery_widget.dart'; // Removed: file not present; using _buildThumbnailWidget instead

/// Camera example home widget.
class CameraPage extends StatefulWidget {
  /// Default Constructor
  const CameraPage({Key? key}) : super(key: key);

  @override
  State<CameraPage> createState() {
    return _CameraPageState();
  }
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  //Controllers
  File? capturedFile;
  CameraController? controller;

  //Zoom
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  int _pointers = 0;

  //Exposure
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;

  //Current camera
  bool isRearCameraSelected = Preferences.getStartWithRearCamera();
  bool takingPicture = false;

  //Circle position
  double _circlePosX = 0, _circlePosY = 0;
  bool _circleEnabled = false;
  final Tween<double> _scaleTween = Tween<double>(begin: 1, end: 0.75);

  //Photo capture timer
  final Stopwatch _timerStopwatch = Stopwatch();

  //Volume buttons
  StreamSubscription<HardwareButton>? volumeSubscription;
  bool canPressVolume = true;

  //LUT controls 已迁移为顶部模式行中的二级菜单样式

  //AI Suggestion Service
  final AiSuggestionService _aiService = AiSuggestionService();
  
  // AI建议组件的拖拽位置 (默认位置：右下角，向右+向下偏移)
  double _aiWidgetX = 40.0; // 默认距离左边40px (向右移动)
  double _aiWidgetY = 40.0; // 默认距离底部40px (向下移动)

  //QR Code
  /*final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  qr.Barcode? result;
  qr.QRViewController? qrController;*/

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    /*final methodChannel = AndroidMethodChannel();
    methodChannel.disableIntentCamera(disable: true);*/

    // 固定为横向模式
    _subscribeOrientationChangeStream();

    // 初始化LUT预览管理器
    _initializeLutPreviewManager();

    onNewCameraSelected(cameras[Preferences.getStartWithRearCamera() ? 0 : 1]);
    
    // 加载AI组件的保存位置
    _aiWidgetX = Preferences.getAiWidgetX();
    _aiWidgetY = Preferences.getAiWidgetY();
    
    // 启动AI服务（稍后在相机初始化完成后启动）
    _aiService.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeLutPreviewManager() async {
    try {
      final manager = LutPreviewManager.instance;
      await manager.initializeFromPreferences();
      final enabled = Preferences.getLutEnabled();
      if (!enabled) {
        manager.disableLut();
      } else {
        final savedPath = Preferences.getSelectedLutPath();
        if (savedPath.isNotEmpty) {
          await manager.setCurrentLut(savedPath);
        } else {
          final defaultLutPath = await manager.getDefaultLutPath();
          await manager.setCurrentLut(defaultLutPath);
        }
      }
    } catch (e) {
      debugPrint('初始化LUT预览管理器失败: $e');
    }
  }

  // In order to get hot reload to work we need to pause the camera if the platform
  // is android, or resume the camera if the platform is iOS.
  /*@override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      qrController!.pauseCamera();
    }
  }*/

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // 停止图像流并处理相机控制器
    LutPreviewManager.instance.stopImageStream();
    _aiService.stopService();
    controller?.dispose();
    controller = null;

    //qrController?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final CameraController? cameraController = controller;

    if (state == AppLifecycleState.inactive) {
      // 应用进入非活动：停止图像流并释放控制器
      await LutPreviewManager.instance.stopImageStream();
      try {
        await cameraController?.dispose();
      } catch (_) {}
      controller = null;
      return;
    }

    if (state == AppLifecycleState.resumed) {
      // 返回前台：如果控制器为空，按当前摄像头偏好重新初始化；否则恢复图像流
      if (controller == null) {
        final CameraDescription desc = cameras[isRearCameraSelected ? 0 : 1];
        await _initializeCameraController(desc);
      } else if (!(controller!.value.isInitialized)) {
        final CameraDescription desc = cameras[isRearCameraSelected ? 0 : 1];
        await _initializeCameraController(desc);
      } else {
        await LutPreviewManager.instance.resumeImageStream();
      }
      return;
    }
  }

  void _subscribeVolumeButtons() {
    volumeSubscription =
        FlutterAndroidVolumeKeydown.stream.listen((event) async {
      if (canPressVolume) {
        onTakePictureButtonPressed();
        canPressVolume = false;
        await Future.delayed(const Duration(seconds: 1));
        canPressVolume = true;
      }
    });
  }

  void _stopVolumeButtons() => volumeSubscription?.cancel();

  void _startVolumeButtons() => checkVolumeButtons();
  
  void checkVolumeButtons() => Preferences.getCaptureAtVolumePress()
      ? _subscribeVolumeButtons()
      : _stopVolumeButtons();

  /*void _onQRViewCreated(qr.QRViewController qrController) {
    this.qrController = qrController;
    qrController.pauseCamera();
    qrController.resumeCamera();

    qrController.scannedDataStream.listen((scanData) {
      setState(() {
        result = scanData;
      });
    });
  }*/

  void _subscribeOrientationChangeStream() {
    // 固定为横向模式，不再根据设备方向变化
    Future.delayed(const Duration(milliseconds: 100), () async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _cameraPreview(context),
    );
  }

  Widget _cameraPreview(context) {
    return Container(
      color: Colors.black,
      child: Row(
        children: [
          // 左侧控制栏
          _leftControlBar(),
          
          // 中央相机预览区域
          Expanded(
            child: Stack(
              children: [
                // 全屏相机预览
                Positioned.fill(child: _previewWidget()),
                
                // 拍照时的白边效果
                _shutterBorder(),
                
                // 计时器显示（居中）
                _timerWidget(),
                
                // 对焦圈
                _circleWidget(),
                
                // 顶部模式切换（如果启用）
                if (Preferences.getEnableModeRow())
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildModeSelector(),
                    ),
                  ),
                
                // 底部曝光滑块（如果启用）
                if (Preferences.getEnableExposureSlider())
                  Positioned(
                    bottom: 16,
                    left: 32,
                    right: 32,
                    child: ExposureSlider(
                      setExposureOffset: _setExposureOffset,
                      currentExposureOffset: _currentExposureOffset,
                      minAvailableExposureOffset: _minAvailableExposureOffset,
                      maxAvailableExposureOffset: _maxAvailableExposureOffset,
                    ),
                  ),
                
                // AI建议组件（如果启用）
                if (Preferences.getAiSuggestionEnabled()) _aiSuggestionWidget(),
              ],
            ),
          ),
          
          // 右侧控制栏
          _rightControlBar(),
        ],
      ),
    );
  }

  Widget _shutterBorder() {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: Border.all(
              color: takingPicture
                  ? const Color(0xFFFFFFFF)
                  : const Color.fromARGB(0, 255, 255, 255),
              width: 4.0,
              style: BorderStyle.solid), //Border.all
        ),
      ),
    );
  }

  Widget _timerWidget() {
    var minuteAmount =
        (Preferences.getTimerDuration() - _timerStopwatch.elapsed.inSeconds) /
            60;
    var minute = minuteAmount.floor();

    return Duration(seconds: Preferences.getTimerDuration()).inSeconds > 0 &&
            _timerStopwatch.elapsedTicks > 1
        ? Center(
            child: IgnorePointer(
              child: Text(
                Preferences.getTimerDuration() -
                            _timerStopwatch.elapsed.inSeconds <
                        60
                    ? '${Preferences.getTimerDuration() - _timerStopwatch.elapsed.inSeconds}s'
                    : '${minute}m ${(Preferences.getTimerDuration() - _timerStopwatch.elapsed.inSeconds) % 60}s',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 64.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        : Container();
  }

  Widget _previewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController != null && cameraController.value.isInitialized) {
      // 获取屏幕详细信息
      final size = MediaQuery.sizeOf(context);                    // 逻辑分辨率：dp
      final dpr = MediaQuery.devicePixelRatioOf(context);         // 设备像素比
      final px = Size(size.width * dpr, size.height * dpr);       // 物理分辨率：px
      final ar = size.aspectRatio;                                // 宽高比
      final pads = MediaQuery.viewPaddingOf(context);            // 刘海/系统条安全区

      // 计算可用空间（扣除安全区域）
      final availableWidth = size.width;
      final availableHeight = size.height - pads.top - pads.bottom;
      
      debugPrint('[Camera] Logical size: ${size.width}x${size.height} dp');
      debugPrint('[Camera] Physical size: ${px.width}x${px.height} px (DPR: $dpr)');
      debugPrint('[Camera] Aspect ratio: $ar');
      debugPrint('[Camera] Safe area padding: top=${pads.top}, bottom=${pads.bottom}');
      debugPrint('[Camera] Available space: ${availableWidth}x$availableHeight dp');
      
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: AnimatedBuilder(
          // Rebuild preview when LUT state changes
          animation: LutPreviewManager.instance,
          builder: (context, _) {
            return LutPreviewManager.instance.createPreviewWidget(
              cameraController,
              isRearCamera: isRearCameraSelected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onTapDown: (TapDownDetails details) =>
                    _onViewFinderTap(details, BoxConstraints(
                      maxWidth: availableWidth,
                      maxHeight: availableHeight,
                    )),
              ),
            );
          },
        ),
      );
    } else {
      return const Center(child: CircularProgressIndicator());
    }
  }

  // 左侧控制栏（横屏模式）- 空白区域
  Widget _leftControlBar() {
    return const SizedBox(width: 0);
  }

  // 右侧控制栏（横屏模式）- 设置、快门键、闪光灯、缩放滑杆
  Widget _rightControlBar() {
    return Container(
      width: 80,
      color: Colors.black.withValues(alpha: 0.3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 设置按钮（顶部）
          _buildVerticalControlButton(
            icon: Icons.settings_outlined,
            onTap: _timerStopwatch.elapsedTicks <= 1 
              ? () => _navigateToSettings() 
              : null,
          ),
          
          // 相册/缩略图按钮（替代缺失的 GalleryWidget）
          SizedBox(
            width: 56,
            height: 56,
            child: _buildThumbnailWidget(),
          ),
          
          // 拍照按钮（中间）
          _buildMainShutterButton(),
          
          // 闪光灯按钮
          FlashModeWidget(
            controller: controller,
            isRearCameraSelected: isRearCameraSelected,
            isVideoCameraSelected: false,
          ),
          
          // 缩放滑块（底部）- 水平显示
          if (Preferences.getEnableZoomSlider())
            SizedBox(
              height: 80,
              child: _zoomSlider(update: false),
            ),
        ],
      ),
    );
  }

  Widget _buildVerticalControlButton({
    required IconData icon,
    VoidCallback? onTap,
    bool isActive = false,
  }) {
    return Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isActive 
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Icon(
            icon,
            color: onTap != null ? Colors.white : Colors.white54,
            size: 24,
          ),
        ),
      ),
    );
  }

  // 垂直的LUT控制组件 - 减小高度适应分布式布局
  // Removed unused: _buildVerticalLutControl()

  void _navigateToSettings() {
    _stopVolumeButtons();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          controller: controller,
          onNewCameraSelected: _initializeCameraController,
        ),
      ),
    ).then((_) => _startVolumeButtons());
  }

  Widget _buildModeSelector() {
    return FractionalTranslation(
      // 先居中后，基于自身宽度向右平移 20%
      translation: const Offset(0.3, 0.0),
      child: Transform.scale(
        scale: 0.6, // 略微放大（相对原始的 60%）
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExposureModeControlWidget(controller: controller),
              const SizedBox(width: 16),
              FocusModeControlWidget(controller: controller),
              const SizedBox(width: 16),
              const LutControlWidget(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailWidget() {
    return _timerStopwatch.elapsedTicks > 1
        ? Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
          )
        : Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: capturedFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
                          AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
                          int sdkInt = androidInfo.version.sdkInt;

                          const String mimeType = 'image/jpeg';
                          final methodChannel = AndroidMethodChannel();
                          await methodChannel.openItem(
                            file: capturedFile!,
                            mimeType: mimeType,
                            openInGallery: sdkInt > 27 ? false : true,
                          );
                        },
                        child: _thumbnailWidget(),
                      ),
                    ),
                  )
                : Icon(
                    Icons.photo_library_outlined,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 24,
                  ),
          );
  }

  Widget _buildMainShutterButton() {
    return GestureDetector(
      onTap: onTakePictureButtonPressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: Colors.white,
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
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: takingPicture ? Colors.red : Colors.white,
            border: Border.all(
              color: Colors.grey.shade300,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  // Removed unused: _buildCameraSwitchButton()

  // Removed unused: _topControlsWidget()

  // Removed unused: _zoomWidget()

  Widget _settingsWidget({required bool enabled}) {
    return AnimatedRotation(
      duration: const Duration(milliseconds: 400),
      turns: 0.25,
      child: SettingsButton(
        onPressed: enabled
            ? () {
                _stopVolumeButtons();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(
                      controller: controller,
                      onNewCameraSelected: _initializeCameraController,
                    ),
                  ),
                );
              }
            : null,
        controller: controller,
      ),
    );
  }

  // 已移除：_lutSelectorWidget（后续重构）

  Widget _thumbnailPreviewWidget() {
    return _timerStopwatch.elapsedTicks > 1
        ? const SizedBox(height: 60, width: 60)
        : AnimatedRotation(
            duration: const Duration(milliseconds: 400),
            turns: 0.25,
            child: Tooltip(
              message: AppLocalizations.of(context)!.openCapturedPictureOrVideo,
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: GestureDetector(
                    onTap: () async {
                      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
                      AndroidDeviceInfo androidInfo =
                          await deviceInfo.androidInfo;
                      int sdkInt = androidInfo.version.sdkInt;

                      const String mimeType = 'image/jpeg';

                      final methodChannel = AndroidMethodChannel();
                      await methodChannel.openItem(
                        file: capturedFile!,
                        mimeType: mimeType,
                        openInGallery: sdkInt > 27 ? false : true,
                      );
                    },
                    child: _thumbnailWidget(),
                  ),
                ),
              ),
            ),
          );
  }

  // Removed unused: _bottomControlsWidget()

  Widget _cameraModesWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        ExposureModeControlWidget(controller: controller),
        FocusModeControlWidget(controller: controller),
        const LutControlWidget(),
      ],
    );
  }

  //Selecting camera
  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    // 始终通过重新初始化控制器来切换摄像头（相机插件不提供 setDescription）
    await _initializeCameraController(cameraDescription);
  }

  Future<void> _initializeCameraController(
      CameraDescription cameraDescription) async {
    // 停止当前的图像流以避免冲突
    await LutPreviewManager.instance.stopImageStream();
    
    // 如果存在旧的控制器，先清理它
    if (controller != null) {
      try {
        await controller!.dispose();
      } catch (e) {
        debugPrint('清理旧控制器时出错: $e');
      }
      controller = null;
    }
    
    final flashMode = getFlashMode();
    final resolution = getResolution();

    final CameraController cameraController = CameraController(
      cameraDescription,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // 改为YUV420以支持LUT预览
    );

    controller = cameraController;

    try {
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        cameraController.setFlashMode(flashMode),
        cameraController
            .getMinExposureOffset()
            .then((double value) => _minAvailableExposureOffset = value),
        cameraController
            .getMaxExposureOffset()
            .then((double value) => _maxAvailableExposureOffset = value),
        cameraController
            .getMaxZoomLevel()
            .then((double value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          debugPrint('You have denied camera access.');
          break;
        case 'AudioAccessDenied':
          debugPrint('You have denied audio access.');
          break;
        default:
          debugPrint('$e: ${e.description}');
          break;
      }
      
      // 即使初始化失败也要尝试恢复图像流
      LutPreviewManager.instance.resumeImageStream();
      return; // 提前返回，避免重复调用resumeImageStream
    } catch (e) {
      debugPrint('初始化相机控制器时发生未知错误: $e');
      // 即使发生未知错误也要尝试恢复图像流
      LutPreviewManager.instance.resumeImageStream();
      return; // 提前返回，避免重复调用resumeImageStream
    }

    if (mounted) {
      await _refreshGalleryImages();

      setState(() {});
      
      // 延迟重新启动图像流，确保相机完全初始化
      Future.delayed(const Duration(milliseconds: 300), () {
        LutPreviewManager.instance.resumeImageStream();
        // 在相机完全初始化后启动AI服务
        _aiService.startService(controller);
      });
    }

    checkVolumeButtons();

    /*startCameraProcessing();

    cameraController.startImageStream((image) async {
      CodeResult result = await processCameraImage(image);
      if (result.isValidBool) {
        debugPrint('QR: ${result.textString}');
      }
      return null;
    });*/
  }

  bool getIsRearCameraSelected() {
    return isRearCameraSelected;
  }

  void setIsRearCameraSelected() {
    setState(() => isRearCameraSelected = !isRearCameraSelected);
  }

  //Camera button functions
  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) {
      if (mounted) {
        setState(() {});
      }
    }).catchError((error) {
      debugPrint('拍照过程中发生错误: $error');
      // 确保即使出错也恢复图像流
      LutPreviewManager.instance.resumeImageStream();
      if (mounted) {
        setState(() {});
      }
    });
  }

  //Camera controls
  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      debugPrint('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already going on, return
      return null;
    }

    // 立即给予拍照反馈，减少感知延迟
    if (mounted) {
      setState(() {
        takingPicture = true;
      });
    }

    // 尝试临时锁定对焦/曝光，避免拍照前的再对焦/测光引起延迟
    final prevFocusMode = cameraController.value.focusMode;
    final prevExposureMode = cameraController.value.exposureMode;
    try {
      if (prevFocusMode == FocusMode.auto) {
        await cameraController.setFocusMode(FocusMode.locked);
      }
      if (prevExposureMode == ExposureMode.auto) {
        await cameraController.setExposureMode(ExposureMode.locked);
      }
    } catch (e) {
      debugPrint('[Capture] 临时锁定对焦/曝光失败: $e');
    }

    // 停止图像流以避免冲突，并记录耗时以排查延迟
    final Stopwatch sw = Stopwatch()..start();
    await LutPreviewManager.instance.stopImageStream();
    sw.stop();
    debugPrint('[Capture] stopImageStream took: ${sw.elapsedMilliseconds} ms');

    final int delaySec = Preferences.getTimerDuration();
    if (delaySec > 0) {
      setState(() {
        Timer.periodic(
          const Duration(milliseconds: 500),
          (Timer t) => setState(() {}),
        );
        _timerStopwatch.start();
      });
      await Future.delayed(Duration(seconds: delaySec));
      setState(() {
        _timerStopwatch.stop();
        _timerStopwatch.reset();
      });
    }

    try {
      final t0 = DateTime.now();
      // 如无倒计时，提前播放快门声以提升感知速度
      bool playedShutter = false;
      if (delaySec == 0 && !Preferences.getDisableShutterSound()) {
        var methodChannel = AndroidMethodChannel();
        methodChannel.shutterSound();
        playedShutter = true;
      }

      final XFile file = await cameraController.takePicture();
      final t1 = DateTime.now();
      debugPrint('[Capture] takePicture() took: ${t1.difference(t0).inMilliseconds} ms');
      if (!Preferences.getDisableShutterSound() && !playedShutter) {
        var methodChannel = AndroidMethodChannel();
        methodChannel.shutterSound();
      }

      capturedFile = File(file.path);

      final directory = Preferences.getSavePath();

      //String fileFormat = capturedFile!.path.split('.').last;
      const CompressFormat format = CompressFormat.jpeg;
      const String fileFormat = 'jpg';

      String path = '$directory/IMG_${timestamp()}.$fileFormat';

      if (!isRearCameraSelected && Preferences.getFlipFrontCameraPhoto()) {
        final imageBytes = await capturedFile!.readAsBytes();
        img.Image? originalImage = img.decodeImage(imageBytes);
        img.Image fixedImage = img.flipHorizontal(originalImage!);

        await capturedFile!.writeAsBytes(
          img.encodeJpg(fixedImage),
          flush: true,
        );
      }

      /*final resolutionString = Preferences.getResolution();
      ResolutionPreset resolution = ResolutionPreset.high;
      for (var res in ResolutionPreset.values) {
        if (res.name == resolutionString) resolution = res;
      }*/

      Uint8List? newFileBytes;
      try {
        final manager = LutPreviewManager.instance;
        if (manager.isEnabled && manager.mixStrength > 0.0 && manager.currentLutPath != null) {
          // 读取当前文件并应用 LUT（优先 GPU 全分辨率渲染，失败则回退到软件）
          final srcBytes = await capturedFile!.readAsBytes();
          try {
            final gpuOut = await GpuLutStillRenderer.processJpegWithLut(
              jpegBytes: srcBytes,
              lutPath: manager.currentLutPath!,
              mixStrength: manager.mixStrength,
              jpegQuality: Preferences.getCompressQuality(),
            );
            newFileBytes = Preferences.getKeepEXIFMetadata()
                ? _injectJpegExif(gpuOut, srcBytes)
                : gpuOut;
          } catch (_) {
            newFileBytes = await _applyLutToImageBytes(
              srcBytes: srcBytes,
              lutPath: manager.currentLutPath!,
              mixStrength: manager.mixStrength,
              format: format,
              quality: Preferences.getCompressQuality(),
            );
          }
        } else {
          // 未启用 LUT，按原路径压缩保存
          newFileBytes = await FlutterImageCompress.compressWithFile(
            capturedFile!.path,
            quality: Preferences.getCompressQuality(),
            keepExif: Preferences.getKeepEXIFMetadata(),
            format: format,
          );
        }
      } catch (e) {
        // 回退到原有压缩路径
        newFileBytes = await FlutterImageCompress.compressWithFile(
          capturedFile!.path,
          quality: Preferences.getCompressQuality(),
          keepExif: Preferences.getKeepEXIFMetadata(),
          format: format,
        );
      }

      //var tempFile = capturedFile!.copySync('$directory/IMG_${timestamp()}.$fileFormat');
      try {
        final outFile = File(path);
        await outFile.writeAsBytes(newFileBytes!, flush: true);

        final methodChannel = AndroidMethodChannel();
        await methodChannel.updateItem(file: outFile);
        capturedFile = outFile;
      } catch (e) {
        if (mounted) showSnackbar(text: e.toString());
      }

      /*Uint8List? newFileBytes = await FlutterImageCompress.compressWithFile(
          capturedFile!.path,
          quality: Preferences.getCompressQuality(),
          keepExif: Preferences.getKeepEXIFMetadata());
      File? newFile = await File(path).create();
      newFile.writeAsBytesSync(newFileBytes!);*/

      /*Directory? finalPath = await getExternalStorageDirectory();
      await FlutterImageCompress.compressAndGetFile(
          capturedFile!.path, finalPath!.path,
          quality: Preferences.getCompressQuality(),
          keepExif: Preferences.getKeepEXIFMetadata());*/

      //OLD without compression and removal of EXIF data: await capturedFile!.copy(path);

      debugPrint('Picture saved to $path');

      takingPicture = false;

      await _refreshGalleryImages();

      await File(file.path).delete();

      // 恢复图像流（等待相机会话稳定后再恢复）
      await Future.delayed(const Duration(milliseconds: 80));
      await LutPreviewManager.instance.resumeImageStream();
      // 恢复对焦/曝光模式
      await _restoreAeAfModes(cameraController, prevFocusMode, prevExposureMode);

      return file;
    } on CameraException catch (e) {
      debugPrint('$e: ${e.description}');
      // 即使发生错误也要恢复图像流
      await LutPreviewManager.instance.resumeImageStream();
      // 恢复对焦/曝光模式
      _restoreAeAfModes(cameraController, prevFocusMode, prevExposureMode);
      if (mounted) {
        setState(() {
          takingPicture = false;
        });
      } else {
        takingPicture = false;
      }
      return null;
    } catch (e) {
      debugPrint('拍照时发生未知错误: $e');
      // 即使发生错误也要恢复图像流
      await LutPreviewManager.instance.resumeImageStream();
      // 恢复对焦/曝光模式
      _restoreAeAfModes(cameraController, prevFocusMode, prevExposureMode);
      if (mounted) {
        setState(() {
          takingPicture = false;
        });
      } else {
        takingPicture = false;
      }
      return null;
    }
  }

  Future<void> _restoreAeAfModes(CameraController cameraController, FocusMode prevFocusMode, ExposureMode prevExposureMode) async {
    try {
      if (cameraController.value.focusMode != prevFocusMode) {
        await cameraController.setFocusMode(prevFocusMode);
      }
      if (cameraController.value.exposureMode != prevExposureMode) {
        await cameraController.setExposureMode(prevExposureMode);
      }
    } catch (e) {
      debugPrint('[Capture] 恢复对焦/曝光模式失败: $e');
    }
  }

  /// 将 LUT 应用于整张图片字节，并按目标格式编码
  Future<Uint8List> _applyLutToImageBytes({
    required Uint8List srcBytes,
    required String lutPath,
    required double mixStrength,
    required CompressFormat format,
    required int quality,
  }) async {
    // 解码图片
    final img.Image? decoded = img.decodeImage(srcBytes);
    if (decoded == null) return srcBytes;

    // 修正方向：将 EXIF Orientation 烘焙到像素，避免竖图被逆时针旋转90°
    final img.Image oriented = img.bakeOrientation(decoded);

    final int w = oriented.width;
    final int h = oriented.height;
    // 获取 RGBA 像素
    final Uint8List rgba = Uint8List.fromList(
      oriented.getBytes(order: img.ChannelOrder.rgba),
    );

    // 载入 LUT
    ByteData lutData;
    if (lutPath.startsWith('assets/')) {
      lutData = await rootBundle.load(lutPath);
    } else {
      final bytes = await File(lutPath).readAsBytes();
      lutData = ByteData.sublistView(bytes);
    }
    final lut = await loadCubeLut(lutData);
    final processor = SoftwareLutProcessor(lut);

    // 应用 LUT
    final Uint8List mixed = processor.processImageData(rgba, w, h, mixStrength);
    // 重建图像
    final img.Image processed = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: mixed.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    // 按目标格式编码
    Uint8List out;
    switch (format) {
      case CompressFormat.jpeg:
        out = Uint8List.fromList(img.encodeJpg(processed, quality: quality));
        break;
      case CompressFormat.png:
        out = Uint8List.fromList(img.encodePng(processed));
        break;
      case CompressFormat.webp:
        // Fallback: encode as PNG when WebP encoder is unavailable
        out = Uint8List.fromList(img.encodePng(processed));
        break;
      default:
        out = Uint8List.fromList(img.encodeJpg(processed, quality: quality));
        break;
    }
    // 可选：迁移 EXIF 到 JPEG
    if (format == CompressFormat.jpeg && Preferences.getKeepEXIFMetadata()) {
      try {
        out = _injectJpegExif(out, srcBytes);
      } catch (_) {}
    }
    return out;
  }

  /// 从原始 JPEG 中提取 EXIF (APP1) 段并注入到新 JPEG（若存在）
  Uint8List _injectJpegExif(Uint8List newJpeg, Uint8List originalBytes) {
    // 检查 SOI
    if (newJpeg.length < 4 || originalBytes.length < 4) return newJpeg;
    if (!(newJpeg[0] == 0xFF && newJpeg[1] == 0xD8)) return newJpeg;
    if (!(originalBytes[0] == 0xFF && originalBytes[1] == 0xD8)) return newJpeg;

    // 在原图中寻找 APP1 Exif 段
    int i = 2;
    while (i + 4 < originalBytes.length) {
      if (originalBytes[i] != 0xFF) { i++; continue; }
      // 跳过填充 FF
      while (i < originalBytes.length && originalBytes[i] == 0xFF) { i++; }
      if (i >= originalBytes.length) break;
      final marker = originalBytes[i++];
      if (marker == 0xD9 || marker == 0xDA) {
        break; // EOI or SOS
      }
      if (i + 1 >= originalBytes.length) break;
      final len = (originalBytes[i] << 8) | originalBytes[i + 1];
      final segStart = i - 2; // points to the 0xFF marker byte
      final dataStart = i + 2; // start of APP1 payload (after 2-byte length)
      final segEnd = i + len; // total segment = marker(2) + len bytes
      if (segEnd > originalBytes.length) break;

      // APP1 Exif
      if (marker == 0xE1 && len >= 6) {
        // Check Exif header
        if (originalBytes[dataStart] == 0x45 && // 'E'
            originalBytes[dataStart + 1] == 0x78 && // 'x'
            originalBytes[dataStart + 2] == 0x69 && // 'i'
            originalBytes[dataStart + 3] == 0x66 && // 'f'
            originalBytes[dataStart + 4] == 0x00 &&
            originalBytes[dataStart + 5] == 0x00) {
          // Copy APP1 (Exif) segment and将 Orientation 标记规范化为 1（已将像素烘焙到正确方向）
          final exifSeg = Uint8List.fromList(originalBytes.sublist(segStart, segEnd));
          try {
            _sanitizeExifOrientationInApp1(exifSeg);
          } catch (_) {}
          // 将 EXIF 插入新 JPEG 的 SOI 之后
          final out = BytesBuilder();
          out.add([0xFF, 0xD8]);
          out.add(exifSeg);
          // 剩余新图从索引2开始加入
          out.add(newJpeg.sublist(2));
          return out.toBytes();
        }
      }
      i = segEnd;
    }
    return newJpeg;
  }

  // 将 APP1(Exif) 段中的 Orientation(0x0112) 设置为 1（Top-left），避免像素已烘焙后再次被旋转
  // exifApp1: 完整 APP1 段，从 0xFF 0xE1 开始，长度包含在偏移 2..3 两字节（大端）
  void _sanitizeExifOrientationInApp1(Uint8List exifApp1) {
    if (exifApp1.length < 12) return;
    // 验证 0xFFE1
    if (!(exifApp1[0] == 0xFF && exifApp1[1] == 0xE1)) return;
    final len = (exifApp1[2] << 8) | exifApp1[3];
    if (len + 2 > exifApp1.length) return; // 2字节 marker 不计入 len
    // 验证 Exif\0\0
    const exifHeaderStart = 4;
    if (exifApp1.length < exifHeaderStart + 6) return;
    if (!(exifApp1[exifHeaderStart] == 0x45 && // E
        exifApp1[exifHeaderStart + 1] == 0x78 && // x
        exifApp1[exifHeaderStart + 2] == 0x69 && // i
        exifApp1[exifHeaderStart + 3] == 0x66 && // f
        exifApp1[exifHeaderStart + 4] == 0x00 &&
        exifApp1[exifHeaderStart + 5] == 0x00)) {
      return;
    }

    const tiffStart = exifHeaderStart + 6;
    if (exifApp1.length < tiffStart + 8) return;
    final littleEndian =
        (exifApp1[tiffStart] == 0x49 && exifApp1[tiffStart + 1] == 0x49);
    // 验证 0x002A
    int readU16(int off) => littleEndian
        ? (exifApp1[off] | (exifApp1[off + 1] << 8))
        : ((exifApp1[off] << 8) | exifApp1[off + 1]);
    int readU32(int off) => littleEndian
        ? (exifApp1[off] |
            (exifApp1[off + 1] << 8) |
            (exifApp1[off + 2] << 16) |
            (exifApp1[off + 3] << 24))
        : ((exifApp1[off] << 24) |
            (exifApp1[off + 1] << 16) |
            (exifApp1[off + 2] << 8) |
            exifApp1[off + 3]);
    void writeU16(int off, int v) {
      if (littleEndian) {
        exifApp1[off] = (v & 0xFF);
        exifApp1[off + 1] = ((v >> 8) & 0xFF);
      } else {
        exifApp1[off] = ((v >> 8) & 0xFF);
        exifApp1[off + 1] = (v & 0xFF);
      }
    }

    final magic = readU16(tiffStart + 2);
    if (magic != 0x002A) return;
    final ifd0Offset = readU32(tiffStart + 4);
    final ifd0Start = tiffStart + ifd0Offset;
    if (ifd0Start + 2 > exifApp1.length) return;
    final entryCount = readU16(ifd0Start);
    int entryBase = ifd0Start + 2;
    const tagOrientation = 0x0112;
    for (int i = 0; i < entryCount; i++) {
      final e = entryBase + i * 12;
      if (e + 12 > exifApp1.length) break;
      final tag = readU16(e);
      if (tag == tagOrientation) {
        final type = readU16(e + 2); // SHORT=3
        final count = readU32(e + 4);
        if (type == 3 && count >= 1) {
          // 值就在 valueOffset 4 字节中（2 字节有效）
          final valueOff = e + 8;
          writeU16(valueOff, 1); // set to 1 (Top-left)
        }
        break;
      }
    }
  }

  //Zoom
  Widget _zoomSlider({required bool update}) {
    if (mounted && update) {
      setState(() {});
    }

    if (_currentScale > _maxAvailableZoom) {
      _currentScale = _maxAvailableZoom;
    }

    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderThemeData(
          showValueIndicator: ShowValueIndicator.onDrag,
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          value: _currentScale,
          min: _minAvailableZoom,
          max: _maxAvailableZoom,
          label: _currentScale.toStringAsFixed(2),
          onChanged: ((value) async {
            setState(() {
              _currentScale = value;
            });
            await controller!.setZoomLevel(value);
          }),
        ),
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  void _onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    _circlePosX = details.localPosition.dx;
    _circlePosY = details.localPosition.dy;

    _displayCircle();

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  void _displayCircle() async {
    setState(() {
      _circleEnabled = true;
    });
    await Future.delayed(const Duration(milliseconds: 600));
    setState(() {
      _circleEnabled = false;
    });
  }

  Widget _circleWidget() {
    return Positioned(
      top: _circlePosY - 20.0,
      left: _circlePosX - 20.0,
      child: _circleEnabled
          ? TweenAnimationBuilder(
              tween: _scaleTween,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(
                  Icons.circle,
                  color: Colors.transparent,
                  size: 42.0,
                ),
              ),
            )
          : Container(),
    );
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (controller == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    _zoomSlider(update: true);

    await controller!.setZoomLevel(_currentScale);
  }

  //Exposure
  Future<void> _setExposureOffset(double offset) async {
    if (controller == null) {
      return;
    }

    setState(() {
      _currentExposureOffset = offset;
    });
    try {
      offset = await controller!.setExposureOffset(offset);
    } on CameraException catch (e) {
      debugPrint('$e: ${e.description}');
      rethrow;
    }
  }

  //Thumbnail
  Widget _thumbnailWidget() {
    if (capturedFile == null) {
      return const Center(child: null);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7.0),
        image: DecorationImage(
          fit: BoxFit.cover,
          image: FileImage(
            File(capturedFile!.path),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshGalleryImages() async {
    List<File> allFileList = [];

    final directory = Directory(Preferences.getSavePath());

    List<FileSystemEntity> fileList = [];
    try {
      fileList = await directory.list().toList();
    } catch (e) {
      showSnackbar(text: e.toString());
      return;
    }

    List<String> fileNames = [];
    List<DateTime> dateTimes = [];

    String recentFileName = '';

    for (var file in fileList) {
      if (file.path.contains('.jpg') ||
          file.path.contains('.png') ||
          file.path.contains('.webp')) {
        allFileList.add(File(file.path));
        String name = file.path.split('/').last; //.split('.').first;
        final stat = FileStat.statSync(file.path);

        dateTimes.add(stat.modified);

        fileNames.add(name);
      }
    }

    if (fileNames.isNotEmpty) {
      for (var name in fileNames) {
        final now = DateTime.now();
        final mostRecentDateTimeToNow = dateTimes.reduce((a, b) =>
            a.difference(now).abs() < b.difference(now).abs() ? a : b);

        final file = File('${directory.path}/$name');

        final stat = FileStat.statSync(file.path);
        if (stat.changed.isAtSameMomentAs(mostRecentDateTimeToNow)) {
          recentFileName = name;
        }
      }

      capturedFile = File('${directory.path}/$recentFileName');
    }
  }

  //Misc
  String timestamp() {
    final DateTime now = DateTime.now();
    final DateFormat formatter = DateFormat('yyyyMMdd_HHmmss');
    final String formatted = formatter.format(now);
    return formatted;
  }

  Widget _aiSuggestionWidget() {
    return Positioned(
      left: _aiWidgetX,
      bottom: _aiWidgetY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            // 获取屏幕尺寸
            final screenSize = MediaQuery.of(context).size;
            const componentWidth = 220.0;
            const componentHeight = 160.0; // 增加高度以容纳更多内容
            
            // 更新位置，确保不会超出屏幕边界
            _aiWidgetX = (_aiWidgetX + details.delta.dx).clamp(
              0.0, 
              screenSize.width - componentWidth,
            );
            _aiWidgetY = (_aiWidgetY - details.delta.dy).clamp(
              0.0, 
              screenSize.height - componentHeight - 100, // 预留底部空间
            );
          });
        },
        onPanEnd: (details) {
          // 拖拽结束时保存位置到本地存储
          Preferences.setAiWidgetX(_aiWidgetX);
          Preferences.setAiWidgetY(_aiWidgetY);
        },
        child: AnimatedBuilder(
          animation: _aiService,
          builder: (context, child) {
            final isReadyToShoot = _aiService.readyToShoot == 1;
            final borderColor = isReadyToShoot 
              ? Colors.green.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.2);
            final backgroundColor = isReadyToShoot
              ? Colors.black.withValues(alpha: 0.8)
              : Colors.black.withValues(alpha: 0.7);
            
            return Container(
              width: 220,
              height: 160, // 增加高度以容纳更多内容
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12), // 圆角
                border: Border.all(
                  color: borderColor,
                  width: isReadyToShoot ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isReadyToShoot 
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.3),
                    blurRadius: isReadyToShoot ? 12 : 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isReadyToShoot ? Icons.check_circle : Icons.auto_awesome,
                          color: isReadyToShoot 
                            ? Colors.green.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.9),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isReadyToShoot ? '准备拍摄' : 'AI 建议',
                          style: TextStyle(
                            color: isReadyToShoot 
                              ? Colors.green.withValues(alpha: 0.9)
                              : Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_aiService.isUploading)
                          const Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white60),
                              ),
                            ),
                          ),
                        const Spacer(),
                        // 添加拖拽指示图标
                        Icon(
                          Icons.drag_indicator,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: isReadyToShoot 
                        ? const Center(
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 32,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // LUT建议（只在有内容时显示）
                              if (_aiService.currentLutSuggestion.isNotEmpty) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.palette,
                                      color: Colors.blue.withValues(alpha: 0.8),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _aiService.currentLutSuggestion,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.8),
                                              fontSize: 12, // 从10调大到12
                                              height: 1.2,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          // 如果有LUT推荐值，显示应用按钮
                                          if (_aiService.currentLutValue != null && 
                                              _aiService.currentLutValue!.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2.0),
                                              child: GestureDetector(
                                                onTap: () async {
                                                  final success = await _aiService.applyRecommendedLut();
                                                  if (success) {
                                                    showSnackbar(text: 'LUT已应用: ${_aiService.currentLutValue}');
                                                  } else {
                                                    showSnackbar(text: '应用LUT失败');
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6.0,
                                                    vertical: 2.0,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: Colors.blue.withValues(alpha: 0.5),
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '应用',
                                                    style: TextStyle(
                                                      color: Colors.blue.withValues(alpha: 0.9),
                                                      fontSize: 10, // 从8调大到10
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                              ],
                              // 取景建议（只在有内容时显示）
                              if (_aiService.currentFramingSuggestion.isNotEmpty)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.camera_alt,
                                      color: Colors.orange.withValues(alpha: 0.8),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _aiService.currentFramingSuggestion,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.8),
                                          fontSize: 12, // 从10调大到12
                                          height: 1.2,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void showSnackbar({required String text}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 5),
    ));
  }
}

class AndroidMethodChannel {
  static const _channel = MethodChannel('media_store');

  Future<void> updateItem({required File file}) async {
    await _channel.invokeMethod('updateItem', {
      'path': file.path,
    });
  }

  Future<void> openItem({
    required File file,
    required String mimeType,
    required bool openInGallery,
  }) async {
    await _channel.invokeMethod('openItem', {
      'path': file.path,
      'mimeType': mimeType,
      'openInGallery': openInGallery,
    });
  }

  Future<void> disableIntentCamera({required bool disable}) async {
    await _channel.invokeMethod('disableIntentCamera', {
      'disable': disable,
    });
  }

  Future<void> shutterSound() async {
    await _channel.invokeMethod('shutterSound', {});
  }
}
