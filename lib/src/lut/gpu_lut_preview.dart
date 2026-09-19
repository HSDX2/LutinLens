import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cube_loader.dart';
import 'lut_preview_manager.dart';

class GpuLutPreview extends StatefulWidget {
  final CameraController cameraController;
  final String lutPath;
  final double mixStrength;
  final Widget? child;
  final bool isRearCamera;
  // Screen size parameters for scaling
  final double? screenWidth;     // 逻辑像素宽度 (dp)
  final double? screenHeight;    // 逻辑像素高度 (dp)
  final double? physicalWidth;   // 物理像素宽度 (px)
  final double? physicalHeight;  // 物理像素高度 (px)
  final double? devicePixelRatio; // 设备像素比
  // Color conversion options
  final GpuYuvMode yuvMode; // BT.709 full by default
  final bool swapUV;        // false by default
  // LUT atlas tiling (for compatibility with glsl-lut style 8x8 atlases)
  final int? lutTilesX;     // default: N (uSize)
  final int? lutTilesY;     // default: 1
  final bool flipLutY;      // default: false
  // LUT cube size (levels per axis). Default: derived from image height (our pack)
  final int? lutSize;       // e.g., 33 for .cube, 64 for glsl-lut PNG

  const GpuLutPreview({
    super.key,
    required this.cameraController,
    required this.lutPath,
    required this.mixStrength,
    this.child,
    this.isRearCamera = true,
    this.screenWidth,
    this.screenHeight,
    this.physicalWidth,
    this.physicalHeight,
    this.devicePixelRatio,
    this.yuvMode = GpuYuvMode.bt709Full,
    this.swapUV = false,
    this.lutTilesX,
    this.lutTilesY,
    this.flipLutY = false,
    this.lutSize,
  });

  @override
  State<GpuLutPreview> createState() => _GpuLutPreviewState();
}

class _GpuLutPreviewState extends State<GpuLutPreview> {
  ui.FragmentProgram? _program;
  // Camera Y and UV planes as textures
  ui.Image? _yImage;   // Y plane packed in R channel
  ui.Image? _uvImage;  // UV plane packed: U in R, V in G
  ui.Image? _lut2D;    // packed 2D LUT
  int _srcW = 0;
  int _srcH = 0;
  int _uvW = 0;
  int _uvH = 0;

  bool _streaming = false;
  bool _isProcessing = false;
  bool _stopRequested = false;
  bool _loading = true;
  // 当前 LUT 名称（调试可用）

  @override
  void initState() {
    super.initState();
    // 注册图像流控制回调，供外部在拍照/切换相机时暂停/恢复
    LutPreviewManager.instance.registerStreamCallbacks(
      () async => await _stopStreamIfNeeded(),
      () async => _startStreamIfNeeded(),
    );
    // 初始化 Shader 与 LUT
    _initialize();
  }

  @override
  void didUpdateWidget(GpuLutPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lutPath != widget.lutPath) {
      _loadLut2D();
    }
    if (oldWidget.mixStrength != widget.mixStrength) {
      if (widget.mixStrength <= 0.0) {
        _stopStreamIfNeeded();
      } else {
        _startStreamIfNeeded();
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    // 取消回调注册
    LutPreviewManager.instance.unregisterStreamCallbacks();
    _stopStreamIfNeeded();
    _yImage?.dispose();
    _uvImage?.dispose();
    _lut2D?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/gpu_lut.frag');
    } catch (e) {
      debugPrint('[GPU] 加载 FragmentProgram 失败: $e');
    }
    await _loadLut2D();
    setState(() => _loading = false);
    _startStreamIfNeeded();
  }

  Future<void> _loadLut2D() async {
    try {
      ByteData lutData;
      if (widget.lutPath.startsWith('assets/')) {
        lutData = await rootBundle.load(widget.lutPath);
      } else {
        final bytes = await File(widget.lutPath).readAsBytes();
        lutData = ByteData.sublistView(bytes);
      }
      if (widget.lutPath.toLowerCase().endsWith('.png')) {
        // Load a pre-baked LUT PNG (e.g., glsl-lut 8x8 atlas 512x512)
        final img = await _pngToUiImage(lutData.buffer.asUint8List());
        _lut2D?.dispose();
        _lut2D = img;
      } else {
        // Load .cube and pack to our default layout
        final cube = await loadCubeLut(lutData);
        final img = await _packCubeTo2DImage(cube);
        _lut2D?.dispose();
        _lut2D = img;
      }
      // 可用于调试显示：widget.lutPath.split('/').last.replaceAll('.cube', '');
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[GPU] 加载 LUT 失败: $e');
    }
  }

