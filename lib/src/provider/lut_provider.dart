import 'package:flutter/foundation.dart';
import 'package:librecamera/src/utils/lut_manager.dart';
import 'package:librecamera/src/lut/lut_preview_manager.dart';
import 'package:librecamera/src/utils/preferences.dart';

/// LUT状态管理Provider
class LutProvider extends ChangeNotifier {
  List<LutFile> _luts = [];
  LutFile? _currentLut;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<LutFile> get luts => _luts;
  LutFile? get currentLut => _currentLut;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLuts => _luts.isNotEmpty;

  /// 初始化LUT系统
  Future<void> initializeLuts() async {
    _setLoading(true);
    _clearError();

    try {
      await LutManager.initializeLuts();
      await loadLuts();
      
      // 恢复上次选择的LUT
      await _restoreSelectedLut();
    } catch (e) {
      _setError('初始化LUT失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 加载所有LUT文件
  Future<void> loadLuts() async {
    try {
      _luts = await LutManager.getAllLuts();
      
      // 如果当前没有选择LUT，选择默认的
      if (_currentLut == null && _luts.isNotEmpty) {
        _currentLut = _luts.firstWhere(
          (lut) => lut.isDefault,
          orElse: () => _luts.first,
        );
      }
      
      notifyListeners();
    } catch (e) {
      _setError('加载LUT列表失败: $e');
    }
  }

  /// 选择LUT
  Future<void> selectLut(LutFile lut) async {
    if (_currentLut != lut) {
      _currentLut = lut;
      
      // 同步更新LutPreviewManager时正确处理图像流
      try {
        // 先停止图像流以避免在切换LUT时出现冲突
        await LutPreviewManager.instance.stopImageStream();
        
        // 设置新的LUT
        await LutPreviewManager.instance.setCurrentLut(lut.path);
        
        // 延迟恢复图像流，确保LUT切换完成
        Future.delayed(const Duration(milliseconds: 200), () {
          LutPreviewManager.instance.resumeImageStream();
        });
        
        // 持久化选择状态
        await _saveSelectedLut(lut);
      } catch (e) {
        debugPrint('更新LUT预览失败: $e');
        // 即使出错也要尝试恢复图像流
        LutPreviewManager.instance.resumeImageStream();
      }
      
      notifyListeners();
    }
  }

  /// 通过名称选择LUT
  Future<void> selectLutByName(String lutName) async {
    final lut = _luts.where((l) => l.name == lutName).firstOrNull;
    if (lut != null) {
      await selectLut(lut);
    } else {
      debugPrint('警告: 找不到名为 "$lutName" 的LUT');
    }
  }

  /// 导入LUT文件
  Future<bool> importLut(String sourcePath, String lutName) async {
    _setLoading(true);
    _clearError();

    try {
      final bool success = await LutManager.importLut(sourcePath, lutName);
      if (success) {
        await loadLuts(); // 重新加载列表
        
        // 如果导入成功，自动选择新导入的LUT
        final importedLut = _luts.where((lut) => lut.name == lutName).firstOrNull;
        if (importedLut != null) {
          await selectLut(importedLut);
        }
      } else {
        _setError('导入LUT失败');
      }
      return success;
    } catch (e) {
      _setError('导入LUT时发生错误: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 通过字节导入LUT文件（适配无本地文件路径场景）
  Future<bool> importLutBytes(Uint8List data, String lutName) async {
    _setLoading(true);
    _clearError();

    try {
      final bool success = await LutManager.importLutBytes(data, lutName);
      if (success) {
        await loadLuts();
        final importedLut = _luts.where((lut) => lut.name == lutName).firstOrNull;
        if (importedLut != null) {
          await selectLut(importedLut);
        }
      } else {
        _setError('导入LUT失败');
      }
      return success;
    } catch (e) {
      _setError('导入LUT时发生错误: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 删除LUT文件
  Future<bool> deleteLut(String lutName) async {
    _setLoading(true);
    _clearError();

    try {
      final bool success = await LutManager.deleteLut(lutName);
      if (success) {
        // 如果删除的是当前选择的LUT，切换到默认LUT
        if (_currentLut?.name == lutName) {
          final defaultLut = _luts.firstWhere(
            (lut) => lut.isDefault,
            orElse: () => _luts.isNotEmpty ? _luts.first : LutFile(name: 'None', path: '', description: ''),
          );
          if (defaultLut.name.isNotEmpty) {
            // 使用selectLut方法确保正确的流处理
            await selectLut(defaultLut);
          } else {
            _currentLut = null;
            // 先停止图像流再禁用LUT预览
            await LutPreviewManager.instance.stopImageStream();
            LutPreviewManager.instance.setEnabled(false);
          }
        }
        await loadLuts(); // 重新加载列表
      } else {
        _setError('删除LUT失败');
      }
      return success;
    } catch (e) {
      _setError('删除LUT时发生错误: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 导出LUT文件
  Future<String?> exportLut(String lutName) async {
    _setLoading(true);
    _clearError();

    try {
      final String? exportPath = await LutManager.exportLut(lutName);
      if (exportPath == null) {
        _setError('导出LUT失败');
      }
      return exportPath;
    } catch (e) {
      _setError('导出LUT时发生错误: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// 重置所有LUT
  Future<bool> resetAllLuts() async {
    _setLoading(true);
    _clearError();

    try {
      final bool success = await LutManager.resetAllLuts();
      if (success) {
        await loadLuts(); // 重新加载列表
      } else {
        _setError('重置LUT失败');
      }
      return success;
    } catch (e) {
      _setError('重置LUT时发生错误: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 获取LUT文件路径（用于图像处理）
  String? getCurrentLutPath() {
    return _currentLut?.path;
  }

  /// 检查是否有可用的LUT
  bool hasLutWithName(String name) {
    return _luts.any((lut) => lut.name == name);
  }

  /// 获取默认LUT
  LutFile? getDefaultLut() {
    return _luts.where((lut) => lut.isDefault).firstOrNull;
  }

  // 私有辅助方法
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
    
    // 自动清除错误信息（3秒后）
    Future.delayed(const Duration(seconds: 3), () {
      if (_error == error) {
        _clearError();
      }
    });
  }

  void _clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// 保存选择的LUT到持久化存储
  Future<void> _saveSelectedLut(LutFile lut) async {
    try {
      await Preferences.setSelectedLutName(lut.name);
      await Preferences.setSelectedLutPath(lut.path);
    } catch (e) {
      debugPrint('保存LUT选择失败: $e');
    }
  }

  /// 从持久化存储恢复选择的LUT
  Future<void> _restoreSelectedLut() async {
    try {
      final lutName = Preferences.getSelectedLutName();
      if (lutName.isNotEmpty && _luts.isNotEmpty) {
        final savedLut = _luts.where((lut) => lut.name == lutName).firstOrNull;
        if (savedLut != null) {
          _currentLut = savedLut;
          // 在初始化时直接设置LUT，不需要停止/恢复流
          await LutPreviewManager.instance.setCurrentLut(savedLut.path);
          notifyListeners();
          return;
        }
      }
      
      // 如果没有保存的LUT或找不到，选择默认LUT
      if (_currentLut == null && _luts.isNotEmpty) {
        final defaultLut = _luts.firstWhere(
          (lut) => lut.isDefault,
          orElse: () => _luts.first,
        );
        // 在初始化时直接设置LUT，不需要流处理
        _currentLut = defaultLut;
        await LutPreviewManager.instance.setCurrentLut(defaultLut.path);
        await _saveSelectedLut(defaultLut);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('恢复LUT选择失败: $e');
    }
  }

  /// 清除所有状态
  void clear() {
    _luts.clear();
    _currentLut = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// 处理摄像头控制器变化（在切换摄像头时调用）
  /// 这个方法只处理LUT状态同步，不处理图像流
  Future<void> onCameraControllerChanged() async {
    try {
      // 如果有当前LUT，重新设置以确保与新控制器兼容
      if (_currentLut != null) {
        await LutPreviewManager.instance.setCurrentLut(_currentLut!.path);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('处理摄像头控制器变化时出错: $e');
    }
  }
}

// 扩展方法，为List添加firstOrNull方法（如果不存在的话）
extension ListExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
