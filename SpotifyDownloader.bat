<# :
@echo off
setlocal EnableExtensions
cd /d "%~dp0"

:: =========================================================
::                 MODE DETECTION & LOGIC
:: =========================================================

:: 1. CHECK FOR REPAIR MODE (Running from 'installation' folder)
echo "%~dp0" | find /i "\installation\" >nul
if %errorlevel% equ 0 goto :RepairMode

:: 2. NORMAL MODE: SELF-CONTAINMENT & BACKUP
for %%I in (.) do set "DirName=%%~nxI"

:: A. Auto-Create Main Folder if loose
echo "%DirName%" | find /i "SpotifyPlaylistDownloader" >nul
if %errorlevel% neq 0 (
    if not exist "SpotifyPlaylistDownloader" mkdir "SpotifyPlaylistDownloader"
    copy /y "%~f0" "SpotifyPlaylistDownloader\SpotifyDownloader.bat" >nul
    if exist "libs" move "libs" "SpotifyPlaylistDownloader" >nul
    start "" "SpotifyPlaylistDownloader\SpotifyDownloader.bat"
    del "%~f0" & exit
)

:: B. Create Backup/Installation Folder
if not exist "installation" mkdir "installation"

:: C. Backup Launcher
copy /y "%~f0" "installation\Repair_Launcher.bat" >nul

:: D. Backup Libs (Mirroring - only copies new/changed files)
if exist "libs" (
    if not exist "installation\libs" mkdir "installation\libs"
    xcopy "libs" "installation\libs" /E /I /Y /D /Q >nul
)

:: E. Run Application
if not exist "src" mkdir "src"
set "PS_SCRIPT=src\Loader_%RANDOM%.ps1"

:: DIRECT COPY METHOD (Zero Parsing - Impossible to break)
copy /y "%~f0" "%PS_SCRIPT%" >nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
if exist "%PS_SCRIPT%" del "%PS_SCRIPT%"
exit

:: =========================================================
::                    REPAIR LOGIC
:: =========================================================
:RepairMode
cls
color 0E
echo ========================================================
echo             REPAIRING SPOTIFY DOWNLOADER
echo ========================================================
echo.
echo [1/3] Restoring Launcher...
copy /y "%~f0" "..\SpotifyDownloader.bat" >nul

echo [2/3] Restoring Libraries...
if exist "libs" (
    xcopy "libs" "..\libs" /E /I /Y /D /Q >nul
) else (
    echo WARNING: No backup libs found in installation folder!
)

echo [3/3] Done.
echo.
echo Restoration Complete. You can close this window.
pause
exit
#>

# ==========================================================
#           POWERSHELL APPLICATION STARTS HERE
# ==========================================================
param([string]$SpotifyUrl = "")

$ErrorActionPreference = "SilentlyContinue"
$scriptDir = Split-Path -Parent $PSCommandPath
$baseDir   = $scriptDir
if ($baseDir.EndsWith("src")) { $baseDir = Split-Path $baseDir -Parent }

# --- CONFIGURATION LOADER ---
$configFile = Join-Path $baseDir "config.txt"
$defaultDownloadPath = "SpotifyDownloads"

if (-not (Test-Path $configFile)) {
    $defaultConfig = @"
# Spotify Downloader Configuration; Default: DownloadPath=SpotifyDownloads
# Change the path below to set your download location. Example below.
# DownloadPath=D:\Music\Spotify Backup
DownloadPath=$defaultDownloadPath
"@
    Set-Content -Path $configFile -Value $defaultConfig -Encoding UTF8
}

$configContent = Get-Content -Path $configFile -Raw
$targetPath = $defaultDownloadPath
foreach ($line in ($configContent -split "`r`n")) {
    if ($line -match "^DownloadPath=(.*)") {
        $targetPath = $matches[1].Trim()
    }
}

if ([System.IO.Path]::IsPathRooted($targetPath)) {
    $downloadDir = $targetPath
} else {
    $downloadDir = Join-Path $baseDir $targetPath
}

# --- LIBRARY LOADER ---
$libDir = Join-Path $baseDir 'libs'
if (-not (Test-Path $libDir)) {
    $parentLibs = Join-Path (Split-Path $baseDir -Parent) 'libs'
    if (Test-Path $parentLibs) { $libDir = $parentLibs }
}

$pythonExe = Join-Path $libDir "python.exe"
$ffmpegExe = Join-Path $libDir "ffmpeg.exe"
$env:PYTHONPATH = $libDir 
$env:PATH = "$libDir;$env:PATH"

function Initialize-Directories {
    if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null }
}

function Get-Url {
    if ($SpotifyUrl) { return $SpotifyUrl }
    Add-Type -AssemblyName PresentationFramework
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Spotify Downloader | Mr. Wise" Height="200" Width="450" Background="#121212" WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
 <StackPanel Margin="20">
  <TextBlock Text="Paste Spotify URL" Foreground="White" FontSize="14" Margin="0,0,0,10"/>
  <TextBox Name="UrlInput" Background="#282828" Foreground="White" CaretBrush="White" BorderBrush="#1DB954" Padding="6"/>
  <Button Name="Go" Content="Download" Height="32" Margin="0,20,0,0" Background="#1DB954" Foreground="White" BorderThickness="0"/>
 </StackPanel>
</Window>
'@
    $r = New-Object System.Xml.XmlNodeReader $xaml
    $w = [Windows.Markup.XamlReader]::Load($r)
    $btn = $w.FindName('Go')
    $tb  = $w.FindName('UrlInput')
    $btn.Add_Click({ $global:u = $tb.Text; $w.Close() })
    $w.ShowDialog() | Out-Null
    return $global:u
}

function Invoke-Download {
    param($url)
    Clear-Host
    Write-Host "Spotify Downloader | Mr. Wise" -ForegroundColor Green
    Write-Host "Github: https://github.com/WiseDodge" -ForegroundColor DarkGray
    Write-Host "Saving to: $downloadDir" -ForegroundColor Gray
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    
    $outputTemplate = Join-Path $downloadDir "{list-name}\{artists} - {title}.{output-ext}"

    try {
        $ErrorActionPreference = "Continue"
        if (Test-Path $pythonExe) {
            $args = @('-m','spotdl','download',$url,'--format','mp3','--bitrate','320k','--output',$outputTemplate,'--ffmpeg',$ffmpegExe,'--simple-tui')
            & $pythonExe @args
        } else {
            Write-Host "CRITICAL ERROR: Portable 'libs' not found!" -ForegroundColor Red
            Write-Host "Missing: $pythonExe" -ForegroundColor Red
            Write-Host "Please run the Repair_Launcher.bat file in the 'installation' folder." -ForegroundColor Yellow
            Read-Host "Press Enter to exit..."
            Stop-Process -Id $PID -Force
        }
    } catch {
        Write-Error "Execution Failed: $_"
        Read-Host "Press Enter to exit..."
    }
    
    Write-Host "`nDone." -ForegroundColor Cyan
    Stop-Process -Name "ffmpeg" -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $PID -Force
}

try { Set-Location -Path $scriptDir } catch {}
Initialize-Directories
$url = Get-Url
if ($url) { Invoke-Download $url }