  void _startStreamIfNeeded() {
    if (_streaming) return;
    if (!widget.cameraController.value.isInitialized) return;
    if (widget.mixStrength <= 0.0) return;
    try {
      _stopRequested = false; // allow processing frames again
      widget.cameraController.startImageStream((image) async {
        if (_isProcessing) return;
        _isProcessing = true;
        try {
          await _processFrame(image);
        } finally {
          _isProcessing = false;
        }
      });
      _streaming = true;
    } catch (e) {
      debugPrint('[GPU] 启动图像流失败: $e');
    }
  }

  Future<void> _stopStreamIfNeeded() async {
    if (!_streaming) return;
    try {
      _stopRequested = true;
      await widget.cameraController.stopImageStream();
    } catch (_) {}
    _streaming = false;
    // 释放持有的上一帧纹理，避免占用显存
    _yImage?.dispose();
    _uvImage?.dispose();
    _yImage = null;
    _uvImage = null;
    if (mounted) setState(() {}); // 刷新UI，避免使用已释放的图像绘制
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_stopRequested) return;
    final int srcW = image.width;
    final int srcH = image.height;
    final yRgba = _packYPlaneToRgba(image);
    final uvRgba = _packUVPlanesToRgba(image);
    final yImg = await _rgbaToUiImage(yRgba.bytes, yRgba.width, yRgba.height);
    final uvImg = await _rgbaToUiImage(uvRgba.bytes, uvRgba.width, uvRgba.height);
    if (!mounted) {
      yImg.dispose();
      uvImg.dispose();
      return;
    }
    _yImage?.dispose();
    _uvImage?.dispose();
    _yImage = yImg;
    _uvImage = uvImg;
    _srcW = srcW;
    _srcH = srcH;
    _uvW = uvRgba.width;
    _uvH = uvRgba.height;
    setState(() {});
  }

  // Pack Y plane (full resolution) into an RGBA buffer (use R for Y)
  _PackedBytes _packYPlaneToRgba(CameraImage image) {
    final yPlane = image.planes[0];
    final int w = image.width;
    final int h = image.height;
    final int yRowStride = yPlane.bytesPerRow;
    final out = Uint8List(w * h * 4);
    for (int j = 0; j < h; j++) {
      final rowStart = j * yRowStride;
      final outRow = j * w * 4;
      for (int i = 0; i < w; i++) {
        final y = yPlane.bytes[rowStart + i];
        final idx = outRow + i * 4;
        out[idx] = y;       // R = Y
        out[idx + 1] = 0;   // G
        out[idx + 2] = 0;   // B
        out[idx + 3] = 255; // A
      }
    }
    return _PackedBytes(bytes: out, width: w, height: h);
  }

  // Pack U and V planes (half resolution) into RG in an RGBA buffer
  _PackedBytes _packUVPlanesToRgba(CameraImage image) {
    final int w = image.width >> 1;
    final int h = image.height >> 1;
    final out = Uint8List(w * h * 4);

    if (image.planes.length == 2) {
      // NV12: planes[0] = Y, planes[1] = interleaved UV
      final uvPlane = image.planes[1];
      final int rowStride = uvPlane.bytesPerRow;
      final int pixelStride = uvPlane.bytesPerPixel ?? 2; // NV12 typically 2
      for (int j = 0; j < h; j++) {
        final rowStart = j * rowStride;
        final outRow = j * w * 4;
        for (int i = 0; i < w; i++) {
          final idxUV = rowStart + i * pixelStride;
          final u = uvPlane.bytes[idxUV];
          final v = uvPlane.bytes[idxUV + 1];
          final idx = outRow + i * 4;
          out[idx] = u;       // R = U
          out[idx + 1] = v;   // G = V
          out[idx + 2] = 0;   // B
          out[idx + 3] = 255; // A
        }
      }
    } else {
      // 3-plane YUV_420_888: planes[1] = U, planes[2] = V
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final int uRowStride = uPlane.bytesPerRow;
      final int vRowStride = vPlane.bytesPerRow;
      final int uPixStride = uPlane.bytesPerPixel ?? 1;
      final int vPixStride = vPlane.bytesPerPixel ?? uPixStride;
      for (int j = 0; j < h; j++) {
        final uRow = j * uRowStride;
        final vRow = j * vRowStride;
        final outRow = j * w * 4;
        for (int i = 0; i < w; i++) {
          final u = uPlane.bytes[uRow + i * uPixStride];
          final v = vPlane.bytes[vRow + i * vPixStride];
          final idx = outRow + i * 4;
          out[idx] = u;       // R = U
          out[idx + 1] = v;   // G = V
          out[idx + 2] = 0;   // B
          out[idx + 3] = 255; // A
        }
      }
    }

    return _PackedBytes(bytes: out, width: w, height: h);
  }

  Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int w, int h) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      (img) => c.complete(img),
      rowBytes: w * 4,
    );
    return c.future;
  }

  Future<ui.Image> _pngToUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<ui.Image> _packCubeTo2DImage(CubeLut cube) async {
    final N = cube.size;
    final width = N * N;
    final height = N;
    final bytes = Uint8List(width * height * 4);
    final data = cube.data; // Float32List in [0..1]
    // Iterate b, g, r
    for (int b = 0; b < N; b++) {
      for (int g = 0; g < N; g++) {
        for (int r = 0; r < N; r++) {
          final base = ((b * N * N) + (g * N) + r) * 3;
          final rr = (data[base] * 255.0).clamp(0.0, 255.0).toInt();
          final gg = (data[base + 1] * 255.0).clamp(0.0, 255.0).toInt();
          final bb = (data[base + 2] * 255.0).clamp(0.0, 255.0).toInt();
          // x = r + b*N; y = g
          final x = r + b * N;
          final y = g;
          final outIndex = (y * width + x) * 4;
          bytes[outIndex] = rr;
          bytes[outIndex + 1] = gg;
          bytes[outIndex + 2] = bb;
          bytes[outIndex + 3] = 255;
        }
      }
    }
    return _rgbaToUiImage(bytes, width, height);
  }

  double _computeRotation(bool isPortrait) {
    final int sensor = widget.cameraController.description.sensorOrientation;
    if (isPortrait) {
      switch (sensor) {
        case 90:
          return 0.0; // 修正：改为无旋转
        case 270:
          return 1.5707963267948966; // 90° 
        case 180:
          return 3.141592653589793; // 180°
        default:
          return 0.0;
      }
    } else {
      // 横屏模式下，根据传感器方向进行适当的旋转以确保正确显示
      switch (sensor) {
        case 90:
          return 0.0; // 横屏时无需旋转
        case 270:
          return 3.141592653589793; // 180°
        case 180:
          return 1.5707963267948966; // 90°
        default:
          return 0.0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _program == null || _lut2D == null) {
      return const SizedBox.shrink();
    }
    if (_yImage == null || _uvImage == null) {
      // 尚无帧可绘制
      return const SizedBox.shrink();
    }

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final rotationRad = _computeRotation(isPortrait);
    final mirror = !widget.isRearCamera;

    // 照搬原生CameraPreview方案：不强制指定画布尺寸，让父容器（CameraPreview）决定
    // 使用相机源尺寸作为CustomPaint的固有尺寸，但允许父容器进行缩放
    // debugPrint('[GPU] Using camera source resolution as intrinsic size: ${_srcW}x$_srcH px');

    // 构建基础绘制 - 使用相机源尺寸作为固有尺寸
    Widget content = CustomPaint(
      painter: _GpuLutPainter(
        program: _program!,
        yImage: _yImage!,
        uvImage: _uvImage!,
        lutImage: _lut2D!,
        srcW: _srcW,
        srcH: _srcH,
        uvW: _uvW,
        uvH: _uvH,
        mix: widget.mixStrength,
        yuvMode: widget.yuvMode,
        swapUV: widget.swapUV,
        lutTilesX: widget.lutTilesX,
        lutTilesY: widget.lutTilesY,
        flipLutY: widget.flipLutY,
        lutSize: widget.lutSize,
      ),
      isComplex: true,
      willChange: true,
    );

    // 先旋转（使用 RotatedBox 参与布局，避免旋转后出现黑边）
    const double piOver2 = 1.5707963267948966;
    int quarterTurns = 0;
    if ((rotationRad - piOver2).abs() < 1e-3) {
      quarterTurns = 1;
    } else if ((rotationRad + piOver2).abs() < 1e-3) {
      quarterTurns = 3;
    } else if ((rotationRad.abs() - 3.141592653589793).abs() < 1e-3) {
      quarterTurns = 2;
    }
    if (quarterTurns != 0) {
      content = RotatedBox(quarterTurns: quarterTurns, child: content);
    }

    // 再镜像（不影响布局）
    if (mirror) {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: content,
      );
    }

    // 照搬原生CameraPreview方案：让父容器（CameraPreview）决定尺寸、缩放、裁切
    // 使用固定的1920x1080分辨率作为画板尺寸
    Widget overlay = SizedBox(
      width: 1920.0,
      height: 1080.0,
      child: content, // content 内部处理了旋转和镜像
    );

    // 叠加子层（手势等）
    if (widget.child != null) {
      overlay = Stack(
        children: [overlay, widget.child!],
      );
    }

    // 将缩放控制交由外层（CameraPage）处理，这里仅返回本体
    return overlay;
  }
}

