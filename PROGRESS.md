# LutinLens 项目进度与后续工作

> 最后更新：2026-09-19

## 项目组成（两个 git 仓库）

| 仓库 | 说明 | clone 地址 |
|---|---|---|
| **App（相机客户端）** | Flutter，基于 LibreCamera，本仓库 | `https://github.com/HSDX2/LutinLens.git` |
| **服务端（AI 后端）** | Python + NVIDIA NeMo Agent Toolkit | `https://github.com/HSDX2/lutinlens_server.git` |

## 已完成

1. **服务端 AI 已从「阿里云百炼 / 通义千问」切换到 DeepSeek**：
   - `base_url`：`https://api.deepseek.com`
   - 文本模型：`deepseek-v4-flash`（ReAct Agent 主体 + LUT 选择）
   - 视觉模型：`deepseek-v4-flash-vision-exp`（图片内容/亮度识别 + 多图构图建议）
   - 环境变量：`DEEPSEEK_API_KEY`（原来是 `DASHSCOPE_API_KEY`）
2. **App 已用 GitHub Actions 云构建出 release APK**（约 57MB，含 `arm64-v8a` + `armeabi-v7a`）。

## 当前状态

- App：可打包安装；本地相机 + GPU LUT 滤镜可独立使用；**AI 功能依赖服务端**。
- 服务端：代码已改好 DeepSeek，**尚未部署运行**。
- App ↔ 服务端：**尚未联调**。

## App 构建要点（重要，务必照此配套）

- Flutter **3.35.0**（代码用了 `ShowValueIndicator.onDrag`，需 ≥3.35；且 3.35 最低只要求 Gradle 8.3）。
- 项目自带 Gradle **8.9** + AGP **8.6.0** + JDK 17 + compileSdk/targetSdk 36 + minSdk 24。
- `android/gradle.properties` 的 `org.gradle.jvmargs` 已调到 `-Xmx4g`（原 1.5G 会让 Jetifier 转 Flutter 引擎 jar 时 OOM）。
- 构建命令：`flutter build apk --release`，产物在 `build/app/outputs/flutter-apk/app-release.apk`。
- CI：`.github/workflows/build-apk.yml`（GitHub Actions，x64 runner）。
- ⚠️ 注意：release 目前用 **debug 签名**（`android/app/build.gradle` 里 `signingConfig signingConfigs.debug`），能装能用，但不能上架、不能覆盖正式版。

## 服务端部署要点

- 环境：Python 3.11~3.12 + NeMo Agent Toolkit（**不需要 GPU**，走 DeepSeek 云端 API）。Windows 必须用 **WSL2 或 Docker**（NAT 官方不支持原生 Windows）。
- 步骤：`git clone` 服务端 → 装 NAT + `pip install ./tools/*` → `export DEEPSEEK_API_KEY="sk-..."` → `nat serve --workflow xxx`。
- 三个工作流对应 App 的三个请求：`lut_advisor`（LUT 推荐）、`framing_advisor`（构图，多图，务必用 `deepseek-v4-flash-vision-exp`）、s3/图床（存照片）。

## App ↔ 服务端对接（App 设置里要填 3 个 HTTP 地址）

App 并非直连 MCP，而是 3 个 HTTP 端点（见 `lib/src/services/ai_suggestion_service.dart`）：
1. **图床上传**：`PUT {uploadUrl}/{uuid}.jpg`（multipart，字段 `file`）→ 返回图片 URL
2. **LUT 建议**：`POST {lutUrl}`（约 8000）body `{"input_message": "图片URL"}` → `{"value": "LUT编号"}`
3. **取景建议**：`POST {framingUrl}`（约 8001）body `{"session_id":..., "img":"data:image/jpeg;base64,..."}` → `{"suggestion":"...","ready_to_shoot":0|1}`

## 后续待办（下一步做什么）

1. **部署服务端**（Linux/macOS 首选，Win10 用 WSL2/Docker），配好 `DEEPSEEK_API_KEY`。
2. 启动三个服务，拿到端口。
3. **App 设置里填上三个服务地址**，联调。
4. **验证 DeepSeek 多图能力**：重点实测 `framing_advisor` 一次传多张历史图 + 严格 JSON 输出的稳定性（这是换模型后最需要验证的点）。
5. （可选）App 正式签名 keystore，替换 debug 签名。
6. （可选）服务端可接 Web UI（原仓库有 `external/nat-ui` 子模块，未拉取，可选）。

## 补充文档

- **App 正式签名**：见本仓库 `SIGNING.md`
- **服务端 WSL2 部署**：见服务端仓库 `DEPLOY_WSL2.md`