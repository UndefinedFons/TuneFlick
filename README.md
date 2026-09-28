<p align="center">
  <img src="Resources/AppIcon-v2.png" width="144" alt="TuneFlick 双脚音符应用图标">
</p>

<h1 align="center">TuneFlick</h1>

<p align="center">用两指横滑切换歌曲，让触控板成为音乐控制的一部分。</p>

<p align="center">macOS 13+ · Intel 与 Apple Silicon · MIT 开源</p>

<p align="center">
  <a href="https://github.com/UndefinedFons/TuneFlick/releases/latest">下载应用</a> ·
  <a href="#使用方式">使用方式</a> ·
  <a href="https://github.com/UndefinedFons/TuneFlick/issues">反馈问题</a>
</p>

## 项目介绍

TuneFlick 是一款 macOS 菜单栏音乐控制工具，为日常使用的音乐播放器补充统一的触控板切歌手势。无需切换窗口或寻找播放按钮，两指向左、向右滑动即可控制上一首和下一首。

播放器位于前台时，手势可以直接使用；播放器在后台时，按住所选修饰键再横滑即可切歌。TuneFlick 会优先保留播放器原生的横向滚动，并提供 `Control + 横滑` 作为前台原生操作入口。

应用采用原生 AppKit 界面，驻留菜单栏。毛玻璃控制面板提供手势开关、后台修饰键和反向滑动设置；前台切歌显示短暂的方向反馈，后台操作保持安静。TuneFlick 沿用现有播放器，不接管音乐账号、曲库或播放列表。

## 安装

1. 从 [Releases](https://github.com/UndefinedFons/TuneFlick/releases/latest) 下载 Universal 版本，解压后将 `TuneFlick.app` 放入“应用程序”文件夹。
2. 打开应用。TuneFlick 不会弹出主窗口或显示 Dock 图标，请点击菜单栏中的双脚音符打开控制面板。
3. 按面板提示，在“系统设置 → 隐私与安全性”中允许 TuneFlick 使用辅助功能和输入监控。授权后返回应用，确认面板显示“已就绪”。
4. 在支持的播放器中开始播放音乐，再使用两指横滑。TuneFlick 只控制 macOS 当前的音乐播放源。

同一个 Universal 2 应用包含 `x86_64` 和 `arm64`，无需根据 Mac 型号分别下载。

应用使用本地临时签名，未经过 Apple 公证。首次打开若被系统阻止，请在“系统设置 → 隐私与安全性”中选择“仍要打开”，并确认应用来自本仓库。无需关闭系统的安全保护。

## 使用方式

默认向左滑动切换上一首，向右滑动切换下一首。开启“反向滑动”后，两个方向的动作互换。

| 播放器状态 | 两指横滑 | Control + 两指横滑 |
| --- | --- | --- |
| 前台聚焦 | 切歌；原生横向滚动区域优先 | 交给播放器处理，不切歌 |
| 后台播放 | 保留当前 App 的原生操作 | 控制当前系统播放源，不显示方向提示 |

后台修饰键默认为 `Control`，可在面板中改为 `Option`、`Command` 或 `Shift`。这个设置只改变后台操作；前台的 `Control + 横滑` 始终保留原生行为。

前台切歌使用不带修饰键的横滑；后台需要只按住所选修饰键。其他组合键交给当前 App 处理。

点击菜单栏图标即可打开并操作面板；点击面板外部或按 `Esc` 收起。关闭手势开关后，TuneFlick 不再接管滑动。

## 播放器支持

默认支持以下播放器：

- Apple Music
- Spotify
- 网易云音乐
- QQ 音乐
- 酷狗音乐

另外内置 Tidal、Deezer、Doppler、IINA 与 VLC 的应用识别。播放器需要向 macOS 发布 Now Playing 状态并接受系统的上一首、下一首命令；多播放器同时运行时，以系统当前播放源为准。

各版本的兼容性说明见 [发布说明](https://github.com/UndefinedFons/TuneFlick/releases)。

### 兼容性边界

原生横向滚动的识别依赖播放器提供的辅助功能信息。自定义控件、界面更新或信息缺失可能影响识别；无法确定时，TuneFlick 会放行滑动。需要原生操作时，可按住 `Control`，或暂时关闭手势。

切歌也受播放队列、电台、广告和播放器自身的命令支持情况影响。应用不会自动切换系统播放源，也不会启动未运行的播放器。遇到问题时，请附上 macOS 版本、Mac 架构、播放器名称与版本，以及问题发生在前台还是后台。

前台播放器与系统当前播放源不一致时，TuneFlick 会保留原生滑动，避免误控另一个播放器。系统媒体控制组件使用 macOS 的非公开接口；系统更新可能影响兼容性。

## 权限与隐私

辅助功能和输入监控用于识别触控板滚动、判断原生滚动区域，以及接管切歌手势。TuneFlick 不监听文本输入，不上传播放信息，也不包含账号登录、广告或遥测。

设置保存在本机。系统播放信息仅用于本地命令路由，不建立歌曲历史记录。缺少权限时，面板会显示相应提示；若辅助功能已开启但仍未就绪，请同时检查“输入监控”，然后退出并重新打开应用。

## 从源码构建

需要 macOS、Xcode Command Line Tools 和 Swift 5.9 或更新版本：

```bash
git clone https://github.com/UndefinedFons/TuneFlick.git
cd TuneFlick
./Scripts/build-app.sh
```

构建结果位于 `build/TuneFlick.app`。脚本编译两种架构并打包媒体控制组件，不需要额外安装 Homebrew。确认包内架构：

```bash
xcrun lipo -archs build/TuneFlick.app/Contents/MacOS/TuneFlick
```

安装到当前用户目录并运行：

```bash
./Scripts/install-app.sh
open ~/Applications/TuneFlick.app
```

## 致谢与许可证

播放器识别与系统媒体控制的集成参考了 [Yudaotor/lyrimuse](https://github.com/Yudaotor/lyrimuse)。感谢该项目对主流音乐播放器接入机制的整理。

TuneFlick 的代码采用 [MIT 许可证](LICENSE)。随应用分发的 [media-control](https://github.com/ungive/media-control) 与 [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter) 保留各自的 BSD-3-Clause 许可证，详见 [第三方声明](THIRD_PARTY_LICENSES.md)。
