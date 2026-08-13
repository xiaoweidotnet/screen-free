---
kind: external_dependency
name: Apple ScreenCaptureKit 屏幕录制框架
slug: apple-screencapturekit
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
source_files:
    - Package.swift
    - Sources/ScreenFree/RecordingEngine.swift
    - script/build_and_run.sh
---

### 项目中的角色
ScreenFree 使用 ScreenCaptureKit 作为核心屏幕录制和系统音频捕获框架，支持显示器、窗口、自由区域和设备四种录制模式。

### 集成方式
- 通过 Swift Package Manager 管理依赖（Package.swift 中声明）
- 在 Sources/ScreenFree 目录下的多个文件中集成，包括 RecordingEngine.swift、AudioAnalyzer.swift 等
- 需要 macOS 14+ 系统支持

### 稳定使用模式
- 屏幕录制：支持多显示器选择、窗口录制、自由区域绘制
- 音频捕获：系统音频（全部应用/选定应用/关闭）、麦克风独立音轨
- 权限处理：通过 NSPrincipalClass 和 Info.plist 中的 usage descriptions 声明权限
- 与 AVFoundation 配合完成视频编码和导出

### 注意事项
- 麦克风录制需要 macOS 15 的流 API，macOS 14 上会明确拒绝而非静默失败
- 需要 Input Monitoring 权限用于自动点击检测
- 沙盒环境下某些功能受限（如隐藏桌面图标）