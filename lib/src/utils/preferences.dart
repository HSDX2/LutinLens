import 'package:camera/camera.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:librecamera/src/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../provider/theme_provider.dart';

class Preferences {
  static SharedPreferences? _preferences;

  static Future init() async =>
      _preferences = await SharedPreferences.getInstance();

  // Language
  static Future setLanguage(String locale) async =>
      await _preferences!.setString(prefLanguage, locale);
  static String getLanguage() => _preferences!.getString(prefLanguage) ?? '';

  // Theme Mode
  static Future setThemeMode(String theme) async =>
      await _preferences!.setString(prefThemeMode, theme);
  static String getThemeMode() =>
      _preferences!.getString(prefThemeMode) ?? CustomThemeMode.system.name;

  // Use Material You
  static Future setUseMaterial3(bool useMaterial3) async =>
      await _preferences!.setBool(prefUseMaterial3, useMaterial3);
  static bool getUseMaterial3() =>
      _preferences!.getBool(prefUseMaterial3) ?? true;

  // Onboarding
  static Future setOnBoardingComplete(bool complete) async =>
      await _preferences!.setBool(prefOnboardingCompleted, complete);
  static bool getOnBoardingComplete() =>
      _preferences!.getBool(prefOnboardingCompleted) ?? false;

  // Save Path
  static Future setSavePath(String path) async =>
      await _preferences!.setString(prefSavePath, path);
  static String getSavePath() =>
      _preferences!.getString(prefSavePath) ?? 'storage/emulated/0/DCIM';

  // Flash Mode
  static Future setFlashMode(String flashMode) async =>
      await _preferences!.setString(prefFlashMode, flashMode);
  static String getFlashMode() =>
      _preferences!.getString(prefFlashMode) ?? FlashMode.off.name;

  // Enable Mode Row
  static Future setEnableModeRow(bool enable) async =>
      await _preferences!.setBool(prefEnableModeRow, enable);
  static bool getEnableModeRow() =>
      _preferences!.getBool(prefEnableModeRow) ?? false;

  // Enable Zoom Slider
  static Future setEnableZoomSlider(bool enable) async =>
      await _preferences!.setBool(prefEnableZoomSlider, enable);
  static bool getEnableZoomSlider() =>
      _preferences!.getBool(prefEnableZoomSlider) ?? false;

  // Enable Exposure Slider
  static Future setEnableExposureSlider(bool enable) async =>
      await _preferences!.setBool(prefEnableExposureSlider, enable);
  static bool getEnableExposureSlider() =>
      _preferences!.getBool(prefEnableExposureSlider) ?? false;

  // Resolution
  static Future setResolution(String resolution) async =>
      await _preferences!.setString(prefResolution, resolution);
  static String getResolution() =>
      _preferences!.getString(prefResolution) ?? ResolutionPreset.max.name;

  // Capture Orientation Locked
  static Future setIsCaptureOrientationLocked(
          bool isCaptureOrientationLocked) async =>
      await _preferences!
          .setBool(prefIsCaptureOrientationLocked, isCaptureOrientationLocked);
  static bool getIsCaptureOrientationLocked() =>
      _preferences!.getBool(prefIsCaptureOrientationLocked) ?? false;

  // Start with rear camera
  static Future setStartWithRearCamera(bool rear) async =>
      await _preferences!.setBool(prefStartWithRearCamera, rear);
  static bool getStartWithRearCamera() =>
      _preferences!.getBool(prefStartWithRearCamera) ?? true;

  // Flip front camera photos horizontally
  static Future setFlipFrontCameraPhoto(bool flip) async =>
      await _preferences!.setBool(prefFlipFrontCameraPhoto, flip);
  static bool getFlipFrontCameraPhoto() =>
      _preferences!.getBool(prefFlipFrontCameraPhoto) ?? false;

  // Enable Audio
  static Future setEnableAudio(bool enableAudio) async =>
      await _preferences!.setBool(prefEnableAudio, enableAudio);
  static bool getEnableAudio() =>
      _preferences!.getBool(prefEnableAudio) ?? true;

  // Compress Image
  static Future setCompressFormat(String compressFormat) async =>
      await _preferences!.setString(prefCompressFormat, compressFormat);
  static String getCompressFormat() =>
      _preferences!.getString(prefCompressFormat) ?? CompressFormat.jpeg.name;

  // Compress Image
  static Future setCompressQuality(int compressQuality) async =>
      await _preferences!.setInt(prefCompressQuality, compressQuality);
  static int getCompressQuality() =>
      _preferences!.getInt(prefCompressQuality) ?? 95;

  // Keep Exif
  static Future setKeepEXIFMetadata(bool keepEXIFMetadata) async =>
      await _preferences!.setBool(prefKeepEXIFMetadata, keepEXIFMetadata);
  static bool getKeepEXIFMetadata() =>
      _preferences!.getBool(prefKeepEXIFMetadata) ?? false;

