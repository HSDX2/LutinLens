import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../utils/preferences.dart';
import '../utils/lut_manager.dart';
import '../lut/lut_preview_manager.dart';

class AiSuggestionService extends ChangeNotifier {
  static final AiSuggestionService _instance = AiSuggestionService._internal();
  factory AiSuggestionService() => _instance;
  AiSuggestionService._internal();

  Timer? _uploadTimer;
  Timer? _hideTimer;
  String _sessionId = '';
  String _currentLutSuggestion = '正在分析场景...';
  String _currentFramingSuggestion = '正在分析场景...';
  String? _currentLutValue; // 存储AI推荐的LUT编号
  bool _isUploading = false;
  int _readyToShoot = 0;
  CameraController? _cameraController;

  String get sessionId => _sessionId;
  String get currentLutSuggestion => _currentLutSuggestion;
  String get currentFramingSuggestion => _currentFramingSuggestion;
  String? get currentLutValue => _currentLutValue; // 获取当前推荐的LUT编号
  bool get isUploading => _isUploading;
  int get readyToShoot => _readyToShoot;

  // 兼容旧代码的getter
  String get currentSuggestion => _currentFramingSuggestion;

  void startService(CameraController? controller) async {
    if (!Preferences.getAiSuggestionEnabled()) {
      return;
    }

    _cameraController = controller;
    _sessionId = const Uuid().v4();
    _currentLutSuggestion = ''; // 初始为空，不显示任何内容
    _currentFramingSuggestion = '点击屏幕获取AI建议';
    _currentLutValue = null;
    
    // 检查所有必要的API配置
    final imageUploadUrl = Preferences.getAiImageUploadUrl();
    final lutSuggestionUrl = Preferences.getAiLutSuggestionUrl();
    final framingSuggestionUrl = Preferences.getAiFramingSuggestionUrl();
    
    if (imageUploadUrl.isNotEmpty && lutSuggestionUrl.isNotEmpty && framingSuggestionUrl.isNotEmpty) {
      // 使用用户设置的轮询频率
      final pollingInterval = Preferences.getAiPollingInterval();
      _uploadTimer?.cancel();
      _uploadTimer = Timer.periodic(Duration(seconds: pollingInterval), (_) {
        _uploadCurrentFrame();
      });
      
      debugPrint('[AI] AI建议服务已启动，Session ID: $_sessionId');
    } else {
      debugPrint('[AI] API配置不完整，请在设置中配置所有API地址');
      _currentLutSuggestion = 'API配置不完整';
      _currentFramingSuggestion = 'API配置不完整';
      _currentLutValue = null;
      notifyListeners();
    }
  }

  void stopService() async {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _hideTimer?.cancel();
    _hideTimer = null;
    _cameraController = null;
    _currentLutSuggestion = '服务已停止';
    _currentFramingSuggestion = '服务已停止';
    _currentLutValue = null;
    
    notifyListeners();
    debugPrint('[AI] AI建议服务已停止');
  }

  void updateCameraController(CameraController? controller) {
    _cameraController = controller;
  }

