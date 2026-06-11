param(
    [string]$Version = "1.28.3",
    [string]$InstallRoot = "C:\gstreamer\1.0\msvc_x86_64",
    [string]$CacheDir = "C:\downloads",
    [switch]$ExportGitHubEnv
)
$ErrorActionPreference = "Stop"
function Add-GitHubEnvLine([string]$Line) { if ($ExportGitHubEnv -and $env:GITHUB_ENV) { $Line | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append } }
function Add-GitHubPathLine([string]$Line) { if ($ExportGitHubEnv -and $env:GITHUB_PATH) { $Line | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append } }
function Install-GStreamerExe([string]$Version, [string]$InstallRoot, [string]$CacheDir) {
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $installerUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/$Version/msvc/gstreamer-1.0-msvc-x86_64-$Version.exe"
    $installerPath = Join-Path $CacheDir "gstreamer-1.0-msvc-x86_64-$Version.exe"
    Write-Host "Downloading GStreamer installer: $installerUrl"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
    Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/NORESTART", "/TYPE=devel", "/DIR=$InstallRoot" -Wait
}
function Install-GStreamerMsiFallback([string]$Version, [string]$InstallRoot, [string]$CacheDir) {
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $runtimeUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/$Version/msvc/gstreamer-1.0-msvc-x86_64-$Version.msi"
    $develUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/$Version/msvc/gstreamer-1.0-devel-msvc-x86_64-$Version.msi"
    $runtimeMsi = Join-Path $CacheDir "gstreamer-runtime-$Version.msi"
    $develMsi = Join-Path $CacheDir "gstreamer-devel-$Version.msi"
    Invoke-WebRequest -Uri $runtimeUrl -OutFile $runtimeMsi
    Invoke-WebRequest -Uri $develUrl -OutFile $develMsi
    Start-Process msiexec.exe -ArgumentList "/i", $runtimeMsi, "/qn", "/norestart", "INSTALLDIR=$InstallRoot" -Wait
    Start-Process msiexec.exe -ArgumentList "/i", $develMsi, "/qn", "/norestart", "INSTALLDIR=$InstallRoot" -Wait
}
if (Test-Path (Join-Path $InstallRoot "bin\gst-inspect-1.0.exe")) { Write-Host "GStreamer already exists at $InstallRoot, skipping installation." -ForegroundColor Green }
else { try { Install-GStreamerExe -Version $Version -InstallRoot $InstallRoot -CacheDir $CacheDir } catch { Write-Warning "EXE installer failed, trying MSI fallback: $($_.Exception.Message)"; Install-GStreamerMsiFallback -Version $Version -InstallRoot $InstallRoot -CacheDir $CacheDir } }
$GstBin = Join-Path $InstallRoot "bin"
$GstPluginDir = Join-Path $InstallRoot "lib\gstreamer-1.0"
if (!(Test-Path $GstBin)) { throw "GStreamer bin directory not found: $GstBin" }
if (!(Test-Path $GstPluginDir)) { throw "GStreamer plugin directory not found: $GstPluginDir" }
$env:PATH = "$GstBin;$env:PATH"
$env:GSTREAMER_1_0_ROOT_MSVC_X86_64 = $InstallRoot
$env:GST_PLUGIN_PATH = $GstPluginDir
$env:GST_PLUGIN_SYSTEM_PATH_1_0 = $GstPluginDir
Add-GitHubPathLine $GstBin
Add-GitHubEnvLine "GSTREAMER_1_0_ROOT_MSVC_X86_64=$InstallRoot"
Add-GitHubEnvLine "GST_PLUGIN_PATH=$GstPluginDir"
Add-GitHubEnvLine "GST_PLUGIN_SYSTEM_PATH_1_0=$GstPluginDir"
& (Join-Path $GstBin "gst-inspect-1.0.exe") --version
