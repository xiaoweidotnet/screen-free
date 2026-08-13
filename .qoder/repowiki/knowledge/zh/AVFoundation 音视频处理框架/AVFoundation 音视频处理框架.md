---
kind: external_dependency
name: AVFoundation 音视频处理框架
slug: avfoundation
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
source_files:
    - Sources/ScreenFree/VideoExporter.swift
    - Sources/ScreenFree/RecordingAudioMixer.swift
---

### 项目中的角色
AVFoundation 负责 ScreenFree 的视频编码、音频混合、格式转换和媒体文件处理。

### 集成方式
- 与 ScreenCaptureKit 配合完成完整的录制到导出流程
- 支持 H.264/AAC MP4 编码和 GIF 动画生成
- 实现多音轨混合（系统音频 + 麦克风）

### 稳定使用模式
- 视频编码：H.264 编码，支持 Source/720p/1080p/4K 分辨率
- 音频处理：AAC 编码，48kHz 立体声，支持音量调节和静音
- 格式输出：MP4 和 GIF 两种主要格式
- 实时预览：基于 AVPlayer 的预览播放

### 注意事项
- 导出过程支持进度监控和取消操作
- 需要处理不同帧率（24/25/30/50/60 fps）的兼容性
- 自定义尺寸时需要中心裁剪而非拉伸