class _GpuLutPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ui.Image yImage;
  final ui.Image uvImage;
  final ui.Image lutImage;
  final int srcW;
  final int srcH;
  final int uvW;
  final int uvH;
  final double mix;
  final GpuYuvMode yuvMode;
  final bool swapUV;
  final int? lutTilesX;
  final int? lutTilesY;
  final bool flipLutY;
  final int? lutSize;

  _GpuLutPainter({
    required this.program,
    required this.yImage,
    required this.uvImage,
    required this.lutImage,
    required this.srcW,
    required this.srcH,
    required this.uvW,
    required this.uvH,
    required this.mix,
    required this.yuvMode,
    required this.swapUV,
    required this.lutTilesX,
    required this.lutTilesY,
    required this.flipLutY,
    required this.lutSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final fs = program.fragmentShader();
      // Samplers order: uY (0), uUV (1), uLut2D (2)
      fs.setImageSampler(0, yImage);
      fs.setImageSampler(1, uvImage);
      fs.setImageSampler(2, lutImage);
      // Float uniforms order must match shader declarations exactly:
      // 0:uSize, 1:uMix, 2:uMode, 3:uSwapUV, 4:uLutW, 5:uLutH, 6:uTilesX, 7:uTilesY,
      // 8:uFlipY, 9:uDstW, 10:uDstH, 11:uSrcW, 12:uSrcH, 13:uUvW, 14:uUvH
      final int inferredSize = lutSize ?? lutImage.height; // our pack defaults
      final double lutSizeValue = inferredSize.toDouble();

      // Infer atlas tiling if not provided
      double tilesX;
      double tilesY;
      if (lutTilesX != null && lutTilesY != null) {
        tilesX = lutTilesX!.toDouble();
        tilesY = lutTilesY!.toDouble();
      } else {
        // Common layouts:
        // 1) Our pack: width = N*N, height = N  => tilesX=N, tilesY=1
        // 2) Square atlas: width == height and divisible by N => tilesX=tilesY=width/N
        if (lutImage.width == inferredSize * inferredSize && lutImage.height == inferredSize) {
          tilesX = inferredSize.toDouble();
          tilesY = 1.0;
        } else if (lutImage.width == lutImage.height && (lutImage.width % inferredSize == 0)) {
          final t = (lutImage.width ~/ inferredSize).toDouble();
          tilesX = t;
          tilesY = t;
        } else {
          // Fallback to a conservative default (treat as our pack)
          tilesX = inferredSize.toDouble();
          tilesY = 1.0;
        }
      }

      fs.setFloat(0, lutSizeValue);
      fs.setFloat(1, mix);
      fs.setFloat(2, yuvMode == GpuYuvMode.bt709Full ? 0.0 : 1.0);
      fs.setFloat(3, swapUV ? 1.0 : 0.0);
      fs.setFloat(4, lutImage.width.toDouble());
      fs.setFloat(5, lutImage.height.toDouble());
      fs.setFloat(6, tilesX);
      fs.setFloat(7, tilesY);
      fs.setFloat(8, flipLutY ? 1.0 : 0.0);
      fs.setFloat(9, size.width);
      fs.setFloat(10, size.height);
      fs.setFloat(11, srcW.toDouble());
      fs.setFloat(12, srcH.toDouble());
      fs.setFloat(13, uvW.toDouble());
      fs.setFloat(14, uvH.toDouble());
      final paint = Paint()..shader = fs;
      canvas.drawRect(Offset.zero & size, paint);
    } catch (_) {
      // 在偶发竞态下（图像刚被释放），优雅跳过本帧绘制
    }
  }

  @override
  bool shouldRepaint(covariant _GpuLutPainter oldDelegate) {
    return oldDelegate.yImage != yImage ||
        oldDelegate.uvImage != uvImage ||
        oldDelegate.lutImage != lutImage ||
        oldDelegate.mix != mix ||
        oldDelegate.yuvMode != yuvMode ||
        oldDelegate.swapUV != swapUV ||
        oldDelegate.lutTilesX != lutTilesX ||
        oldDelegate.lutTilesY != lutTilesY ||
        oldDelegate.flipLutY != flipLutY ||
        oldDelegate.lutSize != lutSize ||
        oldDelegate.srcW != srcW ||
        oldDelegate.srcH != srcH ||
        oldDelegate.uvW != uvW ||
        oldDelegate.uvH != uvH;
  }
}

// Simple struct-like holder for packed pixels
class _PackedBytes {
  final Uint8List bytes;
  final int width;
  final int height;
  const _PackedBytes({required this.bytes, required this.width, required this.height});
}

/// YUV color conversion mode for the shader
enum GpuYuvMode {
  bt709Full,
  bt601Limited,
}
