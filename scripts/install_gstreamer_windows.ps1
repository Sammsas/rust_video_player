param(
    [string]$Version = "1.26.8",
    [string]$InstallRoot = "C:\gstreamer\1.0\msvc_x86_64",
    [string]$CacheDir = "C:\downloads",
    [ValidateSet("Auto", "Msi", "Exe")]
    [string]$InstallerKind = "Auto",
    [int]$TimeoutSeconds = 900,
    [switch]$ExportGitHubEnv
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$Text) {
    Write-Host ""
    Write-Host "========== $Text ==========" -ForegroundColor Cyan
}

function Add-GitHubEnvLine([string]$Line) {
    if ($ExportGitHubEnv -and $env:GITHUB_ENV) {
        $Line | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    }
}

function Add-GitHubPathLine([string]$Line) {
    if ($ExportGitHubEnv -and $env:GITHUB_PATH) {
        $Line | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
    }
}

function Test-RemoteFile([string]$Url) {
    try {
        $response = Invoke-WebRequest `
            -Uri $Url `
            -Method Head `
            -UseBasicParsing `
            -TimeoutSec 60

        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    } catch {
        return $false
    }
}

function Invoke-DownloadFile([string]$Url, [string]$OutFile) {
    Write-Host "Downloading:"
    Write-Host "  $Url"
    Write-Host "To:"
    Write-Host "  $OutFile"

    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

    if (Test-Path $OutFile) {
        $existing = Get-Item $OutFile
        if ($existing.Length -gt 1024) {
            Write-Host "Using cached file: $OutFile" -ForegroundColor Green
            return
        }

        Remove-Item $OutFile -Force
    }

    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $OutFile `
        -UseBasicParsing `
        -TimeoutSec 300

    if (!(Test-Path $OutFile)) {
        throw "Download failed: $OutFile"
    }

    $file = Get-Item $OutFile
    if ($file.Length -le 1024) {
        throw "Downloaded file is too small, probably invalid: $OutFile"
    }

    Write-Host "Downloaded size: $($file.Length) bytes"
}

function Wait-ProcessWithTimeout(
    [System.Diagnostics.Process]$Process,
    [int]$TimeoutSeconds,
    [string]$NameForLog
) {
    Write-Host "Waiting for $NameForLog, timeout = $TimeoutSeconds seconds..."

    $completed = $Process.WaitForExit($TimeoutSeconds * 1000)

    if (-not $completed) {
        Write-Warning "$NameForLog timed out. Killing process..."

        try {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        } catch {}

        throw "$NameForLog timed out after $TimeoutSeconds seconds"
    }

    Write-Host "$NameForLog exit code: $($Process.ExitCode)"

    if ($Process.ExitCode -ne 0) {
        throw "$NameForLog failed with exit code $($Process.ExitCode)"
    }
}

