param(
    [string]$Configuration = "release",
    [string]$GStreamerRoot = "",
    [string]$OutputDir = "dist\RustVideoPlayer",
    [string]$AppExeName = "RustVideoPlayer.exe"
)
$ErrorActionPreference = "Stop"
Write-Host "== Rust Video Player Windows Packager ==" -ForegroundColor Cyan
if ([string]::IsNullOrWhiteSpace($GStreamerRoot)) {
    if ($env:GSTREAMER_1_0_ROOT_MSVC_X86_64) { $GStreamerRoot = $env:GSTREAMER_1_0_ROOT_MSVC_X86_64 }
    elseif ($env:GSTREAMER_1_0_ROOT_X86_64) { $GStreamerRoot = $env:GSTREAMER_1_0_ROOT_X86_64 }
    else { $GStreamerRoot = "C:\gstreamer\1.0\msvc_x86_64" }
}
$GStreamerRoot = [System.IO.Path]::GetFullPath($GStreamerRoot)
$GstBin = Join-Path $GStreamerRoot "bin"
$GstPluginDir = Join-Path $GStreamerRoot "lib\gstreamer-1.0"
if (!(Test-Path $GstBin)) { throw "找不到 GStreamer bin 目录：$GstBin" }
if (!(Test-Path $GstPluginDir)) { throw "找不到 GStreamer 插件目录：$GstPluginDir" }
if (!(Test-Path "assets\app.ico")) { throw "缺少 assets\app.ico，无法编译 exe 图标" }
if (!(Test-Path "assets\app.png")) { throw "缺少 assets\app.png，无法编译窗口图标" }

cargo build --release
$BuiltExe = Join-Path "target\release" "rust_video_player.exe"
if (!(Test-Path $BuiltExe)) { throw "找不到编译结果：$BuiltExe" }
if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir "gstreamer") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir "licenses") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir "assets") | Out-Null
Copy-Item $BuiltExe (Join-Path $OutputDir $AppExeName) -Force
Copy-Item "assets\app.ico" (Join-Path $OutputDir "assets\app.ico") -Force
Copy-Item "assets\app.png" (Join-Path $OutputDir "assets\app.png") -Force
Copy-Item $GstBin (Join-Path $OutputDir "gstreamer\bin") -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir "gstreamer\lib") | Out-Null
Copy-Item $GstPluginDir (Join-Path $OutputDir "gstreamer\lib\gstreamer-1.0") -Recurse -Force
foreach ($sub in @("share", "libexec", "etc")) { $src = Join-Path $GStreamerRoot $sub; if (Test-Path $src) { Copy-Item $src (Join-Path $OutputDir "gstreamer\$sub") -Recurse -Force } }
Copy-Item "README.md" (Join-Path $OutputDir "README.md") -Force
Copy-Item "licenses\THIRD_PARTY_NOTICES.txt" (Join-Path $OutputDir "licenses\THIRD_PARTY_NOTICES.txt") -Force
$RunBat = @"
@echo off
set APP_DIR=%~dp0
set PATH=%APP_DIR%gstreamer\bin;%PATH%
set GST_PLUGIN_PATH=%APP_DIR%gstreamer\lib\gstreamer-1.0
set GST_PLUGIN_SYSTEM_PATH_1_0=%APP_DIR%gstreamer\lib\gstreamer-1.0
start "" "%APP_DIR%$AppExeName"
"@
$RunBat | Out-File -Encoding ASCII (Join-Path $OutputDir "run.bat")
$VersionTxt = @"
Rust Video Player
Version: 0.3.2
Executable: $AppExeName
Packaged: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
GStreamerRoot: $GStreamerRoot
"@
$VersionTxt | Out-File -Encoding UTF8 (Join-Path $OutputDir "VERSION.txt")
Write-Host "打包完成：$OutputDir" -ForegroundColor Green
