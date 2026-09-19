import 'dart:async';
// Uint8List/ByteData 已由 flutter/services.dart 间接提供
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'cube_loader.dart';
import 'gpu_lut_preview.dart' show GpuYuvMode; // Reuse enum for mode
import 'package:image/image.dart' as img;

/// 离线静态图像的 GPU LUT 渲染器（与预览分离）
/// - 复用现有 fragment shader（shaders/gpu_lut.frag）
/// - 全分辨率渲染，追求最高质量，不考虑性能
/// - 异步接口，避免调用方阻塞 UI 事件流
class GpuLutStillRenderer {
  /// 使用 GPU shader 将 LUT 应用于一张 JPEG（或任意可由 Flutter 解码的位图）
  /// 返回按 JPEG 编码后的字节（不包含 EXIF，EXIF 可由上层注入）
  static Future<Uint8List> processJpegWithLut({
    required Uint8List jpegBytes,
    required String lutPath,
    required double mixStrength,
    int jpegQuality = 95,
    GpuYuvMode yuvMode = GpuYuvMode.bt709Full,
    bool swapUV = false,
    int? lutSize,
    int? lutTilesX,
    int? lutTilesY,
    bool flipLutY = false,
  }) async {
    // 1) 解码输入图像为 ui.Image
    final decoded = await _decodeToUiImage(jpegBytes);
    final int w = decoded.width;
    final int h = decoded.height;

    // 2) 从 ui.Image 获取 RGBA 像素
    final rgba = await _imageToRgba(decoded);

    // 3) 将 RGBA 转换为 Shader 需要的 Y 与 UV 两个纹理图（全分辨率）
    final yPacked = _rgbaToYPlaneRgba(rgba, w, h);
    final uvPacked = _rgbaToUVPlaneRgba(rgba, w, h, yuvMode);
    final yImage = await _rgbaToUiImage(yPacked.bytes, yPacked.width, yPacked.height);
    final uvImage = await _rgbaToUiImage(uvPacked.bytes, uvPacked.width, uvPacked.height);

    // 4) 加载/打包 LUT 为 2D 纹理
    final ui.Image lut2D = await _loadLut2D(lutPath);

    // 5) 使用 FragmentProgram 进行全尺寸离线绘制
    final program = await ui.FragmentProgram.fromAsset('shaders/gpu_lut.frag');
    final result = await _renderWithShader(
      program: program,
      dstW: w.toDouble(),
      dstH: h.toDouble(),
      srcW: w,
      srcH: h,
      uvW: uvPacked.width,
      uvH: uvPacked.height,
      yImage: yImage,
      uvImage: uvImage,
      lutImage: lut2D,
      mix: mixStrength,
      yuvMode: yuvMode,
      swapUV: swapUV,
      lutTilesX: lutTilesX,
      lutTilesY: lutTilesY,
      flipLutY: flipLutY,
      lutSize: lutSize ?? lut2D.height,
    );

    // 6) 将结果 ui.Image 转为 RGBA 字节
    final outRgba = await _imageToRgba(result);

    // 7) 使用 image 包编码为 JPEG（异步调度，避免与当前帧竞争）
    await Future<void>.delayed(Duration.zero);
    final encoded = _encodeJpeg(outRgba, w, h, jpegQuality);
    return encoded;
  }

  // 将结果 RGBA 编码为 JPEG（通过 package:image），保持此处异步
  static Uint8List _encodeJpeg(Uint8List rgba, int w, int h, int quality) {
    final image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  // 解码任意图像为 ui.Image
  static Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<Uint8List> _imageToRgba(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw Exception('Failed to extract RGBA bytes from ui.Image');
    }
    return byteData.buffer.asUint8List();
  }