  // Capture Orientation Locked
  static Future setShowNavigationBar(bool showNavigationBar) async =>
      await _preferences!.setBool(prefShowNavigationBar, showNavigationBar);
  static bool getShowNavigationBar() =>
      _preferences!.getBool(prefShowNavigationBar) ?? false;

  // Timer
  static Future setTimerDuration(int durationInSeconds) async =>
      await _preferences!.setInt(prefTimerDuration, durationInSeconds);
  static int getTimerDuration() => _preferences!.getInt(prefTimerDuration) ?? 0;

  // Compress Image
  static Future setDisableShutterSound(bool disable) async =>
      await _preferences!.setBool(prefDisableShutterSound, disable);
  static bool getDisableShutterSound() =>
      _preferences!.getBool(prefDisableShutterSound) ?? false;

  // Maximum Screen Brightness
  static Future setMaximumScreenBrightness(bool enable) async =>
      await _preferences!.setBool(prefMaximumScreenBrightness, enable);
  static bool getMaximumScreenBrightness() =>
      _preferences!.getBool(prefMaximumScreenBrightness) ?? false;

  // Left Handed Mode
  static Future setLeftHandedMode(bool enable) async =>
      await _preferences!.setBool(prefLeftHandedMode, enable);
  static bool getLeftHandedMode() =>
      _preferences!.getBool(prefLeftHandedMode) ?? false;

  // Left Handed Mode
  static Future setCaptureAtVolumePress(bool enable) async =>
      await _preferences!.setBool(prefCaptureAtVolumePress, enable);
  static bool getCaptureAtVolumePress() =>
      _preferences!.getBool(prefCaptureAtVolumePress) ?? true;

  // LUT Selection
  static Future setSelectedLutName(String lutName) async =>
      await _preferences!.setString(prefSelectedLutName, lutName);
  static String getSelectedLutName() =>
      _preferences!.getString(prefSelectedLutName) ?? '';

  static Future setSelectedLutPath(String lutPath) async =>
      await _preferences!.setString(prefSelectedLutPath, lutPath);
  static String getSelectedLutPath() =>
      _preferences!.getString(prefSelectedLutPath) ?? '';

  // LUT Mix Strength
  static Future setLutMixStrength(double value) async =>
      await _preferences!.setDouble(prefLutMixStrength, value);
  static double getLutMixStrength() =>
      _preferences!.getDouble(prefLutMixStrength) ?? 1.0;

  // LUT Enabled
  static Future setLutEnabled(bool enabled) async =>
      await _preferences!.setBool(prefLutEnabled, enabled);
  static bool getLutEnabled() =>
      _preferences!.getBool(prefLutEnabled) ?? true;

  // AI图像上传URL
  static Future setAiImageUploadUrl(String url) async =>
      await _preferences!.setString(prefAiImageUploadUrl, url);
  static String getAiImageUploadUrl() =>
      _preferences!.getString(prefAiImageUploadUrl) ?? 'http://ryanssite.icu:8003/static';

  // AI LUT建议URL
  static Future setAiLutSuggestionUrl(String url) async =>
      await _preferences!.setString(prefAiLutSuggestionUrl, url);
  static String getAiLutSuggestionUrl() =>
      _preferences!.getString(prefAiLutSuggestionUrl) ?? 'http://ryanssite.icu:8000/generate';

  // AI取景建议URL
  static Future setAiFramingSuggestionUrl(String url) async =>
      await _preferences!.setString(prefAiFramingSuggestionUrl, url);
  static String getAiFramingSuggestionUrl() =>
      _preferences!.getString(prefAiFramingSuggestionUrl) ?? 'http://ryanssite.icu:8001/generate';

  // AI服务器URL (保留用于向后兼容)
  static Future setAiServerUrl(String url) async =>
      await _preferences!.setString(prefAiServerUrl, url);
  static String getAiServerUrl() =>
      _preferences!.getString(prefAiServerUrl) ?? '';

  // AI建议功能是否启用
  static Future setAiSuggestionEnabled(bool enabled) async =>
      await _preferences!.setBool(prefAiSuggestionEnabled, enabled);
  static bool getAiSuggestionEnabled() =>
      _preferences!.getBool(prefAiSuggestionEnabled) ?? false;

  // AI轮询频率（秒）
  static Future setAiPollingInterval(int seconds) async =>
      await _preferences!.setInt(prefAiPollingInterval, seconds);
  static int getAiPollingInterval() =>
      _preferences!.getInt(prefAiPollingInterval) ?? 5;

  // AI组件位置
  static Future setAiWidgetX(double x) async =>
      await _preferences!.setDouble(prefAiWidgetX, x);
  static double getAiWidgetX() =>
      _preferences!.getDouble(prefAiWidgetX) ?? 40.0;

  static Future setAiWidgetY(double y) async =>
      await _preferences!.setDouble(prefAiWidgetY, y);
  static double getAiWidgetY() =>
      _preferences!.getDouble(prefAiWidgetY) ?? 40.0;
}
