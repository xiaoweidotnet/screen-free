---
kind: external_dependency
name: SwiftUI 用户界面框架
slug: swiftui
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
source_files:
    - Sources/ScreenFree/MainView.swift
    - Sources/ScreenFree/SettingsView.swift
    - Package.swift
---

### 项目中的角色
ScreenFree 完全基于 SwiftUI 构建原生 macOS 应用程序的用户界面。

### 集成方式
- 作为主要的 UI 框架，所有界面组件都使用 SwiftUI 构建
- 与 AppKit 混用处理底层系统交互
- 支持国际化和本地化（英文、简体中文、跟随系统）

### 稳定使用模式
- 响应式 UI 更新机制
- 跨平台 UI 代码复用（macOS/iOS）
- 与系统主题和深色模式集成
- 支持触摸板手势和键盘快捷键

### 注意事项
- 需要 macOS 14+ 支持
- 部分高级功能需要回退到 AppKit 实现