  static Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int w, int h) async {
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

  // 使用与 shader 常量一致的逆变换，从 RGB' 求 U、V（centered），并回写到 [0..1] 存储
  static _PackedBytes _rgbaToYPlaneRgba(Uint8List rgba, int w, int h) {
    final out = Uint8List(w * h * 4);
    for (int j = 0; j < h; j++) {
      final row = j * w * 4;
      for (int i = 0; i < w; i++) {
        final idx = row + i * 4;
        final r = rgba[idx] / 255.0;
        final g = rgba[idx + 1] / 255.0;
        final b = rgba[idx + 2] / 255.0;
        // 使用 BT.709 亮度近似（gamma 空间下近似足够）
        final y = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
        out[idx] = (y * 255.0).toInt();
        out[idx + 1] = 0;
        out[idx + 2] = 0;
        out[idx + 3] = 255;
      }
    }
    return _PackedBytes(bytes: out, width: w, height: h);
  }

  static _PackedBytes _rgbaToUVPlaneRgba(Uint8List rgba, int w, int h, GpuYuvMode mode) {
    final out = Uint8List(w * h * 4);
    for (int j = 0; j < h; j++) {
      final row = j * w * 4;
      for (int i = 0; i < w; i++) {
        final idx = row + i * 4;
        final r = rgba[idx] / 255.0;
        final g = rgba[idx + 1] / 255.0;
        final b = rgba[idx + 2] / 255.0;
        double yN;
        if (mode == GpuYuvMode.bt601Limited) {
          // 近似：先按 709 求 y，再缩放到 601 有效区间的等效 y'（保持一致性即可）
          yN = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
          // 为了与 shader 的 601 分支对应（其内部会 1.164*(y-16/255)），此处仍存储原始 [0..1]
        } else {
          yN = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
        }
        // 与 shader 使用的矩阵常数保持一致的反推：
        // U = (B - y)/2.128, V = (R - y)/1.280
        final U = ((b - yN) / 2.128).clamp(-0.5, 0.5);
        final V = ((r - yN) / 1.280).clamp(-0.5, 0.5);
        final uStore = (U + 0.5).clamp(0.0, 1.0);
        final vStore = (V + 0.5).clamp(0.0, 1.0);
        out[idx] = (uStore * 255.0).toInt();
        out[idx + 1] = (vStore * 255.0).toInt();
        out[idx + 2] = 0;
        out[idx + 3] = 255;
      }
    }
    return _PackedBytes(bytes: out, width: w, height: h);
  }

  static Future<ui.Image> _loadLut2D(String lutPath) async {
    ByteData lutData;
    if (lutPath.startsWith('assets/')) {
      lutData = await rootBundle.load(lutPath);
    } else {
      // ignore: avoid_slow_async_io
      final bytes = await _readFileBytes(lutPath);
      lutData = ByteData.sublistView(bytes);
    }
    if (lutPath.toLowerCase().endsWith('.png')) {
      final codec = await ui.instantiateImageCodec(lutData.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } else {
      final cube = await loadCubeLut(lutData);
      final img = await _packCubeTo2DImage(cube);
      return img;
    }
  }

  static Future<ui.Image> _packCubeTo2DImage(CubeLut cube) async {
    final N = cube.size;
    final width = N * N;
    final height = N;
    final bytes = Uint8List(width * height * 4);
    final data = cube.data; // Float32List in [0..1]
    for (int b = 0; b < N; b++) {
      for (int g = 0; g < N; g++) {
        for (int r = 0; r < N; r++) {
          final base = ((b * N * N) + (g * N) + r) * 3;
          final rr = (data[base] * 255.0).clamp(0.0, 255.0).toInt();
          final gg = (data[base + 1] * 255.0).clamp(0.0, 255.0).toInt();
          final bb = (data[base + 2] * 255.0).clamp(0.0, 255.0).toInt();
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

  static Future<ui.Image> _renderWithShader({
    required ui.FragmentProgram program,
    required double dstW,
    required double dstH,
    required int srcW,
    required int srcH,
    required int uvW,
    required int uvH,
    required ui.Image yImage,
    required ui.Image uvImage,
    required ui.Image lutImage,
    required double mix,
    required GpuYuvMode yuvMode,
    required bool swapUV,
    int? lutTilesX,
    int? lutTilesY,
    bool flipLutY = false,
    required int lutSize,
  }) async {
    final shader = program.fragmentShader();
    shader.setImageSampler(0, yImage);
    shader.setImageSampler(1, uvImage);
    shader.setImageSampler(2, lutImage);

    // 推断 atlas 切片
    double tilesX;
    double tilesY;
    if (lutTilesX != null && lutTilesY != null) {
      tilesX = lutTilesX.toDouble();
      tilesY = lutTilesY.toDouble();
    } else if (lutImage.width == lutSize * lutSize && lutImage.height == lutSize) {
      tilesX = lutSize.toDouble();
      tilesY = 1.0;
    } else if (lutImage.width == lutImage.height && (lutImage.width % lutSize == 0)) {
      final t = (lutImage.width ~/ lutSize).toDouble();
      tilesX = t;
      tilesY = t;
    } else {
      tilesX = lutSize.toDouble();
      tilesY = 1.0;
    }

    shader.setFloat(0, lutSize.toDouble());
    shader.setFloat(1, mix);
    shader.setFloat(2, yuvMode == GpuYuvMode.bt709Full ? 0.0 : 1.0);
    shader.setFloat(3, swapUV ? 1.0 : 0.0);
    shader.setFloat(4, lutImage.width.toDouble());
    shader.setFloat(5, lutImage.height.toDouble());
    shader.setFloat(6, tilesX);
    shader.setFloat(7, tilesY);
    shader.setFloat(8, flipLutY ? 1.0 : 0.0);
    shader.setFloat(9, dstW);
    shader.setFloat(10, dstH);
    shader.setFloat(11, srcW.toDouble());
    shader.setFloat(12, srcH.toDouble());
    shader.setFloat(13, uvW.toDouble());
    shader.setFloat(14, uvH.toDouble());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, dstW, dstH));
    final paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, dstW, dstH), paint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(dstW.toInt(), dstH.toInt());
    return image;
  }

  // 读取文件字节（assets 或外部路径）
  static Future<Uint8List> _readFileBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    }
  }
}

class _PackedBytes {
  final Uint8List bytes;
  final int width;
  final int height;
  const _PackedBytes({required this.bytes, required this.width, required this.height});
}

// 动态封装对 package:image 的最小依赖，避免在上层引入时打断 UI
// 无需动态封装，已直接使用 package:image 公共 API
