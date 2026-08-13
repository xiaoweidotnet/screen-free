---
kind: dependency_management
name: Swift Package Manager 依赖管理
category: dependency_management
scope:
    - '**'
source_files:
    - Package.swift
    - .gitignore
---

本项目使用 Swift Package Manager (SPM) 作为唯一的依赖管理与构建系统，采用单仓库多目标（monorepo）结构组织代码与依赖。

**使用的系统与工具**
- Swift Package Manager：通过根目录 `Package.swift` 声明所有模块、产品与依赖关系，swift-tools-version 为 6.0，最低支持 macOS 14。
- SPM 缓存目录 `.build/` 与包管理器元数据 `.swiftpm/` 均被 `.gitignore` 忽略，不纳入版本控制。

**关键文件与模块**
- `Package.swift`：定义两个产品（`ScreenFree` 可执行应用、`ScreenFreeCore` 库）和四个目标（`ScreenFreeCore`、`ScreenFree`、`ScreenFreeCoreTests`、`ScreenFreeMediaTests`），并通过 `dependencies` 字段明确模块间依赖关系。
- `.gitignore`：排除 `.build/`、`.swiftpm/`、`dist/` 等 SPM 生成产物及构建输出。

**架构与约定**
- 依赖声明集中式：所有第三方库依赖需通过 `Package.swift` 的 `dependencies` 数组添加，由 SPM 自动解析与下载。
- 本地模块化依赖：项目内部通过 SPM target 划分职责——`ScreenFreeCore` 提供时间线模型与转场逻辑，`ScreenFree` 应用层依赖该核心库，测试目标按需依赖对应模块。
- 资源管理：应用目标通过 `.process("Resources")` 将 `Sources/ScreenFree/Resources` 下的本地化字符串、图标等资源打包进产物。
- 语言模式：显式设置 `swiftLanguageModes: [.v5]` 以兼容 Swift 5 语法。

**约束与规范**
- 无 vendoring 策略：未使用 `vendor/` 目录或私有源镜像，依赖由 SPM 默认从 swift.org 包索引解析。
- 无锁文件提交：`Package.resolved` 未被跟踪（不在 `.gitignore` 中但未见提交），依赖版本由 SPM 在构建时动态解析。
- 平台锁定：仅声明 `.macOS(.v14)` 为目标平台，不支持 iOS（尽管存在 `ScreenFreeiOS` 目录，当前未在产品中暴露）。
- 测试隔离：测试目标独立声明，`ScreenFreeMediaTests` 同时依赖 `ScreenFree` 与 `ScreenFreeCore`，便于跨模块集成测试。