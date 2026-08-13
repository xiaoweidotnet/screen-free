---
kind: configuration_system
name: 配置系统 — UserDefaults + JSON 快照的 macOS 应用配置管理
category: configuration_system
scope:
    - '**'
source_files:
    - Sources/ScreenFree/EditorStore.swift
    - Sources/ScreenFree/SettingsView.swift
    - Sources/ScreenFree/ProjectPersistence.swift
    - Sources/ScreenFree/StylePreset.swift
    - script/build_and_run.sh
    - .codex/environments/environment.toml
    - Config/AppStore.entitlements
---

该仓库采用基于 Swift 标准库的配置方案，以 UserDefaults 作为用户偏好存储、JSON 编码的快照文件作为项目与样式配置的持久化载体，并通过构建脚本动态生成 Info.plist 完成应用级元数据配置。整体呈现“轻量、内聚、无第三方依赖”的特点。

1. 使用的系统与工具
- UserDefaults.standard：用于存储用户界面与录制行为相关的布尔/字符串/枚举偏好（如语言、降噪开关、隐藏 Dock 图标等）。
- SwiftUI @AppStorage：在 SettingsView、MainView 等视图层直接声明式绑定少量 UI 状态到 UserDefaults。
- Codable + JSONEncoder/JSONDecoder：将复杂对象（项目快照 ScreenFreeProjectSnapshot、样式预设 ScreenFreeStylePreset）序列化为 .screenfree / JSON 文件，实现版本化持久化。
- 构建脚本 script/build_and_run.sh：在每次构建时通过 here-doc 动态生成 Info.plist，注入 Bundle ID、最小系统版本、权限描述、自定义 UTType 等。
- .codex/environments/environment.toml：由 Codex 环境自动生成的运行动作配置，仅包含 version/name/setup/actions，不包含运行时配置。

2. 关键文件与位置
- Sources/ScreenFree/EditorStore.swift：用户偏好的核心读写入口，所有 @Published 设置项在 didSet 中写入 UserDefaults，并在 init() 中统一恢复默认值。
- Sources/ScreenFree/SettingsView.swift：使用 @AppStorage("autoStudioCheck")、@AppStorage("floatingRecordingController") 直接绑定两个简单开关。
- Sources/ScreenFree/ProjectPersistence.swift：定义 ScreenFreeProjectSnapshot 结构体与 ProjectPersistence 服务，负责 .screenfree 项目的保存/加载与版本校验。
- Sources/ScreenFree/StylePreset.swift：定义 ScreenFreeStylePreset 与 StylePresetPersistence，内置 Clean/Vibrant/Minimal 三种预设，支持导入/导出 JSON 预设文件。
- script/build_and_run.sh：构建阶段生成 Info.plist，声明 NSMicrophoneUsageDescription、NSCameraUsageDescription、NSSpeechRecognitionUsageDescription 等权限键。
- .codex/environments/environment.toml：Codex 环境的运行命令配置，非运行时配置。
- Config/AppStore.entitlements：App Store 提交所需的 entitlements 文件。

3. 架构与设计约定
- 分层清晰：EditorStore 集中管理所有用户偏好，UI 层通过 @Published/@AppStorage 观察变化；ProjectPersistence 与 StylePresetPersistence 分别负责项目与样式的 I/O。
- 版本化持久化：ScreenFreeProjectSnapshot.currentVersion 与 ScreenFreeStylePreset.currentVersion 配合解码时的版本检查，遇到不支持的版本抛出 unsupportedVersion 错误。
- 原子写入：JSON 文件均使用 options: .atomic 写入，避免部分写入导致损坏。
- 资源路径策略：项目恢复目录位于 Application Support/ScreenFree/Recovery.screenfree，通过 FileManager.applicationSupportDirectory 定位。
- 构建期配置：Info.plist 不在源码中硬编码，而是由 build_and_run.sh 在构建时生成，便于 debug/release 切换与 CI 集成。

4. 约定与约束
- 用户偏好必须通过 EditorStore 中的 @Published 属性暴露，并在 didSet 中同步写入 UserDefaults，key 使用小驼峰字符串（如 reduceMicrophoneNoise、hideDockIconWhileRecording）。
- 新增的项目或样式字段需在对应 Snapshot/Preset 结构体中保持向后兼容（可选字段），并在 currentVersion 升级时处理迁移。
- 所有 JSON 序列化需启用 prettyPrinted 与 sortedKeys，保证可读性与可比较性。
- 权限相关描述（麦克风、摄像头、屏幕录制、语音识别）必须在 Info.plist 中声明，由构建脚本统一管理。
- 环境变量与外部配置未使用 .env/.yaml/.toml 等格式，仅通过 Codex 的 environment.toml 指定开发动作，不侵入运行时。
- 未发现 Feature Flags、远程配置或 A/B 测试机制，所有开关均为本地 UserDefaults 或编译期 #if APP_STORE 宏控制。