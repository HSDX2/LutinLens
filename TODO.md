# LutinLens TODO

This document tracks prioritized, actionable work items across stability, performance, architecture, tests/CI, and docs. Use GitHub issues for execution details and link items back here. Check boxes when done.

## Conventions
- [ ] Item: concise action with crisp acceptance criteria
- Priority: P0 (urgent), P1 (soon), P2 (later)
- Area tags: [App], [Camera], [LUT], [AI], [Android], [Build], [Test], [Docs], [UX], [I18n]

## P0 — Stability & Performance

- [ ] [Camera] Select cameras by `lensDirection` instead of index
  - Context: `lib/src/pages/camera_page.dart:107`, `:566`
  - Action: Implement helper to pick `CameraDescription` by `CameraLensDirection.back/front` with fallback when one side is missing. Replace index-based usage in init and switch.
  - Acceptance: App boots and switches camera reliably on devices with non-0/1 ordering; no crashes if only one camera exists.

- [ ] [App] Unify orientation management in one place
  - Context: `lib/main.dart:31` and `lib/src/pages/camera_page.dart:200-230`
  - Action: Decide single source (prefer app entry) for `SystemChrome.setPreferredOrientations`, remove delayed orientation set in page. Respect `Preferences.getIsCaptureOrientationLocked()`.
  - Acceptance: No duplicate orientation calls; no flicker on page load; manual lock works.

- [ ] [LUT] Reduce per-frame CPU and allocation in GPU preview
  - Context: `lib/src/lut/gpu_lut_preview.dart:161, 200-280`
  - Actions:
    - Reuse `Uint8List` buffers for Y/UV packing across frames.
    - Throttle processing (e.g., max 30 FPS or every Nth frame).
    - Optionally downsample before packing (configurable).
  - Acceptance: Average CPU usage and GC pressure drop during preview; visual smoothness acceptable; no frame leaks.

- [ ] [LUT][AI] Single image stream coordination & frame sharing
  - Context: AI service TODO at `lib/src/services/ai_suggestion_service.dart:120`; stream control callbacks in `LutPreviewManager`.
  - Actions:
    - Add a lightweight frame bus in `LutPreviewManager` that exposes a throttled latest frame (small JPEG/PNG) for consumers.
    - AI service subscribes to that bus instead of starting its own stream.
    - Ensure `stopImageStream/resumeImageStream` remain authoritative for capture.
  - Acceptance: Only one active camera stream; AI uploads happen without stream conflicts; capture still pauses/resumes properly.

- [ ] [AI][Net] Harden HTTP client and timeouts
  - Context: `lib/src/services/ai_suggestion_service.dart:149-191`
  - Actions: Add retry with backoff, per-host circuit breaker, and configurable timeouts; optionally support HTTPS and pin/allow self-signed based on user setting.
  - Acceptance: Network blips don’t spam UI; no freezes; user can require HTTPS.

## P1 — Architecture & Code Health

- [ ] [LUT] Consolidate `LutProvider` vs `LutPreviewManager`
  - Context: Provider exists but is not integrated in `lib/src/app.dart`; `LutPreviewManager` used directly.
  - Actions: Choose single source of truth. If keeping Provider, route preview updates via Provider and keep manager internal. Otherwise remove Provider and adjust UI accordingly.
  - Acceptance: No dead code; consistent state updates with fewer singletons.

- [ ] [Android] Method channel error handling and safety
  - Context: `lib/src/pages/camera_page.dart:1406-1519` (AndroidMethodChannel)
  - Actions: Wrap calls in try/catch with typed error logs and user feedback; ensure channel methods are no-ops on non-Android.
  - Acceptance: No unhandled exceptions when methods are missing or on iOS.

- [ ] [Camera] Remove unused `FutureBuilder` in `CaptureControlWidget`
  - Context: `lib/src/widgets/capture_control.dart:97`
  - Actions: Delete the `FutureBuilder` or use the device info to tailor UI; prefer simple `switchButton()`.
  - Acceptance: No functional change, simpler rebuild path.

