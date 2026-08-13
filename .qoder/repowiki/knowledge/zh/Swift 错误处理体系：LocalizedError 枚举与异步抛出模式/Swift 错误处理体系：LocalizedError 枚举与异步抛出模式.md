---
kind: error_handling
name: Swift 错误处理体系：LocalizedError 枚举与异步抛出模式
category: error_handling
scope:
    - '**'
source_files:
    - Sources/ScreenFree/RecordingEngine.swift
    - Sources/ScreenFree/VideoExporter.swift
    - Sources/ScreenFree/CaptionGenerator.swift
    - Sources/ScreenFree/ProjectPersistence.swift
    - Sources/ScreenFree/EditorStore.swift
    - Sources/ScreenFree/DesktopIconPresentation.swift
    - Sources/ScreenFree/DeviceMonitor.swift
---

该 ScreenFree macOS 屏幕录制项目采用 Swift 原生的基于 throws/async throws 的错误处理机制，通过为每个功能模块定义专用的 enum ...: LocalizedError 类型来统一表达错误语义，并在 UI 层通过 @Published var errorMessage: String? 集中呈现。

1. 系统与方法
- 所有业务错误均定义为遵循 LocalizedError 协议的枚举，提供人类可读的 errorDescription，无需额外国际化框架即可直接显示。
- 异步 API 普遍使用 async throws 签名（如 RecordingEngine.start、VideoExporter.export、CaptionGenerator.generate），调用方通过 do { try await ... } catch { ... } 捕获并转换为 errorMessage。
- 底层 I/O 或系统调用失败时，优先保留原始 Error（如 reader.error ?? VideoExportError.exportFailed），再回退到领域错误枚举。

2. 关键文件与错误类型
- RecordingEngine.swift: RecordingError（noSource、noAudioApplications、cannotStartWriter、cannotFinishWriter、writerFailed）
- VideoExporter.swift: VideoExportError（missingVideoTrack、cannotCreateCompositionTrack、cannotCreateExportSession、cannotReadComposedFrame、exportFailed）
- CaptionGenerator.swift: CaptionGenerationError（permissionDenied、recognizerUnavailable）
- ProjectPersistence.swift: ProjectPersistenceError（unsupportedVersion、missingSource）
- EditorStore.swift: FrameExportError、AudioBackgroundError
- DesktopIconPresentation.swift: DesktopIconPresentationError
- DeviceMonitor.swift: DeviceMonitorError
- ExportOptions.swift: VideoPasteboardError
- OriginalMediaExporter.swift: OriginalMediaExportError
- RecordingAudioMixer.swift: RecordingAudioMixError
- RecordingSegmentMerger.swift: RecordingSegmentMergeError
- StylePreset.swift: StylePresetError

3. 架构与约定
- 错误定义与使用严格分层：底层引擎（RecordingEngine、VideoExporter、CaptionGenerator）抛出具体领域错误；上层 EditorStore 仅负责将 localizedDescription 写入 errorMessage，UI 层通过 localizedErrorMessage 绑定显示。
- 权限类错误（麦克风、摄像头、屏幕录制、语音识别）在 EditorStore 中通过 refreshPermissionState、requestMicrophoneAccess、requestCameraAccess 等前置检查提前拦截，避免进入核心流程后抛错。
- 文件/磁盘操作失败时，优先尝试恢复（如 try? FileManager.default.removeItem(at:) 清理部分导出产物），再向上抛出。

4. 约定与约束
- 所有可对外暴露的错误必须实现 LocalizedError，禁止使用裸 String 或 NSError 作为用户可见错误。
- 异步方法一律使用 async throws，禁止在异步上下文中使用 fatalError 或 preconditionFailure 终止进程。
- UI 层不直接处理底层错误细节，统一通过 @Published var errorMessage: String? 传递，配合 L10n.text(...) 进行本地化。
- 测试套件（Tests/ScreenFreeMediaTests）覆盖各错误路径，确保错误枚举分支完整且消息可本地化。