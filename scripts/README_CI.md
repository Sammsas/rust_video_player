# CI Scripts

## install_gstreamer_windows.ps1

用于 GitHub Actions 或本地 Windows 环境安装 GStreamer MSVC x64。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install_gstreamer_windows.ps1 `
  -Version "1.28.3" `
  -InstallRoot "C:\gstreamer\1.0\msvc_x86_64"
```

在 GitHub Actions 中使用 `-ExportGitHubEnv` 会自动写入 `GITHUB_PATH` 和 `GITHUB_ENV`。
