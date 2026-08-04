# Mac App Store 提交资料

## 已生成文件

- `Assets/AppIcon-1024.png`：1024×1024、RGB、无 Alpha 的 App Store 主图标。
- `Assets/AppIcon.appiconset`：可导入 Xcode Asset Catalog 的完整 macOS 图标集。
- `Sources/ScreenFree/Resources/ScreenFree.icns`：应用包使用的多分辨率图标。
- `Sources/ScreenFree/Resources/PrivacyInfo.xcprivacy`：隐私清单，声明 UserDefaults、文件时间戳、系统运行时间及磁盘空间 API 的使用理由。
- `Config/AppStore.entitlements`：Mac App Store 沙盒、麦克风、摄像头、影片目录及用户所选文件权限。
- `Metadata`：中英文商店文案、隐私填写建议、审核备注和隐私政策模板。
- `Screenshots`：中英文商店截图目录。Mac 截图必须为 16:10，允许尺寸为 1280×800、1440×900、2560×1600 或 2880×1800，且不得包含 Alpha。
- `SUBMISSION_CHECKLIST.md`：账号、构建、沙盒兼容和 App Store Connect 的逐项提交清单。
- `script/build_app_store.sh`：使用真实分发证书、安装器证书和配置文件生成签名 `.pkg`。

## 无法自动填写的账号信息

以下信息属于开发者账号或公开服务，提交前必须人工替换：

- Apple Developer Team ID
- Mac App Distribution 签名证书
- Mac Installer Distribution 签名证书
- 与 `com.screenfree.app` 匹配的 Mac App Store provisioning profile
- App Store Connect 中的 App 记录、SKU 和 Apple ID
- 隐私政策 URL、支持 URL、支持邮箱和版权主体
- 定价、销售地区、年龄分级、内容版权、出口合规和 DSA 身份

## 当前阻塞项

本机钥匙串当前没有可用代码签名身份，因此只能生成临时签名开发包，不能生成可上传 App Store Connect 的最终 `.pkg`。

此外，Mac App Store 强制启用 App Sandbox。当前“隐藏桌面图标”功能会修改 Finder 偏好设置并重启 Finder，该行为不适合沙盒版本；全局点击/快捷键监听也必须在真实沙盒签名包中验证 Input Monitoring 行为。完成这两项兼容性验证前，不应宣称构建已通过 App Review 要求。

`APP_STORE` 编译条件已经从商店构建中隐藏“隐藏桌面图标”，并强制禁止调用对应 Finder 控制逻辑。日常开发包仍保留该功能。

## 最终构建

安装证书并下载 provisioning profile 后运行：

```bash
APP_SIGN_IDENTITY="Mac App Distribution: 公司名称 (TEAMID)" \
INSTALLER_SIGN_IDENTITY="Mac Installer Distribution: 公司名称 (TEAMID)" \
PROVISIONING_PROFILE="$HOME/Downloads/ScreenFree_Mac_App_Store.provisionprofile" \
MARKETING_VERSION="1.0.0" \
BUILD_NUMBER="1" \
./script/build_app_store.sh
```

构建完成后，使用 Transporter 上传 `AppStore/Build/ScreenFree.pkg`，或配置 App Store Connect API Key 后使用 `xcrun altool` 验证及上传。
