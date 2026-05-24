![Hana Banner](Assets/Banner.png)

# 🌸 Hana

Hana 是一个使用 SwiftUI 构建的 Hanime1 客户端，面向 iOS、iPadOS、macOS。

## 主要功能

- 首页发现、横幅推荐
- 视频搜索、筛选、观看记录、收藏、稍后观看、播放清单
- 视频详情页、评论、相关推荐、清晰度选择
- AVKit 播放器、画中画、循环播放、长按倍速、播放进度恢复
- HKeyframes 关键帧、共享记录、倒计时提示和剪贴板导入
- 下载队列、分组管理和本地播放
- iOS TabView 与 macOS NavigationSplitView 双平台布局

## 技术栈

- SwiftUI
- SwiftData
- AVKit / AVFoundation
- URLSession
- Nuke
- SwiftSoup

## 运行项目

1. 使用 Xcode 打开 `Hana.xcodeproj`
2. 选择 `Hana` scheme
3. 选择运行目标，例如 iPhone Simulator 或 My Mac
4. 直接 Build / Run

也可以使用命令行构建：

```bash
xcodebuild -project Hana.xcodeproj -scheme Hana -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Hana.xcodeproj -scheme Hana -destination 'platform=macOS' build
```

## 开发注意事项

- `build/`、`DerivedData/`、`xcuserdata/`、`.DS_Store` 等本地产物不应提交
- `Package.resolved` 应保留提交，方便复现依赖版本
- 修改后需要分别验证 macOS 和 iOS，提交前请确保跨平台一致性

## 免责声明

本项目仅作为客户端实现使用。使用时应遵守目标站点的服务条款、当地法律法规和内容访问限制。
