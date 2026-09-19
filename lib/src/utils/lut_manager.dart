import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LUT文件管理器
/// 负责管理用户的LUT文件，包括默认LUT的初始化、用户LUT的增删改查等
class LutManager {
  static const String _lutsInitializedKey = 'luts_initialized';
  static const String _defaultLutPath = 'assets/Luts/';
  static const String _userLutsDirName = 'luts';
  static const String _defaultLutName = '0_人像，电影感，皮肤质感';

  /// 获取用户LUT存储目录
  static Future<Directory> getUserLutsDirectory() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory lutsDir = Directory(p.join(appDocDir.path, _userLutsDirName));
    
    if (!await lutsDir.exists()) {
      await lutsDir.create(recursive: true);
    }
    
    return lutsDir;
  }

  /// 初始化LUT系统
  /// 直接使用静态资源，无需复制到用户目录
  static Future<void> initializeLuts() async {
    try {
      debugPrint('🔄 初始化LUT系统，直接使用静态资源...');
      
      // 验证静态资源是否可用
      final names = await _discoverAssetLutNames();
      debugPrint('� 发现 ${names.length} 个静态LUT文件: $names');
      
      debugPrint('✅ LUT初始化完成，使用静态资源模式');
    } catch (e) {
      debugPrint('❌ LUT初始化失败: $e');
    }
  }

  /// 从 AssetManifest 中枚举所有 assets/Luts/ 下的 .cube 文件，提取 LUT 名称
  static Future<List<String>> _discoverAssetLutNames() async {
    try {
      debugPrint('[LUT] 读取 AssetManifest...');
      
      // 尝试新版本的 AssetManifest.bin 格式
      try {
        final ByteData manifestData = await rootBundle.load('AssetManifest.bin');
        final manifestMap = const StandardMessageCodec().decodeMessage(manifestData) as Map<Object?, Object?>;
        
        final related = manifestMap.keys
            .cast<String>()
            .where((k) => k.startsWith(_defaultLutPath))
            .toList()
          ..sort();
        debugPrint('[LUT] AssetManifest.bin 中与 LUT 相关的条目共 ${related.length} 个');
        for (final k in related) {
          debugPrint('[LUT] manifest: $k');
        }

        final Set<String> names = {};
        for (final String assetPath in manifestMap.keys.cast<String>()) {
          // 直接匹配 assets/Luts/*.cube 格式的文件
          if (assetPath.startsWith(_defaultLutPath) && assetPath.endsWith('.cube')) {
            final parts = assetPath.split('/');
            if (parts.length == 3) {
              // 形如: assets/Luts/<FILE>.cube 的直接文件
              final fileName = parts[2]; // <FILE>.cube
              final name = fileName.replaceAll('.cube', '');
              names.add(name);
            } else if (parts.length >= 4) {
              // 形如: assets/Luts/<DIR>/<FILE>.cube 的子目录文件（兼容旧格式）
              final dirName = parts[2];
              names.add(dirName);
            }
          }
        }
        final list = names.toList()..sort();
        debugPrint('[LUT] 在 assets 中发现默认LUT 名称: $list');
        return list;
      } catch (binError) {
        debugPrint('[LUT] AssetManifest.bin 读取失败，尝试 JSON 格式: $binError');
        
        // 回退到旧版本的 JSON 格式
        final String manifestJson = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifestMap = json.decode(manifestJson) as Map<String, dynamic>;

        final related = manifestMap.keys
            .where((k) => k.startsWith(_defaultLutPath))
            .toList()
          ..sort();
        debugPrint('[LUT] AssetManifest.json 中与 LUT 相关的条目共 ${related.length} 个');
        for (final k in related) {
          debugPrint('[LUT] manifest: $k');
        }

        final Set<String> names = {};
        for (final String assetPath in manifestMap.keys) {
          // 直接匹配 assets/Luts/*.cube 格式的文件
          if (assetPath.startsWith(_defaultLutPath) && assetPath.endsWith('.cube')) {
            final parts = assetPath.split('/');
            if (parts.length == 3) {
              // 形如: assets/Luts/<FILE>.cube 的直接文件
              final fileName = parts[2]; // <FILE>.cube
              final name = fileName.replaceAll('.cube', '');
              names.add(name);
            } else if (parts.length >= 4) {
              // 形如: assets/Luts/<DIR>/<FILE>.cube 的子目录文件（兼容旧格式）
              final dirName = parts[2];
              names.add(dirName);
            }
          }
        }
        final list = names.toList()..sort();
        debugPrint('[LUT] 在 assets 中发现默认LUT 名称: $list');
        return list;
      }
    } catch (e) {
      debugPrint('[LUT][ERR] 读取 AssetManifest 失败，回退为空: $e');
      return [];
    }
  }

  /// 尝试从 asset CSV 获取指定 LUT 的描述
  static Future<String?> _tryReadAssetDescription(String assetDir, String lutName, String fileName) async {
    try {
      final ByteData csvData = await rootBundle.load('$assetDir$fileName');
      final content = utf8.decode(csvData.buffer.asUint8List());
      final lines = content.split(RegExp(r'\r?\n'));
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.toLowerCase().startsWith('name,')) continue;
        final parts = line.split(',');
        if (parts.isEmpty) continue;
        final name = parts.first.trim();
        if (name == lutName) {
          return parts.length > 1 ? parts[1].trim() : null;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 获取所有可用的LUT文件
  static Future<List<LutFile>> getAllLuts() async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      final List<LutFile> luts = [];

      await for (final FileSystemEntity entity in lutsDir.list()) {
        if (entity is File && entity.path.endsWith('.cube')) {
          final String name = p.basenameWithoutExtension(entity.path);
          final String description = await _getLutDescription(entity.path, name);
          
          luts.add(LutFile(
            name: name,
            path: entity.path,
            description: description,
            isDefault: name == _defaultLutName,
          ));
        }
      }

      // 排序：默认置顶，其余按名称
      luts.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return luts;
    } catch (e) {
      debugPrint('❌ 获取LUT列表失败: $e');
      return [];
    }
  }

  /// 从 assets 直接枚举可用的 LUT（不使用用户目录拷贝）
  static Future<List<LutFile>> getAllAssetLuts() async {
    try {
      final names = await _discoverAssetLutNames();
      final List<LutFile> luts = [];
      if (names.isEmpty) {
        debugPrint('[LUT] 未发现任何 LUT 名称，请检查 assets 路径与 pubspec 资源声明');
      }
      for (final name in names) {
        // 直接构建 LUT 路径，支持两种格式：
        // 1. assets/Luts/<NAME>.cube (新格式，直接放在Luts目录下)
        // 2. assets/Luts/<NAME>/<NAME>.cube (旧格式，每个LUT有自己的文件夹)
        String lutPath = '$_defaultLutPath$name.cube';
        
        // 先尝试直接路径
        try {
          await rootBundle.load(lutPath);
          debugPrint('[LUT] 找到直接路径的 LUT: $lutPath');
        } catch (e) {
          // 如果直接路径不存在，尝试子目录路径（兼容旧格式）
          lutPath = '$_defaultLutPath$name/$name.cube';
          try {
            await rootBundle.load(lutPath);
            debugPrint('[LUT] 找到子目录路径的 LUT: $lutPath');
          } catch (e2) {
            debugPrint('[LUT] 跳过无法加载的 LUT: $name ($e, $e2)');
            continue;
          }
        }
        
        debugPrint('[LUT] 构建 LUT: name=$name, path=$lutPath');
        String? desc;
        
        // 尝试读取描述（先尝试子目录格式，再尝试根目录格式）
        try {
          desc = await _tryReadAssetDescription('$_defaultLutPath$name/', name, 'describe.csv');
          desc ??= await _tryReadAssetDescription('$_defaultLutPath$name/', name, 'discribe.csv');
        } catch (e) {
          // 忽略描述读取错误
        }
        
        desc ??= '$name cinematic look LUT';
        
        luts.add(LutFile(
          name: name,
          path: lutPath,
          description: desc,
          isDefault: name == _defaultLutName,
        ));
      }
      luts.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      debugPrint('[LUT] 最终可用 LUT 数量: ${luts.length} — ${luts.map((e) => e.name).toList()}');
      return luts;
    } catch (e) {
      debugPrint('[LUT][ERR] 读取 assets LUT 列表失败: $e');
      return [];
    }
  }

  /// 获取LUT描述信息
  static Future<String> _getLutDescription(String lutPath, String lutName) async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      // 统一只读全局 describe.csv，兼容旧 discribe.csv 名称
      File describeFile = File(p.join(lutsDir.path, 'describe.csv'));
      if (!await describeFile.exists()) {
        describeFile = File(p.join(lutsDir.path, 'discribe.csv'));
      }

      if (await describeFile.exists()) {
        final String content = await describeFile.readAsString();
        final List<String> lines = content.split('\n');
        
        for (String line in lines) {
          if (line.trim().isNotEmpty && line.split(',').isNotEmpty && line.split(',').first.trim() == lutName) {
            final List<String> parts = line.split(',');
            return parts.length > 1 ? parts[1].trim() : 'No description';
          }
        }
      }
      
      return 'Cinematic look LUT';
    } catch (e) {
      return 'Cinematic look LUT';
    }
  }

  /// 导入新的LUT文件
  static Future<bool> importLut(String sourcePath, String lutName) async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      final File sourceFile = File(sourcePath);
      final String safeName = _sanitizeLutName(lutName);
      final File targetFile = File(p.join(lutsDir.path, '$safeName.cube'));

      if (!await sourceFile.exists()) {
        debugPrint('❌ 源文件不存在: $sourcePath');
        return false;
      }

      await sourceFile.copy(targetFile.path);
      
      // 更新描述文件
      await _upsertGlobalDescription(safeName, 'Imported LUT');
      
      debugPrint('✅ LUT导入成功: $safeName');
      return true;
    } catch (e) {
      debugPrint('❌ LUT导入失败: $e');
      return false;
    }
  }

  /// 通过内存字节导入新的LUT文件（适配 Android SAF/无物理路径场景）
  static Future<bool> importLutBytes(Uint8List data, String lutName) async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      final String safeName = _sanitizeLutName(lutName);
      final File targetFile = File(p.join(lutsDir.path, '$safeName.cube'));
      await targetFile.writeAsBytes(data, flush: true);

      // 更新描述文件
      await _upsertGlobalDescription(safeName, 'Imported LUT');

      debugPrint('✅ LUT字节导入成功: $safeName');
      return true;
    } catch (e) {
      debugPrint('❌ LUT字节导入失败: $e');
      return false;
    }
  }

  /// 删除LUT文件
  static Future<bool> deleteLut(String lutName) async {
    try {
      // 防止删除默认LUT
      if (lutName == _defaultLutName) {
        debugPrint('❌ 无法删除默认LUT');
        return false;
      }

      final Directory lutsDir = await getUserLutsDirectory();
      final String safeName = _sanitizeLutName(lutName);
      final File lutFile = File(p.join(lutsDir.path, '$safeName.cube'));

      if (await lutFile.exists()) {
        await lutFile.delete();
        await _removeLutDescription(safeName);
        debugPrint('✅ LUT删除成功: $safeName');
        return true;
      } else {
        debugPrint('❌ LUT文件不存在: $safeName');
        return false;
      }
    } catch (e) {
      debugPrint('❌ LUT删除失败: $e');
      return false;
    }
  }

  /// 全局 CSV 中增改一条描述
  static Future<void> _upsertGlobalDescription(String lutName, String description) async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      final File describeFile = File(p.join(lutsDir.path, 'describe.csv'));
      
      List<String> lines = [];
      
      if (await describeFile.exists()) {
        lines = (await describeFile.readAsString()).split('\n');
      } else {
        lines = ['name,description'];
      }

      // 检查是否已存在该LUT的描述
      bool found = false;
      for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
        if (line.split(',').isNotEmpty && line.split(',').first.trim() == lutName) {
          lines[i] = '$lutName,$description';
          found = true;
          break;
        }
      }

      // 如果没找到，添加新行
      if (!found) {
        lines.add('$lutName,$description');
      }

      await describeFile.writeAsString(lines.join('\n'));
    } catch (e) {
      debugPrint('❌ 更新LUT描述失败: $e');
    }
  }

  /// 移除LUT描述
  static Future<void> _removeLutDescription(String lutName) async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      final File describeFile = File(p.join(lutsDir.path, 'describe.csv'));
      
      if (await describeFile.exists()) {
        final List<String> lines = (await describeFile.readAsString()).split('\n');
        lines.removeWhere((line) => line.split(',').isNotEmpty && line.split(',').first.trim() == lutName);
        await describeFile.writeAsString(lines.join('\n'));
      }
    } catch (e) {
      debugPrint('❌ 移除LUT描述失败: $e');
    }
  }

  /// 导出LUT到外部存储
  static Future<String?> exportLut(String lutName) async {
    try {
      final Directory lutsDir = await getUserLutsDirectory();
      final String safeName = _sanitizeLutName(lutName);
      final File lutFile = File(p.join(lutsDir.path, '$safeName.cube'));

      if (!await lutFile.exists()) {
        debugPrint('❌ LUT文件不存在: $lutName');
        return null;
      }

      // 获取外部存储目录
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        debugPrint('❌ 无法获取外部存储目录');
        return null;
      }

      final Directory exportDir = Directory(p.join(externalDir.path, 'LutinLens', 'exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final File exportFile = File(p.join(exportDir.path, '$safeName.cube'));
      await lutFile.copy(exportFile.path);

      debugPrint('✅ LUT导出成功: ${exportFile.path}');
      return exportFile.path;
    } catch (e) {
      debugPrint('❌ LUT导出失败: $e');
      return null;
    }
  }

  /// 重置所有LUT（恢复默认）
  static Future<bool> resetAllLuts() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Directory lutsDir = await getUserLutsDirectory();

      // 删除整个LUT目录
      if (await lutsDir.exists()) {
        await lutsDir.delete(recursive: true);
      }

      // 重置初始化标志
      await prefs.setBool(_lutsInitializedKey, false);

      // 重新初始化
      await initializeLuts();

      debugPrint('✅ LUT重置成功');
      return true;
    } catch (e) {
      debugPrint('❌ LUT重置失败: $e');
      return false;
    }
  }
}

/// 工具：清理传入的 LUT 名，防止路径穿越和非法字符
String _sanitizeLutName(String name) {
  // 只允许字母数字下划线和中划线
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  // 去除潜在的路径片段
  return p.basename(safe);
}

/// LUT文件信息类
class LutFile {
  final String name;
  final String path;
  final String description;
  final bool isDefault;

  LutFile({
    required this.name,
    required this.path,
    required this.description,
    this.isDefault = false,
  });

  @override
  String toString() {
    return 'LutFile{name: $name, path: $path, description: $description, isDefault: $isDefault}';
  }
}
