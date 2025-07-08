```powershell
# Install-iPhoneTools.ps1
# Installs libimobiledevice and defines iPhone log management functions for Windows.

# Ensure running with sufficient permissions
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script requires administrative privileges to modify PATH. Run PowerShell as Administrator or manually add libimobiledevice to PATH."
}

# Prompt for directory configuration
Write-Host "Set directories for iPhone logs (press Enter or 'e' for defaults, or input custom paths):"
Write-Host "Default LiveLogs: D:\GNO-DATA\iPhone\LiveLogs"
Write-Host "Default ExtractedLogs: D:\GNO-DATA\iPhone\ExtractedLogs"
Write-Host "Default DeviceInfo: D:\GNO-DATA\iPhone\DeviceInfo"
$input = Read-Host "Press Enter or 'e' for defaults, or type 'custom' for custom paths"

if ($input -eq '' -or $input -eq 'e') {
    $liveLogsDir = "D:\GNO-DATA\iPhone\LiveLogs"
    $extractedLogsDir = "D:\GNO-DATA\iPhone\ExtractedLogs"
    $deviceInfoDir = "D:\GNO-DATA\iPhone\DeviceInfo"
} else {
    $liveLogsDir = Read-Host "Enter path for LiveLogs (e.g., D:\Logs\Live)"
    $extractedLogsDir = Read-Host "Enter path for ExtractedLogs (e.g., D:\Logs\Extracted)"
    $deviceInfoDir = Read-Host "Enter path for DeviceInfo (e.g., D:\Logs\Info)"
}

# Create directories
foreach ($dir in $liveLogsDir, $extractedLogsDir, $deviceInfoDir) {
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $dir)) {
        Write-Error "Failed to create directory: $dir. Ensure you have write permissions."
        exit 1
    }
}

# Install libimobiledevice
$libimobilePath = "$HOME\libimobiledevice"
if (-not (Test-Path "$libimobilePath\idevicesyslog.exe")) {
    Write-Host "Installing libimobiledevice..."
    try {
        $releaseUrl = "https://api.github.com/repos/libimobiledevice/libimobiledevice/releases/latest"
        $releaseInfo = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        $asset = $releaseInfo.assets | Where-Object { $_.name -like "libimobiledevice-win32-x86_64-*.zip" }
        if (-not $asset) {
            Write-Error "No Windows binary found in the latest libimobiledevice release."
            exit 1
        }
        $downloadUrl = $asset.browser_download_url
        $zipPath = "$HOME\Downloads\libimobiledevice.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -ErrorAction Stop
        Expand-Archive -Path $zipPath -DestinationPath $libimobilePath -Force -ErrorAction Stop
        Remove-Item $zipPath -ErrorAction SilentlyContinue
        Write-Host "libimobiledevice installed to $libimobilePath"
    } catch {
        Write-Error "Failed to download or install libimobiledevice: $_"
        exit 1
    }
}

# Add libimobiledevice to system PATH (if admin)
if ($isAdmin) {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$libimobilePath*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$libimobilePath", "Machine")
        Write-Host "Added $libimobilePath to system PATH."
    }
} else {
    Write-Warning "Run as Administrator to add $libimobilePath to system PATH, or manually add it via System Settings > Environment Variables."
}

# Define iLive function (non-verbose live logging)
function iLive {
    $devices = & "$libimobilePath\idevice_id.exe" -l
    if (-not $devices) {
        Write-Host "No iPhone detected. Connect via USB and ensure it's trusted."
        return
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logDir = "$liveLogsDir\$timestamp"
    New-Item -Path $logDir -ItemType Directory -Force
    $logFile = "$logDir\iphone_syslog_$timestamp.log"
    Write-Host "Starting live debugging. Logs saved to $logFile. Press Ctrl+C to stop."
    & "$libimobilePath\idevicesyslog.exe" | Out-File -FilePath $logFile -Append
}

# Define iLiveVerb function (verbose live logging)
function iLiveVerb {
    $devices = & "$libimobilePath\idevice_id.exe" -l
    if (-not $devices) {
        Write-Host "No iPhone detected. Connect via USB and ensure it's trusted."
        return
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logDir = "$liveLogsDir\$timestamp"
    New-Item -Path $logDir -ItemType Directory -Force
    $logFile = "$logDir\iphone_syslog_verbose_$timestamp.log"
    Write-Host "Starting verbose live debugging. Press Ctrl+C to stop."
    & "$libimobilePath\idevicesyslog.exe" | Tee-Object -FilePath $logFile
}

# Define iCopy function (copy logs)
function iCopy {
    $devices = & "$libimobilePath\idevice_id.exe" -l
    if (-not $devices) {
        Write-Host "No iPhone detected. Connect via USB and ensure it's trusted."
        return
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logDir = "$extractedLogsDir\$timestamp"
    New-Item -Path $logDir -ItemType Directory -Force
    # Collect syslog for 5 seconds
    $syslogFile = "$logDir\iphone_syslog.log"
    Write-Host "Collecting syslog..."
    $job = Start-Job -ScriptBlock { & "$using:libimobilePath\idevicesyslog.exe" }
    Start-Sleep -Seconds 5
    Stop-Job $job
    Receive-Job $job | Out-File -FilePath $syslogFile
    Remove-Job $job
    # Collect device info
    Write-Host "Collecting device info..."
    & "$libimobilePath\ideviceinfo.exe" | Out-File -FilePath "$logDir\iphone_device_info.txt"
    # Collect diagnostics
    Write-Host "Collecting diagnostics..."
    & "$libimobilePath\idevicediagnostics.exe" diagnostics | Out-File -FilePath "$logDir\iphone_diagnostics.txt"
    # Collect crash reports
    $crashDir = "$logDir\crash_reports"
    New-Item -Path $crashDir -ItemType Directory -Force
    Write-Host "Collecting crash reports..."
    & "$libimobilePath\idevicecrashreport.exe" -e $crashDir
    Write-Host "iPhone logs copied to $logDir"
}

# Define iInfo function (device information)
function iInfo {
    $devices = & "$libimobilePath\idevice_id.exe" -l
    if (-not $devices) {
        Write-Host "No iPhone detected. Connect via USB and ensure it's trusted."
        return
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $infoFile = "$deviceInfoDir\iphone_info_$timestamp.txt"
    New-Item -Path (Split-Path $infoFile -Parent) -ItemType Directory -Force
    Write-Host "Collecting device information..."
    & "$libimobilePath\ideviceinfo.exe" | Out-File -FilePath $infoFile
    Write-Host "Device info saved to $infoFile"
}

# Inform user
Write-Host "Installation complete! Functions iLive, iLiveVerb, iCopy, and iInfo are now available."
Write-Host "Usage:"
Write-Host "  iLive - Silent live logging to $liveLogsDir\<timestamp>"
Write-Host "  iLiveVerb - Verbose live logging to $liveLogsDir\<timestamp>"
Write-Host "  iCopy - Copy logs to $extractedLogsDir\<timestamp>"
Write-Host "  iInfo - Save device info to $deviceInfoDir\iphone_info_<timestamp>.txt"
Write-Host "Note: Ensure your iPhone is connected via USB and trusted."
Write-Host "If the device isn't detected, install the libusbK driver using Zadig (https://zadig.akeo.ie/)."
Write-Host "To make functions persistent, add them to your PowerShell profile:"
Write-Host "  notepad `$PROFILE"
Write-Host "  Add: . $PSScriptRoot\Install-iPhoneTools.ps1"
```
