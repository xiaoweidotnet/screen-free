---
kind: build_system
name: Swift Package Manager 构建与打包系统
category: build_system
scope:
    - '**'
source_files:
    - Package.swift
    - script/build_and_run.sh
    - script/build_app_store.sh
    - script/package_dmg.sh
    - Config/AppStore.entitlements
---

本项目采用 Swift Package Manager (SPM) 作为核心构建系统，配合 Bash 脚本完成 macOS 应用的本地开发、App Store 发布包生成与 DMG 安装包制作。整体构建流程围绕 `Package.swift` 定义的模块结构展开，通过三个专用脚本覆盖从开发到分发的完整生命周期。

**构建系统与工具链**
- 使用 `swift-tools-version: 6.0` 的 SPM 工程，目标平台为 macOS 14.0，Swift 语言模式兼容 v5
- 定义两个产品：可执行文件 `ScreenFree` 和库 `ScreenFreeCore`，以及两个测试目标 `ScreenFreeCoreTests` 和 `ScreenFreeMediaTests`
- 资源通过 `.process("Resources")` 声明，由 SPM 自动处理国际化字符串与图标等静态资源

**开发构建流程** (`script/build_and_run.sh`)
- 支持多种运行模式：`run`（默认，编译并打开应用）、`--package`（release 构建）、`--debug`（lldb 调试）、`--logs`/`--telemetry`（日志流监控）、`--verify`（进程验证）
- 通过 `swift build -c debug|release` 编译二进制，手动组装 `.app` Bundle 结构（Contents/MacOS、Contents/Resources、Info.plist）
- 动态复制资源 bundle、`.lproj` 国际化目录、`ScreenFree.icns` 图标与 `PrivacyInfo.xcprivacy` 隐私清单
- Info.plist 通过 here-doc 模板生成，硬编码版本号为 `CFBundleShortVersionString=0.2.0`、`CFBundleVersion=1`
- 使用 `codesign --sign -` 进行临时签名，便于本地开发与调试

**App Store 发布流程** (`script/build_app_store.sh`)
- 要求严格的环境变量：`APP_SIGN_IDENTITY`、`INSTALLER_SIGN_IDENTITY`、`PROVISIONING_PROFILE`、`BUNDLE_ID`、`MARKETING_VERSION`、`BUILD_NUMBER`
- 通过 `require_value` 函数强制校验必填参数，缺失时直接退出
- 解析 provisioning profile 提取团队标识与应用标识，验证其与 BUNDLE_ID 匹配
- 合并 entitlements 文件，注入 application-identifier 与 team-identifier
- 使用 `swift build -c release -Xswiftc -DAPP_STORE` 启用 APP_STORE 编译宏
- 严格的代码签名流程：`codesign --timestamp --options runtime` 启用 hardened runtime，随后 `codesign --verify --deep --strict` 验证签名完整性
- 通过 `productbuild` 生成 `.pkg` 安装包，并使用 `pkgutil --check-signature` 验证安装包签名
- 输出提示下一步使用 Transporter 或 `xcrun altool` 上传至 App Store Connect

**DMG 分发包生成** (`script/package_dmg.sh`)
- 依赖 `dist/ScreenFree.app` 已存在（需先执行 `build_and_run.sh --package`）
- 从 Info.plist 读取版本号，生成命名格式为 `ScreenFree-<VERSION>.dmg` 的压缩包
- 使用 `hdiutil create -format UDZO` 创建压缩 DMG，并在其中添加 `/Applications` 软链接以便拖拽安装
- 通过 `trap 'rm -rf "$STAGING_DIR"' EXIT` 确保临时目录在退出时清理

**架构约定与约束**
- 所有构建脚本遵循 `set -euo pipefail` 严格模式，任何命令失败立即终止
- 路径计算统一使用 `$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)` 获取仓库根目录
- 版本管理分离：开发版固定为 0.2.0，App Store 版通过环境变量 `MARKETING_VERSION` 和 `BUILD_NUMBER` 注入
- 权限描述键（NSScreenCaptureUsageDescription、NSMicrophoneUsageDescription 等）在 Info.plist 中显式声明，符合 macOS 隐私要求
- 自定义文档类型 `com.screenfree.project` 与扩展名 `.screenfree` 通过 UTExportedTypeDeclarations 注册，使应用能识别项目文件