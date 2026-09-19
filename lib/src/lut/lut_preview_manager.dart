import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'gpu_lut_preview.dart';
import '../utils/preferences.dart';

/// LUT实时预览管理器
class LutPreviewManager extends ChangeNotifier {
  static LutPreviewManager? _instance;
  static LutPreviewManager get instance => _instance ??= LutPreviewManager._();
  
  LutPreviewManager._();

  String? _currentLutPath;
  double _mixStrength = 1.0;
  bool _isEnabled = true;
  
  // 使用函数回调而不是直接引用来避免循环依赖
  Future<void> Function()? _stopStreamCallback;
  Future<void> Function()? _resumeStreamCallback;

  String? get currentLutPath => _currentLutPath;
  double get mixStrength => _mixStrength;
  bool get isEnabled => _isEnabled;
  // 仅保留 GPU 预览实现

  /// 设置当前使用的LUT，并自动启用预览
  Future<void> setCurrentLut(String lutPath) async {
    _currentLutPath = lutPath;
    debugPrint('[LUT] 当前 LUT 路径: $_currentLutPath');
    // 选择了有效 LUT 时确保启用
    setEnabled(true);
  }

  /// 禁用 LUT 预览并恢复为原生相机预览
  void disableLut() {
    _currentLutPath = null;
    debugPrint('[LUT] 禁用 LUT 预览，恢复原生相机预览');
    setEnabled(false);
  }

  /// 设置LUT混合强度
  void setMixStrength(double strength) {
    _mixStrength = strength.clamp(0.0, 1.0);
    // persist
    Preferences.setLutMixStrength(_mixStrength);
    debugPrint('[LUT] 混合强度: $_mixStrength');
    notifyListeners();
  }

  /// 启用/禁用LUT预览
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    // persist
    Preferences.setLutEnabled(_isEnabled);
    debugPrint('[LUT] 预览启用: $_isEnabled');
    notifyListeners();
  }

  // 移除 CPU 预览切换，始终使用 GPU 实现

  /// 获取默认LUT路径（直接使用静态资源）
  Future<String> getDefaultLutPath() async {
    return 'assets/Luts/0_人像，电影感，皮肤质感.cube';
  }

  /// 创建LUT预览Widget
  Widget createPreviewWidget(
    CameraController cameraController, {
    bool isRearCamera = true,
    double? screenWidth,
    double? screenHeight,
    double? physicalWidth,
    double? physicalHeight,
    double? devicePixelRatio,
    Widget? child,
  }) {
    // 学习原生无LUT方案：始终使用 CameraPreview 作为基础
    // LUT 作为透明overlay叠加在相机预览之上，而不是替换整个预览
    
    Widget overlay = const SizedBox.shrink();
    if (_isEnabled && _currentLutPath != null) {
      debugPrint('[LUT] Creating overlay=GPU path=$_currentLutPath strength=$_mixStrength');
      overlay = GpuLutPreview(
        cameraController: cameraController,
        lutPath: _currentLutPath!,
        mixStrength: _mixStrength,
        isRearCamera: isRearCamera,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
        devicePixelRatio: devicePixelRatio,
      );
    }

    // 照搬原生无LUT方案：始终返回 CameraPreview，LUT作为child叠加
    final children = <Widget>[];

    // 添加LUT overlay（如果启用）
    if (_isEnabled && _currentLutPath != null) {
      // 叠加层填充 CameraPreview 区域，匹配其 cover 行为
      children.add(Positioned.fill(child: overlay));
    }

    // 添加用户的child（手势检测等）
    if (child != null) {
      children.add(child);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasLut = _isEnabled && _currentLutPath != null;
        debugPrint(
            '[CameraPreview] Canvas size (${hasLut ? "with LUT" : "no LUT"}): ${constraints.maxWidth}x${constraints.maxHeight}');

        return CameraPreview(
          cameraController,
          // 通过 Stack(center) 且 clipBehavior:none，避免对 LUT 预览进行裁切或缩放
          child: children.isNotEmpty
              ? Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none, // 移除裁切
                  children: children,
                )
              : child,
        );
      },
    );
  }

  /// 注册流控制回调（由预览层调用，可选）
  void registerStreamCallbacks(Future<void> Function() stopCallback, Future<void> Function() resumeCallback) {
    _stopStreamCallback = stopCallback;
    _resumeStreamCallback = resumeCallback;
  }

  /// 取消注册流控制回调
  void unregisterStreamCallbacks() {
    _stopStreamCallback = null;
    _resumeStreamCallback = null;
  }

  /// 从偏好中恢复混合强度与启用状态
  Future<void> initializeFromPreferences() async {
    try {
      _mixStrength = Preferences.getLutMixStrength();
      _isEnabled = Preferences.getLutEnabled();
      notifyListeners();
    } catch (_) {
      // ignore preference errors
    }
  }

  /// 停止图像流（在拍照/录制前调用）
  Future<void> stopImageStream() async {
    try {
      await _stopStreamCallback?.call();
    } catch (e) {
      debugPrint('停止图像流时出错: $e');
    }
  }

  /// 恢复图像流（在拍照/录制后调用）
  Future<void> resumeImageStream() async {
    try {
      await _resumeStreamCallback?.call();
    } catch (e) {
      debugPrint('恢复图像流时出错: $e');
    }
  }

  /// 准备相机控制器以支持YUV420格式
  static Future<CameraController> createLutCompatibleCamera(
    CameraDescription description,
    ResolutionPreset resolution, {
    bool enableAudio = false,
  }) async {
    final controller = CameraController(
      description,
      resolution,
      enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    return controller;
  }
}