function Install-GStreamerMsi(
    [string]$Version,
    [string]$InstallRoot,
    [string]$CacheDir,
    [int]$TimeoutSeconds
) {
    Write-Section "Installing GStreamer by MSI"

    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

    $baseUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/$Version/msvc"

    $runtimeUrl = "$baseUrl/gstreamer-1.0-msvc-x86_64-$Version.msi"
    $develUrl = "$baseUrl/gstreamer-1.0-devel-msvc-x86_64-$Version.msi"

    if (!(Test-RemoteFile $runtimeUrl)) {
        throw "Runtime MSI not found: $runtimeUrl"
    }

    if (!(Test-RemoteFile $develUrl)) {
        throw "Development MSI not found: $develUrl"
    }

    $runtimeMsi = Join-Path $CacheDir "gstreamer-runtime-$Version.msi"
    $develMsi = Join-Path $CacheDir "gstreamer-devel-$Version.msi"

    $runtimeLog = Join-Path $CacheDir "gstreamer-runtime-install.log"
    $develLog = Join-Path $CacheDir "gstreamer-devel-install.log"

    Invoke-DownloadFile -Url $runtimeUrl -OutFile $runtimeMsi
    Invoke-DownloadFile -Url $develUrl -OutFile $develMsi

    Write-Host "Installing Runtime MSI..."

    $runtimeArgs = @(
        "/i", "`"$runtimeMsi`"",
        "/qn",
        "/norestart",
        "INSTALLDIR=`"$InstallRoot`"",
        "ADDLOCAL=ALL",
        "/L*v", "`"$runtimeLog`""
    )

    $p1 = Start-Process `
        -FilePath "msiexec.exe" `
        -ArgumentList $runtimeArgs `
        -PassThru `
        -NoNewWindow

    Wait-ProcessWithTimeout `
        -Process $p1 `
        -TimeoutSeconds $TimeoutSeconds `
        -NameForLog "GStreamer Runtime MSI installer"

    Write-Host "Installing Development MSI..."

    $develArgs = @(
        "/i", "`"$develMsi`"",
        "/qn",
        "/norestart",
        "INSTALLDIR=`"$InstallRoot`"",
        "ADDLOCAL=ALL",
        "/L*v", "`"$develLog`""
    )

    $p2 = Start-Process `
        -FilePath "msiexec.exe" `
        -ArgumentList $develArgs `
        -PassThru `
        -NoNewWindow

    Wait-ProcessWithTimeout `
        -Process $p2 `
        -TimeoutSeconds $TimeoutSeconds `
        -NameForLog "GStreamer Development MSI installer"
}

function Install-GStreamerExe(
    [string]$Version,
    [string]$InstallRoot,
    [string]$CacheDir,
    [int]$TimeoutSeconds
) {
    Write-Section "Installing GStreamer by EXE"

    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

    $installerUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/$Version/msvc/gstreamer-1.0-msvc-x86_64-$Version.exe"

    if (!(Test-RemoteFile $installerUrl)) {
        throw "EXE installer not found: $installerUrl"
    }

    $installerPath = Join-Path $CacheDir "gstreamer-1.0-msvc-x86_64-$Version.exe"
    $installLog = Join-Path $CacheDir "gstreamer-exe-install.log"

    Invoke-DownloadFile -Url $installerUrl -OutFile $installerPath

    $args = @(
        "/SP-",
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/NOCANCEL",
        "/TYPE=devel",
        "/DIR=`"$InstallRoot`"",
        "/LOG=`"$installLog`""
    )

    $p = Start-Process `
        -FilePath $installerPath `
        -ArgumentList $args `
        -PassThru `
        -NoNewWindow

    Wait-ProcessWithTimeout `
        -Process $p `
        -TimeoutSeconds $TimeoutSeconds `
        -NameForLog "GStreamer EXE installer"
}

function Verify-GStreamer([string]$InstallRoot) {
    Write-Section "Verifying GStreamer"

    $GstBin = Join-Path $InstallRoot "bin"
    $GstPluginDir = Join-Path $InstallRoot "lib\gstreamer-1.0"
    $GstInspect = Join-Path $GstBin "gst-inspect-1.0.exe"

    if (!(Test-Path $GstBin)) {
        throw "GStreamer bin directory not found: $GstBin"
    }

    if (!(Test-Path $GstPluginDir)) {
        throw "GStreamer plugin directory not found: $GstPluginDir"
    }

    if (!(Test-Path $GstInspect)) {
        throw "gst-inspect-1.0.exe not found: $GstInspect"
    }

    $env:PATH = "$GstBin;$env:PATH"
    $env:GSTREAMER_1_0_ROOT_MSVC_X86_64 = $InstallRoot
    $env:GST_PLUGIN_PATH = $GstPluginDir
    $env:GST_PLUGIN_SYSTEM_PATH_1_0 = $GstPluginDir

    $registryPath = Join-Path $env:TEMP "gst-registry-actions.bin"
    $env:GST_REGISTRY = $registryPath

    Add-GitHubPathLine $GstBin
    Add-GitHubEnvLine "GSTREAMER_1_0_ROOT_MSVC_X86_64=$InstallRoot"
    Add-GitHubEnvLine "GST_PLUGIN_PATH=$GstPluginDir"
    Add-GitHubEnvLine "GST_PLUGIN_SYSTEM_PATH_1_0=$GstPluginDir"
    Add-GitHubEnvLine "GST_REGISTRY=$registryPath"

    Write-Host "Root:     $InstallRoot"
    Write-Host "Bin:      $GstBin"
    Write-Host "Plugins:  $GstPluginDir"
    Write-Host "Registry: $registryPath"

    & $GstInspect --version

    if ($LASTEXITCODE -ne 0) {
        throw "gst-inspect-1.0 --version failed"
    }
}

Write-Section "GStreamer installer configuration"

Write-Host "Version:       $Version"
Write-Host "InstallRoot:   $InstallRoot"
Write-Host "CacheDir:      $CacheDir"
Write-Host "InstallerKind: $InstallerKind"
Write-Host "Timeout:       $TimeoutSeconds seconds"

if (Test-Path (Join-Path $InstallRoot "bin\gst-inspect-1.0.exe")) {
    Write-Host "GStreamer already exists at $InstallRoot, skipping installation." -ForegroundColor Green
} else {
    if ($InstallerKind -eq "Msi") {
        Install-GStreamerMsi `
            -Version $Version `
            -InstallRoot $InstallRoot `
            -CacheDir $CacheDir `
            -TimeoutSeconds $TimeoutSeconds
    } elseif ($InstallerKind -eq "Exe") {
        Install-GStreamerExe `
            -Version $Version `
            -InstallRoot $InstallRoot `
            -CacheDir $CacheDir `
            -TimeoutSeconds $TimeoutSeconds
    } else {
        try {
            Install-GStreamerMsi `
                -Version $Version `
                -InstallRoot $InstallRoot `
                -CacheDir $CacheDir `
                -TimeoutSeconds $TimeoutSeconds
        } catch {
            Write-Warning "MSI install path failed: $($_.Exception.Message)"
            Write-Warning "Trying EXE installer..."

            Install-GStreamerExe `
                -Version $Version `
                -InstallRoot $InstallRoot `
                -CacheDir $CacheDir `
                -TimeoutSeconds $TimeoutSeconds
        }
    }
}

Verify-GStreamer -InstallRoot $InstallRoot

Write-Section "GStreamer installation ready"