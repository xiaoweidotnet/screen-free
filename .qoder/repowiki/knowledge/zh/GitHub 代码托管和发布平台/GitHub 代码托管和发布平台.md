---
kind: external_dependency
name: GitHub 代码托管和发布平台
slug: github
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
source_files:
    - script/package_dmg.sh
---

### 项目中的角色
GitHub 用作项目的代码托管、版本管理和应用分发平台。

### 集成方式
- 使用 `gh` CLI 工具进行 Release 管理
- 通过 GitHub Releases 发布 DMG 安装包
- 仓库地址：https://github.com/xiaoweidotnet/screen-free

### 稳定使用模式
- 使用 Git tag 标记版本号（如 v0.2.0）
- 将编译后的 DMG 文件作为 Release asset 上传
- 提供下载链接和安装说明

### 注意事项
- 应用使用 ad-hoc 签名，用户首次打开可能被 Gatekeeper 拦截
- 建议后续接入 Developer ID 签名和公证流程