- [ ] [Imaging] EXIF migration safety & memory limits
  - Context: `_injectJpegExif` in `lib/src/pages/camera_page.dart:1030+`
  - Actions: Bound processing for extremely large files; guard non-JPEG paths; add unit tests for EXIF orientation sanitize.
  - Acceptance: Stable on large images; unit tests pass.

- [ ] [Logs] Centralized logging facade
  - Actions: Introduce a simple `logger.dart` with levels and tags; funnel `debugPrint` through it; silence in release as needed.
  - Acceptance: Reduced noisy logs in release; consistent tags.

## P1 — Tests & CI

- [ ] [Test] Replace default counter widget test
  - Context: `test/widget_test.dart`
  - Actions: Remove sample; add tests for `Preferences`, `LutManager` (asset enumeration with fakes), EXIF sanitizer, and `LutControlWidget` basic interactions (golden optional).
  - Acceptance: `flutter test` passes locally with meaningful coverage.

- [ ] [CI] Add GitHub Actions for analyze, test, (optional) build
  - Actions: Workflow with `flutter pub get`, `flutter analyze`, `flutter test`; optionally cache pub; add build job guarded by tag or manual trigger.
  - Acceptance: CI runs on PRs and main; clear status checks.

- [ ] [Lints] Tighten analyzer rules
  - Context: `analysis_options.yaml`
  - Actions: Enable stricter rules (e.g., `unawaited_futures`, `prefer_final_fields`, `always_declare_return_types`). Consider re-enabling `strict-inference/raw-types`.
  - Acceptance: Repo is warning-clean under new rules.

## P1 — Docs & Build

- [ ] [Docs] Update README with AI Suggestion overview & privacy
  - Actions: Document external AI server flow, data handling, and opt-in controls. Remove references to embedded/test modes.
  - Acceptance: Users understand what is sent and how to disable.

- [ ] [Build] Document `flutter_gl` and `threeegl.aar` setup
  - Context: `scripts/install_threeegl_aar.sh`, `pubspec.yaml` overrides
  - Actions: Add “Build prerequisites” to README; script usage and troubleshooting.
  - Acceptance: New contributors can build without guesswork.

## P2 — UX, I18n, Nice-to-haves

- [ ] [UX] Improve accessibility and semantics
  - Actions: Add `Semantics` and `tooltip` to key controls; ensure AI suggestion widget has labels and focus order.
  - Acceptance: TalkBack/VoiceOver reads critical actions.

- [ ] [I18n] Localize AI suggestion texts and new UI strings
  - Actions: Add keys to `app_localizations_*.dart` and use via `AppLocalizations`; ensure Chinese, English at minimum.
  - Acceptance: New UI fully localized; l10n gen passes.

- [ ] [LUT] Additional LUT formats and caching
  - Actions: Support common 2D LUT atlases (PNG) with inferred tiling; cache parsed LUTs by path and mtime.
  - Acceptance: Faster LUT switching; stable visuals.

- [ ] [AI] Configurable upload resolution and cadence
  - Actions: Add settings for downscale factor and interval; persist in `Preferences`.
  - Acceptance: Users on low bandwidth can tune cost.

- [ ] [Perf] Optional on-screen perf HUD (FPS, ms/frame)
  - Actions: Small overlay toggled via dev setting; logs aggregated with rolling average.
  - Acceptance: Aids profiling without attaching tools.

## Task Breakdown (Suggested Order)
1) P0: LensDirection camera selection + orientation unification
2) P0: Single image stream + GPU preview allocations reduction
3) P1: Replace tests + add CI + tighten lints
4) P1: Cleanup Provider vs Manager, EXIF safety, logging
5) P1: Docs for AI/privacy and build prerequisites
6) P2: UX/I18n polish and optional features

## References
- Camera usage: `lib/src/pages/camera_page.dart`
- GPU LUT: `lib/src/lut/gpu_lut_preview.dart`, `lib/src/lut/lut_preview_manager.dart`
- AI service: `lib/src/services/ai_suggestion_service.dart`
- Preferences & globals: `lib/src/utils/preferences.dart`, `lib/src/globals.dart`
- Widgets: `lib/src/widgets/*`
- Provider (optional): `lib/src/provider/lut_provider.dart`
- Tests: `test/*`
- Config: `analysis_options.yaml`, `pubspec.yaml`, `.github/workflows/*`
