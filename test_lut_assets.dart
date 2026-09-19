import 'dart:convert';
import 'package:flutter/services.dart';

Future<void> testLutAssets() async {
  try {
    print('尝试读取 AssetManifest.bin...');
    final ByteData manifestData = await rootBundle.load('AssetManifest.bin');
    final manifestMap = const StandardMessageCodec().decodeMessage(manifestData) as Map<Object?, Object?>;
    
    final lutAssets = manifestMap.keys
        .cast<String>()
        .where((k) => k.startsWith('assets/Luts/') && k.endsWith('.cube'))
        .toList();
    
    print('找到 ${lutAssets.length} 个 LUT 资产:');
    for (final asset in lutAssets) {
      print('  - $asset');
    }
  } catch (binError) {
    print('AssetManifest.bin 读取失败: $binError');
    
    try {
      print('尝试读取 AssetManifest.json...');
      final String manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson) as Map<String, dynamic>;
      
      final lutAssets = manifestMap.keys
          .where((k) => k.startsWith('assets/Luts/') && k.endsWith('.cube'))
          .toList();
      
      print('找到 ${lutAssets.length} 个 LUT 资产:');
      for (final asset in lutAssets) {
        print('  - $asset');
      }
    } catch (jsonError) {
      print('AssetManifest.json 读取失败: $jsonError');
    }
  }
  
  // 直接尝试加载已知的LUT文件
  try {
    print('\n直接测试加载 CINEMATIC_FILM.cube...');
    final ByteData data = await rootBundle.load('assets/Luts/CINEMATIC_FILM/CINEMATIC_FILM.cube');
    print('成功! 文件大小: ${data.lengthInBytes} 字节');
  } catch (e) {
    print('直接加载失败: $e');
  }
}
