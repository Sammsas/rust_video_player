param([string]$GStreamerRoot = "")
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($GStreamerRoot)) {
    if ($env:GSTREAMER_1_0_ROOT_MSVC_X86_64) { $GStreamerRoot = $env:GSTREAMER_1_0_ROOT_MSVC_X86_64 }
    elseif ($env:GSTREAMER_1_0_ROOT_X86_64) { $GStreamerRoot = $env:GSTREAMER_1_0_ROOT_X86_64 }
    else { $GStreamerRoot = "C:\gstreamer\1.0\msvc_x86_64" }
}
$GstBin = Join-Path $GStreamerRoot "bin"
$GstPluginDir = Join-Path $GStreamerRoot "lib\gstreamer-1.0"
Write-Host "GStreamerRoot: $GStreamerRoot"
if (!(Test-Path $GstBin)) { throw "缺少 bin 目录" }
if (!(Test-Path $GstPluginDir)) { throw "缺少 plugin 目录" }
$RequiredPlugins = @("gstcoreelements.dll","gstplayback.dll","gstapp.dll","gstvideoconvertscale.dll","gstaudioconvert.dll","gstaudioresample.dll","gstisomp4.dll","gstmatroska.dll","gstlibav.dll")
foreach ($plugin in $RequiredPlugins) { $path = Join-Path $GstPluginDir $plugin; if (Test-Path $path) { Write-Host "OK  $plugin" -ForegroundColor Green } else { Write-Host "MISS $plugin" -ForegroundColor Red } }
