import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:librecamera/l10n/l10n.dart';
import 'package:librecamera/src/pages/onboarding_page.dart';
import 'package:librecamera/src/provider/locale_provider.dart';
import 'package:librecamera/src/provider/theme_provider.dart';
import 'package:librecamera/src/utils/preferences.dart';
import 'package:librecamera/src/widgets/resolution.dart';

import '../../l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
// Removed: unused color_compat import

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    Key? key,
    required this.onPressed,
    required this.controller,
  }) : super(key: key);

  final void Function()? onPressed;
  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      disabledColor: Colors.white24,
      onPressed: onPressed,
      icon: const Icon(Icons.settings),
      tooltip: AppLocalizations.of(context)!.settings,
      iconSize: 35,
      color: Colors.white,
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    Key? key,
    required this.controller,
    required this.onNewCameraSelected,
  }) : super(key: key);

  final CameraController? controller;
  final Function(CameraDescription) onNewCameraSelected;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String currentSavePath = Preferences.getSavePath();
  bool isMoreOptions = false;

  ScrollController listScrollController = ScrollController();

  //Compress quality slider
  double value = Preferences.getCompressQuality().toDouble();

  TextStyle style = const TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.bold,
  );

  Widget _aiSuggestionEnabledTile() {
    return SwitchListTile(
      title: const Text('AI智能建议'),
      subtitle: const Text('开启后，摄像机会定期向服务器发送预览图像以获取拍摄建议'),
      value: Preferences.getAiSuggestionEnabled(),
      onChanged: (value) async {
        await Preferences.setAiSuggestionEnabled(value);
        setState(() {});
      },
    );
  }

  Widget _aiImageUploadUrlTile() {
    return ListTile(
      title: const Text('图床服务'),
      subtitle: Text(
        Preferences.getAiImageUploadUrl().isEmpty 
          ? '未设置图片上传服务' 
          : Preferences.getAiImageUploadUrl(),
      ),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        _showAiImageUploadUrlDialog();
      },
    );
  }

  Widget _aiLutSuggestionUrlTile() {
    return ListTile(
      title: const Text('LUT建议服务'),
      subtitle: Text(
        Preferences.getAiLutSuggestionUrl().isEmpty 
          ? '未设置LUT建议API' 
          : Preferences.getAiLutSuggestionUrl(),
      ),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        _showAiLutSuggestionUrlDialog();
      },
    );
  }

  Widget _aiFramingSuggestionUrlTile() {
    return ListTile(
      title: const Text('取景建议服务'),
      subtitle: Text(
        Preferences.getAiFramingSuggestionUrl().isEmpty 
          ? '未设置取景建议API' 
          : Preferences.getAiFramingSuggestionUrl(),
      ),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        _showAiFramingSuggestionUrlDialog();
      },
    );
  }

  Widget _aiPollingIntervalTile() {
    return ListTile(
      title: const Text('轮询频率'),
      subtitle: Text('每 ${Preferences.getAiPollingInterval()} 秒获取一次AI建议'),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        _showAiPollingIntervalDialog();
      },
    );
  }

  void _showAiImageUploadUrlDialog() {
    final TextEditingController controller = TextEditingController(
      text: Preferences.getAiImageUploadUrl(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置AI图像上传服务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '图床服务地址（用于存储上传的图片）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'http://ryanssite.icu:8003/static',
                labelText: '图床服务地址',
                border: OutlineInputBorder(),
                helperText: '图片将通过PUT请求上传到此地址',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              String url = controller.text.trim();
              if (url.isNotEmpty && !url.startsWith('http')) {
                url = 'http://$url';
              }
              await Preferences.setAiImageUploadUrl(url);
              if (!mounted) return;
              setState(() {});
              navigator.pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAiLutSuggestionUrlDialog() {
    final TextEditingController controller = TextEditingController(
      text: Preferences.getAiLutSuggestionUrl(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置LUT建议服务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LUT建议API服务地址',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'http://ryanssite.icu:8000/single/generate',
                labelText: 'LUT建议API地址',
                border: OutlineInputBorder(),
                helperText: '返回推荐的LUT编号',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              String url = controller.text.trim();
              if (url.isNotEmpty && !url.startsWith('http')) {
                url = 'http://$url';
              }
              await Preferences.setAiLutSuggestionUrl(url);
              if (!mounted) return;
              setState(() {});
              navigator.pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAiFramingSuggestionUrlDialog() {
    final TextEditingController controller = TextEditingController(
      text: Preferences.getAiFramingSuggestionUrl(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置取景建议服务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '取景建议API服务地址',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'http://ryanssite.icu:8001/single/generate',
                labelText: '取景建议API地址',
                border: OutlineInputBorder(),
                helperText: '返回拍摄构图建议',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              String url = controller.text.trim();
              if (url.isNotEmpty && !url.startsWith('http')) {
                url = 'http://$url';
              }
              await Preferences.setAiFramingSuggestionUrl(url);
              if (!mounted) return;
              setState(() {});
              navigator.pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAiPollingIntervalDialog() {
    final TextEditingController controller = TextEditingController(
      text: Preferences.getAiPollingInterval().toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置轮询频率'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI建议获取频率设置，建议3-10秒之间',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '5',
                labelText: '轮询间隔（秒）',
                border: OutlineInputBorder(),
                helperText: '间隔时间越短，响应越快，但耗电量更大',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final intervalStr = controller.text.trim();
              if (intervalStr.isNotEmpty) {
                final interval = int.tryParse(intervalStr) ?? 5;
                // 限制在1-60秒范围内
                final clampedInterval = interval.clamp(1, 60);
                await Preferences.setAiPollingInterval(clampedInterval);
                if (!mounted) return;
                setState(() {});
                navigator.pop();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }


  Widget _aboutListTile({String? version}) {
    void launchGitHubURL() async {
      var url = Uri.parse('https://github.com/iakmds/librecamera');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }

    return AboutListTile(
      icon: const Icon(Icons.info),
      applicationName: 'Libre Camera',
      applicationVersion: version != null
          ? AppLocalizations.of(context)!.version(version)
          : null,
      applicationIcon: const Image(
        image: AssetImage('assets/images/icon.png'),
        width: 50,
        height: 50,
      ),
      applicationLegalese: 'GNU Public License v3',
      aboutBoxChildren: [
        Text(AppLocalizations.of(context)!.license),
        const Divider(),
        TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          onPressed: launchGitHubURL,
          label: SelectableText(
            'https://github.com/iakmds/librecamera',
            style: const TextStyle(
              color: Colors.blue,
            ),
            onTap: launchGitHubURL,
          ),
        ),
      ],
    );
  }

  Widget _aboutTile() {
    return FutureBuilder(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        return _aboutListTile(
            version: snapshot.hasData
                ? snapshot.data!.version
                : null);
      },
    );
  }

  Widget _onboardingScreenTile() {
    return ListTile(
      title: Text(AppLocalizations.of(context)!.onboardingScreen),
      subtitle: Text(
        AppLocalizations.of(context)!.onboardingScreen_description,
      ),
      trailing: const Icon(Icons.logout),
      onTap: () async {
        Preferences.setOnBoardingComplete(false);

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OnboardingPage()),
        );
      },
    );
  }

  Widget _captureOrientationLockedTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.lockCaptureOrientation),
      subtitle: Text(
          AppLocalizations.of(context)!.lockCaptureOrientation_description),
      value: Preferences.getIsCaptureOrientationLocked(),
      onChanged: (value) async {
        Preferences.setIsCaptureOrientationLocked(value);
        setState(() {});
      },
    );
  }

  Widget _showNavigationBarTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.showNavigationBar),
      subtitle:
          Text(AppLocalizations.of(context)!.showNavigationBar_description),
      value: Preferences.getShowNavigationBar(),
      onChanged: (value) async {
        await Preferences.setShowNavigationBar(value);
        setState(() {});
      },
    );
  }

  Widget _showMoreTile() {
    return InkWell(
      onTap: () => setState(() {
        isMoreOptions = !isMoreOptions;

        SchedulerBinding.instance.addPostFrameCallback((_) {
          listScrollController.animateTo(
            listScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        });
      }),
      child: ListTile(
        title: Text(
          isMoreOptions
              ? AppLocalizations.of(context)!.less
              : AppLocalizations.of(context)!.more,
          style: style,
        ),
        trailing: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            isMoreOptions ? Icons.expand_less : Icons.expand_more,
            size: 35,
          ),
        ),
      ),
    );
  }

  Widget _savePathTile() {
    return ListTile(
      title: Text(AppLocalizations.of(context)!.savePath),
      subtitle: Text(
        AppLocalizations.of(context)!.savePath_description(currentSavePath),
      ),
      trailing: ElevatedButton(
          onPressed: () async {
            String? selectedDirectory =
                await FilePicker.platform.getDirectoryPath();

            if (selectedDirectory == null) {
              // User canceled the picker
            }

            Preferences.setSavePath(
                selectedDirectory ?? Preferences.getSavePath());

            currentSavePath = Preferences.getSavePath();
            setState(() {});
          },
          child: Text(AppLocalizations.of(context)!.choosePath)),
    );
  }

  Widget _keepEXIFMetadataTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.keepEXIFMetadata),
      subtitle:
          Text(AppLocalizations.of(context)!.keepEXIFMetadata_description),
      value: Preferences.getKeepEXIFMetadata(),
      onChanged: (value) async {
        await Preferences.setKeepEXIFMetadata(value);
        setState(() {});
      },
    );
  }

  // 已移除：图片格式切换（固定 JPEG）

  Widget _imageCompressionTile() {
    return ListTile(
      title: Text(AppLocalizations.of(context)!.imageCompressionQuality),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!
              .imageCompressionQuality_description),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 0),
            child: Row(
              children: [
                const Text('10', style: TextStyle(fontWeight: FontWeight.bold)),
                Flexible(
                  child: Slider(
                    value: value,
                    onChanged: (value) => setState(() => this.value = value),
                    onChangeEnd: (value) {
                      Preferences.setCompressQuality(value.toInt());
                    },
                    min: 10,
                    max: 100,
                    label: value.round().toString(),
                    //label: Preferences.getCompressQuality().round().toString(),
                    divisions: 90,
                  ),
                ),
                const Text('100',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _disableShutterSoundTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.shutterSound),
      subtitle: Text(AppLocalizations.of(context)!.shutterSound_description),
      value: Preferences.getDisableShutterSound(),
      onChanged: (value) async {
        await Preferences.setDisableShutterSound(value);
        setState(() {});
      },
    );
  }

  Widget _captureAtVolumePressTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.captureAtVolumePress),
      subtitle:
          Text(AppLocalizations.of(context)!.captureAtVolumePress_description),
      value: Preferences.getCaptureAtVolumePress(),
      onChanged: (value) async {
        await Preferences.setCaptureAtVolumePress(value);
        setState(() {});
      },
    );
  }

  Widget _disableAudioTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.disableAudio),
      subtitle: Text(AppLocalizations.of(context)!.disableAudio_description),
      value: !Preferences.getEnableAudio(),
      onChanged: (value) async {
        await Preferences.setEnableAudio(!value);
        setState(() {});
      },
    );
  }

  Widget _enableModeRow() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.enableModeRow),
      subtitle: Text(AppLocalizations.of(context)!.enableModeRow_description),
      value: Preferences.getEnableModeRow(),
      onChanged: (value) async {
        await Preferences.setEnableModeRow(value);
        setState(() {});
      },
    );
  }

  Widget _startWithFrontCameraTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.startWithFrontCamera),
      subtitle:
          Text(AppLocalizations.of(context)!.startWithFrontCamera_description),
      value: !Preferences.getStartWithRearCamera(),
      onChanged: (value) async {
        await Preferences.setStartWithRearCamera(!value);
        setState(() {});
      },
    );
  }

  Widget _flipPhotosFrontCameraTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.flipPhotosFrontCamera),
      subtitle:
          Text(AppLocalizations.of(context)!.flipPhotosFrontCamera_description),
      value: !Preferences.getFlipFrontCameraPhoto(),
      onChanged: (value) async {
        await Preferences.setFlipFrontCameraPhoto(!value);
        setState(() {});
      },
    );
  }

  Widget _resolutionTile() {
    return ListTile(
      title: Text(AppLocalizations.of(context)!.resolution),
      subtitle: Text(AppLocalizations.of(context)!.resolution_description),
      trailing: const ResolutionButton(enabled: true),
    );
  }

  Widget _enableExposureSliderTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.enableExposureSlider),
      subtitle:
          Text(AppLocalizations.of(context)!.enableExposureSlider_description),
      value: Preferences.getEnableExposureSlider(),
      onChanged: (value) async {
        await Preferences.setEnableExposureSlider(value);
        setState(() {});
      },
    );
  }

  Widget _enableZoomSliderTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.enableZoomSlider),
      subtitle:
          Text(AppLocalizations.of(context)!.enableZoomSlider_description),
      value: Preferences.getEnableZoomSlider(),
      onChanged: (value) async {
        await Preferences.setEnableZoomSlider(value);
        setState(() {});
      },
    );
  }

  Widget _themeTile() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return ListTile(
      title: Text(AppLocalizations.of(context)!.theme),
      subtitle: Text(AppLocalizations.of(context)!.theme_description),
      trailing: DropdownButton(
        icon: Preferences.getThemeMode() == CustomThemeMode.system.name
            ? const Icon(Icons.settings_display)
            : Preferences.getThemeMode() == CustomThemeMode.light.name
                ? const Icon(Icons.light_mode)
                : const Icon(Icons.dark_mode),
        value: CustomThemeMode.values.byName(Preferences.getThemeMode()),
        items: [
          DropdownMenuItem(
            value: CustomThemeMode.system,
            onTap: () => themeProvider.setTheme(CustomThemeMode.system),
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(AppLocalizations.of(context)!.themeSystem),
            ),
          ),
          DropdownMenuItem(
            value: CustomThemeMode.light,
            onTap: () => themeProvider.setTheme(CustomThemeMode.light),
            child: Text(AppLocalizations.of(context)!.themeLight),
          ),
          DropdownMenuItem(
            value: CustomThemeMode.dark,
            onTap: () => themeProvider.setTheme(CustomThemeMode.dark),
            child: Text(AppLocalizations.of(context)!.themeDark),
          ),
          DropdownMenuItem(
            value: CustomThemeMode.black,
            onTap: () => themeProvider.setTheme(CustomThemeMode.black),
            child: Text(AppLocalizations.of(context)!.themeBlack),
          ),
        ],
        onChanged: (_) {},
      ),
    );
  }

  Widget _maximumScreenBrightnessTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.enableMaximumScreenBrightness),
      subtitle: Text(AppLocalizations.of(context)!
          .enableMaximumScreenBrightness_description),
      value: Preferences.getMaximumScreenBrightness(),
      onChanged: (value) async {
        await Preferences.setMaximumScreenBrightness(value);
        Preferences.getMaximumScreenBrightness()
            ? await ScreenBrightness().setScreenBrightness(1.0)
            : await ScreenBrightness().resetScreenBrightness();
        setState(() {});
      },
    );
  }

  Widget _leftHandedModeTile() {
    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.leftHandedMode),
      subtitle: Text(AppLocalizations.of(context)!.leftHandedMode_description),
      value: Preferences.getLeftHandedMode(),
      onChanged: (value) async {
        await Preferences.setLeftHandedMode(value);
        setState(() {});
      },
    );
  }

  Widget _languageTile() {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);

    return ListTile(
      title: Text(AppLocalizations.of(context)!.language),
      subtitle: Text(AppLocalizations.of(context)!.language_description),
      trailing: DropdownButton<String>(
        icon: const Icon(Icons.language),
        value: Preferences.getLanguage().isNotEmpty
            ? Preferences.getLanguage()
            : null,
        items: Localization.supportedLocales.map(
          (locale) {
            final name = Localization.getName(locale);

            return DropdownMenuItem(
              value: locale.toLanguageTag(),
              onTap: () => localeProvider.setLocale(locale),
              child: Text(name),
            );
          },
        ).toList()
          ..insert(
            0,
            DropdownMenuItem<String>(
              value: null,
              onTap: () => localeProvider.clearLocale(),
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(AppLocalizations.of(context)!.systemLanguage),
              ),
            ),
          ),
        onChanged: (_) {},
      ),
    );
  }

  Widget _useMaterial3Tile() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return SwitchListTile(
      title: Text(AppLocalizations.of(context)!.useMaterialYou),
      subtitle: Text(AppLocalizations.of(context)!.useMaterialYou_description),
      value: Preferences.getUseMaterial3(),
      onChanged: (value) {
        Preferences.setUseMaterial3(value);
        themeProvider.setTheme(themeProvider.themeMode());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          await widget.onNewCameraSelected(widget.controller!.description);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: (() async {
              await widget.onNewCameraSelected(widget.controller!.description);
              if (!mounted) return;
              if (context.mounted) {
                Navigator.pop(context);
              }
            }),
            tooltip: AppLocalizations.of(context)!.back,
          ),
          title: Text(AppLocalizations.of(context)!.settings),
          scrolledUnderElevation: 2,
        ),
        body: ListView(
          controller: listScrollController,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          children: <Widget>[
            // 应用设置卡片
            _buildSettingsCard(
              title: AppLocalizations.of(context)!.appSettings,
              children: [
                _languageTile(),
                _themeTile(),
                _maximumScreenBrightnessTile(),
                _leftHandedModeTile(),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // UI设置卡片
            _buildSettingsCard(
              title: '界面设置',
              children: [
                _enableModeRow(),
                _enableZoomSliderTile(),
                _enableExposureSliderTile(),
              ],
            ),

            const SizedBox(height: 16),

            // 相机行为设置卡片
            _buildSettingsCard(
              title: AppLocalizations.of(context)!.cameraBehaviour,
              children: [
                _resolutionTile(),
                _captureAtVolumePressTile(),
                _disableShutterSoundTile(),
                _startWithFrontCameraTile(),
                _disableAudioTile(),
              ],
            ),

            const SizedBox(height: 16),

            // 保存设置卡片
            _buildSettingsCard(
              title: AppLocalizations.of(context)!.saving,
              children: [
                _flipPhotosFrontCameraTile(),
                _imageCompressionTile(),
                _keepEXIFMetadataTile(),
                _savePathTile(),
              ],
            ),

            const SizedBox(height: 16),

            // AI设置卡片
            _buildSettingsCard(
              title: 'AI设置',
              children: [
                _aiSuggestionEnabledTile(),
                _aiPollingIntervalTile(),
                _aiImageUploadUrlTile(),
                _aiLutSuggestionUrlTile(),
                _aiFramingSuggestionUrlTile(),
              ],
            ),

            const SizedBox(height: 16),

            // 更多设置卡片
            _buildSettingsCard(
              title: '更多设置',
              children: [
                _showMoreTile(),
                if (isMoreOptions) ..._buildMoreOptions(),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children.map((child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: child,
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _buildMoreOptions() {
    return [
      _captureOrientationLockedTile(),
      _showNavigationBarTile(),
      _onboardingScreenTile(),
      _buildGitHubTile(),
      _aboutTile(),
    ];
  }

  Widget _buildGitHubTile() {
    void launchGitHubURL() async {
      var url = Uri.parse('https://github.com/iakmds/librecamera');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }

    return ListTile(
      leading: const Icon(Icons.code),
      title: const Text('GitHub'),
      subtitle: const Text('查看源代码'),
      trailing: const Icon(Icons.open_in_new),
      onTap: launchGitHubURL,
    );
  }
}
