# Mac App Store 提交清单

## 开发者账号

- [ ] Apple Developer Program 协议已由 Account Holder 接受。
- [ ] 已注册与最终应用一致的显式 Bundle ID；首个构建版本上传后不可更改。
- [ ] 已在 App Store Connect 新建 macOS App 记录。
- [ ] 已安装 Mac App Distribution 和 Mac Installer Distribution 证书及其私钥。
- [ ] 已下载与 Bundle ID、App Sandbox 能力匹配的 Mac App Store provisioning profile。

## 应用构建

- [x] 1024×1024 RGB 无 Alpha 主图标。
- [x] 完整 macOS App Icon 尺寸集与 `.icns`。
- [x] App Sandbox 权限模板。
- [x] 摄像头、麦克风、屏幕录制和语音识别用途说明及中英文翻译。
- [x] 隐私清单 `PrivacyInfo.xcprivacy`。
- [x] 影片与 `.screenfree` 文件类型声明。
- [ ] 在真实沙盒分发签名包中验证录制、输入监控、导入、历史、保存和导出。
- [ ] 使用 `script/build_app_store.sh` 生成签名 `.pkg`。
- [ ] 使用 Transporter 或 `xcrun altool` 完成上传前验证。

## 产品兼容性

- [x] App Store 构建不显示“隐藏桌面图标”，也不会修改 Finder 偏好设置。
- [ ] 验证沙盒中的全局点击与快捷键监控；如果系统不允许，应在 App Store 版本中采用可审核的替代实现或明确降级。
- [ ] 为需要跨启动持续访问的用户所选外部文件实现 security-scoped bookmark。目前模板已声明 app-scope bookmark 权限，但代码仍需逐项验证持久访问行为。
- [ ] 在应用内加入可访问的隐私政策入口；仅在 App Store Connect 中填写 URL 不满足审核指南对应用内入口的要求。

## App Store Connect 元数据

- [x] 简体中文与英文名称、副标题、描述、关键词及首版说明草案。
- [x] 中英文审核备注草案。
- [x] 中英文隐私政策草案。
- [x] 中英文 1440×900 真实界面截图各一张，无 Alpha。
- [ ] 将隐私政策发布为公开 HTTPS 页面并替换占位 URL。
- [ ] 填写支持 URL、支持邮箱和版权主体。
- [ ] 完成年龄分级、内容版权、出口合规、定价、销售地区及 DSA 身份。
- [ ] 如面向中国大陆提供下载，核对适用的备案及合规信息。

## 官方参考

- App 图标：https://developer.apple.com/design/human-interface-guidelines/app-icons
- 截图规格：https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- 上传构建：https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
- App Sandbox：https://developer.apple.com/documentation/security/app-sandbox
- 隐私清单：https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- App 信息：https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