  Future<void> _uploadCurrentFrame() async {
    if (_isUploading || 
        _cameraController == null || 
        !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      _isUploading = true;
      // 不立即取消隐藏计时器，让取景建议能完整显示
      // 只更新取景建议为"分析中..."，LUT建议保持上一次的内容
      _currentFramingSuggestion = '分析中...';
      // 不清空LUT值，保持应用按钮可用直到下一条LUT建议给出
      notifyListeners();

      // 执行完整的业务流程
      await _executeFullWorkflow();
      
    } catch (e) {
      debugPrint('[AI] 上传图像失败: $e');
      _currentLutSuggestion = '连接服务器失败';
      _currentFramingSuggestion = '连接服务器失败';
      // 不清空LUT值，保持之前的应用按钮可用
      notifyListeners();
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// 执行完整的AI业务流程
  Future<void> _executeFullWorkflow() async {
    try {
      // 第一步：捕获当前帧
      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List originalImageBytes = await imageFile.readAsBytes();
      
      // 第二步：生成新的UUID文件名（每次都生成新的）
      final String uuid = const Uuid().v4();
      // 移除UUID中的破折号，使文件名更简洁
      final String cleanUuid = uuid.replaceAll('-', '');
      final String fileName = '$cleanUuid.jpg';
      debugPrint('[AI] 生成文件名: $fileName (UUID: $uuid)');
      
      // 第三步：压缩图片到540p分辨率和100KB以下
      final Uint8List compressedImageBytes = await _compressImage(originalImageBytes);
      debugPrint('[AI] 图片压缩完成，原始大小: ${originalImageBytes.length}字节, 压缩后: ${compressedImageBytes.length}字节');
      
      // 第四步：上传图片到图床服务
      final String imageUrl = await _uploadImageToServer(compressedImageBytes, fileName);
      debugPrint('[AI] 图片上传成功: $imageUrl');
      
      // 第五步：生成base64编码的图片数据用于取景建议
      debugPrint('[AI] 开始生成base64编码...');
      final String base64Image = base64Encode(compressedImageBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';
      debugPrint('[AI] Base64编码完成，数据URI长度: ${dataUri.length}字符');
      debugPrint('[AI] Base64前缀: ${dataUri.substring(0, dataUri.length > 50 ? 50 : dataUri.length)}...');
      
      // 第六步：并行请求LUT建议和取景建议
      debugPrint('[AI] 开始并行请求AI服务...');
      debugPrint('[AI] LUT建议URL: ${Preferences.getAiLutSuggestionUrl()}');
      debugPrint('[AI] 取景建议URL: ${Preferences.getAiFramingSuggestionUrl()}');
      
      final Future<String> lutFuture = _requestLutSuggestion(imageUrl);
      final Future<Map<String, dynamic>> framingFuture = _requestFramingSuggestion(dataUri);
      
      debugPrint('[AI] 等待AI服务响应...');
      final List<dynamic> results = await Future.wait([lutFuture, framingFuture]);
      debugPrint('[AI] AI服务响应完成');
      
      final String lutSuggestion = results[0] as String;
      final Map<String, dynamic> framingResult = results[1] as Map<String, dynamic>;
      
      debugPrint('[AI] LUT建议原始响应: $lutSuggestion');
      debugPrint('[AI] 取景建议原始响应: $framingResult');
      
      // 将LUT编号转换为实际的LUT名称
      String lutDisplayName = lutSuggestion;
      if (_currentLutValue != null && _currentLutValue!.isNotEmpty) {
        try {
          // 获取所有LUT并找到匹配的名称
          final luts = await LutManager.getAllAssetLuts();
          for (final lut in luts) {
            if (lut.name.startsWith('${_currentLutValue}_')) {
              lutDisplayName = lut.name;
              break;
            }
          }
        } catch (e) {
          debugPrint('[AI] 获取LUT名称失败: $e');
        }
      }
      
      // 更新UI
      _currentLutSuggestion = lutDisplayName; // LUT建议持续显示
      _currentFramingSuggestion = framingResult['suggestion'] ?? '无建议';
      _readyToShoot = framingResult['ready_to_shoot'] ?? 0;
      
      debugPrint('[AI] LUT建议显示: $lutDisplayName, 取景建议: $_currentFramingSuggestion, ready_to_shoot: $_readyToShoot');
      
      // 取消之前的隐藏计时器，设置新的3秒计时器
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 3), () {
        _currentFramingSuggestion = ''; // 只清空取景建议
        // _currentLutSuggestion 保持不变，继续显示LUT
        // _currentLutValue 保持不变，应用按钮继续可用
        notifyListeners();
      });
      
    } catch (e) {
      debugPrint('[AI] 执行完整流程失败: $e');
      debugPrint('[AI] 错误堆栈: ${StackTrace.current}');
      _currentLutSuggestion = '处理失败: $e';
      _currentFramingSuggestion = '处理失败: $e';
      // 不清空LUT值，保持应用按钮可用
    }
    
    notifyListeners();
  }

  /// 压缩图片到540p分辨率和100KB以下
  Future<Uint8List> _compressImage(Uint8List originalBytes) async {
    try {
      // 设置目标参数
      const int targetWidth = 960;  // 540p通常指的是960x540
      const int targetHeight = 540;
      const int maxSizeKB = 100;
      const int maxSizeBytes = maxSizeKB * 1024;
      
      // 初始质量设置
      int quality = 85;
      Uint8List compressedBytes = originalBytes;
      
      // 第一步：先压缩分辨率
      compressedBytes = await FlutterImageCompress.compressWithList(
        originalBytes,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      
      // 第二步：如果文件仍然太大，循环降低质量
      while (compressedBytes.length > maxSizeBytes && quality > 10) {
        quality -= 10; // 降低质量
        
        compressedBytes = await FlutterImageCompress.compressWithList(
          originalBytes,
          minWidth: targetWidth,
          minHeight: targetHeight,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        
        debugPrint('[AI] 压缩质量调整: $quality, 当前大小: ${compressedBytes.length}字节');
      }
      
      debugPrint('[AI] 图片压缩完成: 质量=$quality, 大小=${compressedBytes.length}字节 (${(compressedBytes.length/1024).toStringAsFixed(1)}KB)');
      return compressedBytes;
      
    } catch (e) {
      debugPrint('[AI] 图片压缩失败: $e');
      // 压缩失败时返回原始图片
      return originalBytes;
    }
  }

  /// 上传图片到图床服务
  Future<String> _uploadImageToServer(Uint8List imageBytes, String fileName) async {
    final String uploadUrl = Preferences.getAiImageUploadUrl();
    final Uri uri = Uri.parse('$uploadUrl/$fileName');
    
    debugPrint('[AI] 开始上传图片: $uri');
    debugPrint('[AI] 图片大小: ${imageBytes.length}字节 (${(imageBytes.length/1024).toStringAsFixed(1)}KB)');
    debugPrint('[AI] 文件名: $fileName');
    
    try {
      // 创建multipart请求
      var request = http.MultipartRequest('PUT', uri);
      
      // 添加文件字段
      request.files.add(
        http.MultipartFile.fromBytes(
          'file', // API期望的字段名
          imageBytes,
          filename: fileName,
        ),
      );
      
      // 设置请求头
      request.headers.addAll({
        'Accept': '*/*',
      });
      
      debugPrint('[AI] 发送multipart PUT请求...');
      debugPrint('[AI] 请求头: ${request.headers}');
      debugPrint('[AI] 文件字段: file, 文件名: $fileName, 大小: ${imageBytes.length}字节');
      
      final response = await request.send().timeout(const Duration(seconds: 15));
      final responseBody = await response.stream.bytesToString();

      debugPrint('[AI] PUT响应状态码: ${response.statusCode}');
      debugPrint('[AI] 响应头: ${response.headers}');
      debugPrint('[AI] 响应体: $responseBody');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final String resultUrl = '$uploadUrl/$fileName';
        debugPrint('[AI] 上传成功: $resultUrl');
        return resultUrl;
      } else {
        debugPrint('[AI] 上传失败响应体: $responseBody');
        throw Exception('图片上传失败: HTTP ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      debugPrint('[AI] 上传异常: $e');
      rethrow;
    }
  }

  /// 请求LUT建议（8000端口）
  Future<String> _requestLutSuggestion(String imageUrl) async {
    final String apiUrl = Preferences.getAiLutSuggestionUrl();
    
    debugPrint('[AI-LUT] 开始请求LUT建议');
    debugPrint('[AI-LUT] API URL: $apiUrl');
    debugPrint('[AI-LUT] 图片URL: $imageUrl');
    
    final Map<String, dynamic> requestBody = {
      'input_message': imageUrl,
    };
    
    debugPrint('[AI-LUT] 请求体: ${jsonEncode(requestBody)}');
    
    try {
      debugPrint('[AI-LUT] 发送POST请求...');
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30)); // 增加超时时间到30秒

      debugPrint('[AI-LUT] 响应状态码: ${response.statusCode}');
      debugPrint('[AI-LUT] 响应头: ${response.headers}');
      debugPrint('[AI-LUT] 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final String lutValue = responseData['value']?.toString() ?? '';
        
        debugPrint('[AI-LUT] 解析的LUT值: "$lutValue"');
        
        // 保存LUT编号供应用按钮使用
        _currentLutValue = lutValue.isNotEmpty ? lutValue : null;
        debugPrint('[AI-LUT] 保存的LUT值: $_currentLutValue');
        
        return lutValue.isNotEmpty ? lutValue : '无建议';
      } else {
        debugPrint('[AI-LUT] 请求失败: ${response.statusCode} - ${response.body}');
        throw Exception('LUT建议请求失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AI-LUT] 请求异常: $e');
      if (e.toString().contains('TimeoutException')) {
        debugPrint('[AI-LUT] 请求超时，LUT服务可能响应较慢');
      }
      rethrow;
    }
  }

  /// 请求取景建议（8001端口）
  Future<Map<String, dynamic>> _requestFramingSuggestion(String imageData) async {
    final String apiUrl = Preferences.getAiFramingSuggestionUrl();
    
    debugPrint('[AI-FRAMING] 开始请求取景建议');
    debugPrint('[AI-FRAMING] API URL: $apiUrl');
    debugPrint('[AI-FRAMING] Session ID: $_sessionId');
    debugPrint('[AI-FRAMING] 图片数据长度: ${imageData.length}字符');
    debugPrint('[AI-FRAMING] 图片数据前缀: ${imageData.substring(0, imageData.length > 80 ? 80 : imageData.length)}...');
    
    final Map<String, dynamic> requestBody = {
      'session_id': _sessionId, // API文档中session_id在前
      'img': imageData, // 现在传递的是base64数据URI
    };
    
    // 不打印完整请求体，因为base64数据太长
    debugPrint('[AI-FRAMING] 请求体结构: {session_id: "$_sessionId", img: "[${imageData.length}字符的base64数据]"}');
    
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 10));

      debugPrint('[AI-FRAMING] 响应状态码: ${response.statusCode}');
      debugPrint('[AI-FRAMING] 响应头: ${response.headers}');
      debugPrint('[AI-FRAMING] 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final responseBody = response.body;
        
        // 尝试解析JSON，如果失败则作为纯文本处理
        try {
          final result = jsonDecode(responseBody) as Map<String, dynamic>;
          debugPrint('[AI-FRAMING] 成功解析JSON响应: $result');
          return result;
        } catch (e) {
          debugPrint('[AI-FRAMING] JSON解析失败，作为纯文本处理: $e');
          // 如果响应是纯文本，包装成标准格式
          final result = {
            'suggestion': responseBody,
            'ready_to_shoot': 0, // 修正字段名：ready_to_shoot而不是ready_to_shot
          };
          debugPrint('[AI-FRAMING] 包装后的结果: $result');
          return result;
        }
      } else {
        debugPrint('[AI-FRAMING] 请求失败: ${response.statusCode} - ${response.body}');
        throw Exception('取景建议请求失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AI-FRAMING] 请求异常: $e');
      rethrow;
    }
  }
  
  /// 应用AI推荐的LUT
  Future<bool> applyRecommendedLut() async {
    debugPrint('[AI-APPLY] 开始应用推荐的LUT');
    debugPrint('[AI-APPLY] 当前LUT值: $_currentLutValue');
    
    if (_currentLutValue == null || _currentLutValue!.isEmpty) {
      debugPrint('[AI-APPLY] 没有可应用的LUT推荐');
      return false;
    }
    
    try {
      // 获取所有可用的LUT
      debugPrint('[AI-APPLY] 获取所有可用的LUT...');
      final luts = await LutManager.getAllAssetLuts();
      debugPrint('[AI-APPLY] 找到 ${luts.length} 个LUT');
      debugPrint('[AI-APPLY] 可用LUT列表: ${luts.map((e) => e.name).toList()}');
      
      // 查找匹配的LUT（按编号前缀匹配）
      LutFile? targetLut;
      for (final lut in luts) {
        debugPrint('[AI-APPLY] 检查LUT: "${lut.name}" vs "$_currentLutValue"');
        // 检查LUT名称是否以"编号_"开头匹配
        if (lut.name.startsWith('${_currentLutValue}_')) {
          targetLut = lut;
          debugPrint('[AI-APPLY] 找到匹配的LUT: ${lut.name}');
          break;
        }
        // 也支持完全匹配（向后兼容）
        if (lut.name == _currentLutValue) {
          targetLut = lut;
          debugPrint('[AI-APPLY] 找到完全匹配的LUT: ${lut.name}');
          break;
        }
      }
      
      if (targetLut == null) {
        debugPrint('[AI-APPLY] 未找到匹配的LUT: $_currentLutValue');
        return false;
      }
      
      // 停止图像流，安全切换LUT
      debugPrint('[AI-APPLY] 停止图像流...');
      await LutPreviewManager.instance.stopImageStream();
      
      // 应用推荐的LUT（使用与LUT控制组件相同的逻辑）
      debugPrint('[AI-APPLY] 应用LUT: ${targetLut.path}');
      await LutPreviewManager.instance.setCurrentLut(targetLut.path);
      
      // 持久化选择
      await Preferences.setSelectedLutName(targetLut.name);
      await Preferences.setSelectedLutPath(targetLut.path);
      await Preferences.setLutEnabled(true);
      debugPrint('[AI-APPLY] LUT设置完成');
      
      // 稍作延迟后恢复流，避免切换抖动
      await Future.delayed(const Duration(milliseconds: 200));
      debugPrint('[AI-APPLY] 恢复图像流...');
      LutPreviewManager.instance.resumeImageStream();
      
      debugPrint('[AI-APPLY] 成功应用推荐的LUT: ${targetLut.name}');
      return true;
      
    } catch (e) {
      debugPrint('[AI-APPLY] 应用推荐的LUT失败: $e');
      debugPrint('[AI-APPLY] 确保恢复图像流...');
      LutPreviewManager.instance.resumeImageStream(); // 确保恢复图像流
      return false;
    }
  }
}
