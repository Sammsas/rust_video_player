# Rust Video Player - GitHub Actions 自动构建版

这是一个 Windows x64 可打包发布的 Rust 嵌入式视频播放器项目。

## 功能

- Rust + egui / eframe GUI
- GStreamer playbin 解码和音频播放
- GStreamer appsink 输出 RGBA 视频帧，画面嵌入 GUI 主窗口
- 内置 exe 图标、窗口图标、版本信息
- Windows 打包脚本
- GitHub Actions 自动构建、上传 Artifact、tag 自动发布 Release
- 生成 SHA256 校验文件

## 本地运行

```powershell
cargo run --release
```

## 本地打包

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package_windows.ps1
```

如果 GStreamer 在其他路径：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package_windows.ps1 -GStreamerRoot "D:\gstreamer\1.0\msvc_x86_64"
```

## GitHub Actions 自动构建

Workflow 文件：

```text
.github/workflows/windows-build.yml
```

触发方式：

- push 到 `main`
- pull request 到 `main`
- 推送 `v*` tag，例如 `v0.3.2`
- 手动 `workflow_dispatch`

普通 push / PR 会生成 Actions Artifact：

```text
RustVideoPlayer-windows-x64.zip
RustVideoPlayer-windows-x64.zip.sha256
```

推送 tag 后会自动创建或更新 GitHub Release：

```bash
git tag v0.3.2
git push origin v0.3.2
```

## 发布目录

```text
dist\RustVideoPlayer\
├─ RustVideoPlayer.exe
├─ run.bat
├─ VERSION.txt
├─ README.md
├─ assets\
│  ├─ app.ico
│  └─ app.png
├─ licenses\
│  └─ THIRD_PARTY_NOTICES.txt
└─ gstreamer\
   ├─ bin\
   └─ lib\
      └─ gstreamer-1.0\
```

## 授权注意

如果商业发布，请检查 GStreamer、FFmpeg/libav、插件和编解码器授权。建议动态链接 DLL、附带第三方许可证和 NOTICE，并避免 GPL / nonfree 构建。
