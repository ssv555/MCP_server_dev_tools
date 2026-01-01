<#
.SYNOPSIS
    Automates sending a message to Telegram Desktop via clipboard and captures a screenshot.

.DESCRIPTION
    This script activates the Telegram window, focuses the input field (via click),
    pastes the provided text using the Clipboard (Ctrl+V), sends it (Enter),
    and saves a verification screenshot to the .tmp directory.
    
    FOR MCP AGENTS:
    - Use this script to send messages to Telegram.
    - If the message contains non-ASCII characters (Cyrillic, Emoji, etc.),
      it is HIGHLY RECOMMENDED to encode the string in Base64 (UTF-8) and pass it with the -Base64 switch.
      This avoids shell encoding issues.

.PARAMETER Message
    The message text to send. Can be plain text or Base64 encoded string.
    Default: "Test Message"

.PARAMETER Base64
    Switch to indicate that the Message parameter is Base64 encoded.
    
.EXAMPLE
    # Send plain text
    .\send_telegram_v7.ps1 -Message "Hello World"
    
.EXAMPLE
    # Send Russian text (Base64 encoded "Привет")
    .\send_telegram_v7.ps1 -Message "0J/RgNC40LLQtdGC" -Base64
#>
param(
    [string]$Message = "Test Message",
    [switch]$Base64
)

$source = @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

namespace NativeMethods {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static class Win32 {
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint cButtons, uint dwExtraInfo);
        
        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int X, int Y);
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing, System.Windows.Forms

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# --- CONFIGURATION LOADING ---
$ConfigFile = Join-Path $PSScriptRoot "..\..\config.json"
$TelegramPath = $null
if (Test-Path $ConfigFile) {
    try {
        $ConfigRaw = Get-Content $ConfigFile | ConvertFrom-Json
        # Check for nested "telegram" key (new structure)
        if ($ConfigRaw.telegram) {
            $Config = $ConfigRaw.telegram
        } else {
            $Config = $ConfigRaw
        }

        $TelegramPath = $Config.TelegramPath
        # Fallback to default client if TelegramPath is not explicitly set but clients are
        if (-not $TelegramPath -and $Config.clients -and $Config.default) {
            $defaultKey = "$($Config.default)"
            $TelegramPath = $Config.clients.$defaultKey
        }
        Write-Output "Loaded configuration. Using Telegram at: $TelegramPath"
    } catch {
        Write-Warning "Could not read configuration file."
    }
}

Write-Output "Searching for Telegram process..."
$procs = Get-Process Telegram -ErrorAction SilentlyContinue
$proc = $procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1

if (-not $proc) {
    Write-Output "Telegram process not found. Attempting to launch..."
    
    if (-not $TelegramPath) {
        # Fallback search if no config
        $possiblePaths = @(
            "$env:APPDATA\Telegram Desktop\Telegram.exe",
            "D:\Data\Tools\Telegram\Telegram +79990711101 - My\Telegram.exe",
            "D:\Data\Tools\Telegram\Telegram +79660091975 - SOU\Telegram.exe"
        )
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $TelegramPath = $path
                break
            }
        }
    }

    if ($TelegramPath -and (Test-Path $TelegramPath)) {
        Write-Output "Launching Telegram from: $TelegramPath"
        Start-Process $TelegramPath
        Write-Output "Telegram launched. Waiting for window to initialize..."
        # Wait loop for process and window
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            $procs = Get-Process Telegram -ErrorAction SilentlyContinue
            $proc = $procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
            if ($proc) { break }
        }
    } else {
        Write-Error "Telegram executable not found. Please run 'scripts\setup_telegram.ps1' to configure the path."
        exit 1
    }
}

if (-not $proc) {
    Write-Error "Telegram process could not be started or found."
    exit 1
}
$hwnd = $proc.MainWindowHandle
Write-Output "Found Telegram (Handle: $hwnd)"

Write-Output "Activating window..."
[NativeMethods.Win32]::ShowWindow($hwnd, 9)
[NativeMethods.Win32]::SetForegroundWindow($hwnd)
Start-Sleep -Seconds 1

# --- LOCK SCREEN DETECTION ---
Write-Output "Checking for Lock Screen..."
try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if ($root) {
        $maxWaitSeconds = 30
        $waited = 0
        
        do {
            $isLocked = $false
            
            # Method 1: Search specifically for "Passcode" or "Password" labels/edits
            $condProp = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Passcode")
            $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condProp)
            if ($el) { $isLocked = $true; Write-Warning "Detected Lock Indicator: 'Passcode'" }
    
            if (-not $isLocked) {
                 # Method 2: Search for Russian equivalents
                $condProp = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Код доступа")
                $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condProp)
                if ($el) { $isLocked = $true; Write-Warning "Detected Lock Indicator: 'Код доступа'" }
            }
    
            if (-not $isLocked) {
                 # Method 3: Search for "Confirm" button (Подтвердить)
                 $condProp = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Подтвердить")
                 $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condProp)
                 if ($el) { $isLocked = $true; Write-Warning "Detected Lock Indicator: 'Подтвердить'" }
            }
            
            # Method 4: Check if any Edit control is a Password field
            if (-not $isLocked) {
                 $condType = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
                 $edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condType)
                 foreach ($edit in $edits) {
                     # Not all elements support ValuePattern, checking IsPassword if available
                     $isPwd = $edit.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsPasswordProperty)
                     if ($isPwd -eq $true) {
                         $isLocked = $true
                         Write-Warning "Detected Lock Indicator: Edit control with IsPassword=True"
                         break
                     }
                 }
            }
            
            # Method 5: Fallback - Scan for typical text (broader search)
            if (-not $isLocked) {
                $allTextCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
                $allTexts = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $allTextCond)
                foreach ($t in $allTexts) {
                    $n = $t.Current.Name
                    if ($n -match "Введите код" -or $n -match "Enter passcode" -or $n -match "Two-Step Verification") {
                         $isLocked = $true
                         Write-Warning "Detected Lock Indicator: Text '$n'"
                         break
                    }
                }
            }
            
            if ($isLocked) {
                if ($waited -lt $maxWaitSeconds) {
                    Write-Warning "TELEGRAM IS LOCKED! Waiting for manual unlock... ($waited/$maxWaitSeconds)"
                    Start-Sleep -Seconds 1
                    $waited++
                    try { $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd) } catch {}
                    continue
                }
                
                Write-Error "TELEGRAM IS LOCKED! Please unlock it manually."
                # Capture screenshot of locked state
                $timestamp = Get-Date -Format "yyyy.MM.dd_HH.mm.ss.fff"
                $filename = "$timestamp`_LOCKED_Telegram.png"
                $path = Join-Path $PSScriptRoot "..\..\.tmp\$filename"
                
                $rect = New-Object NativeMethods.RECT
                [NativeMethods.Win32]::GetWindowRect($hwnd, [ref]$rect)
                $width = $rect.Right - $rect.Left
                $height = $rect.Bottom - $rect.Top
                
                if ($width -gt 0 -and $height -gt 0) {
                    $bmp = New-Object System.Drawing.Bitmap $width, $height
                    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
                    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
                    $graphics.Dispose()
                    $bmp.Dispose()
                    Write-Output "Screenshot of locked state saved to: $path"
                }
                exit 1
            } else {
                Write-Output "Telegram appears unlocked. Proceeding..."
                break
            }
            
        } while ($waited -le $maxWaitSeconds)
    }
} catch {
    Write-Warning "Could not verify lock state via UIAutomation. Proceeding with caution..."
    Write-Warning $_.Exception.Message
}

$rect = New-Object NativeMethods.RECT
[NativeMethods.Win32]::GetWindowRect($hwnd, [ref]$rect)

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

Write-Output "Searching for Message Input Field via UIAutomation..."
$inputFound = $false

try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if ($root) {
        $condType = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
        $edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condType)
        
        # Sort by Top to find the bottom-most one (Message Input)
        $targetEdit = $null
        $maxTop = 0
        
        foreach ($edit in $edits) {
            try {
                $b = $edit.Current.BoundingRectangle
                # Ensure it's not off-screen or empty
                if ($b.Width -gt 0 -and $b.Height -gt 0) {
                     if ($b.Top -gt $maxTop) {
                        $maxTop = $b.Top
                        $targetEdit = $edit
                    }
                }
            } catch {}
        }
        
        if ($targetEdit) {
            $b = $targetEdit.Current.BoundingRectangle
            $centerX = $b.Left + ($b.Width / 2)
            $centerY = $b.Top + ($b.Height / 2)
            
            # Check if coordinates are reasonable (inside window rect)
            if ($centerY -gt $rect.Top -and $centerY -lt $rect.Bottom) {
                Write-Output "Found Input Field via UIAutomation at: $centerX, $centerY"
                [NativeMethods.Win32]::SetCursorPos([int]$centerX, [int]$centerY)
                Start-Sleep -Milliseconds 200
                [NativeMethods.Win32]::mouse_event(0x02, 0, 0, 0, 0)
                [NativeMethods.Win32]::mouse_event(0x04, 0, 0, 0, 0)
                $inputFound = $true
            }
        }
    }
} catch {
    Write-Warning "UIAutomation search for input failed: $_"
}

if (-not $inputFound) {
    # Fallback to coordinates
    $inputX = $rect.Left + ($width / 2)
    $inputY = $rect.Bottom - 55
    Write-Output "Fallback: Clicking Input Field at: $inputX, $inputY"
    [NativeMethods.Win32]::SetCursorPos($inputX, $inputY)
    Start-Sleep -Milliseconds 200
    [NativeMethods.Win32]::mouse_event(0x02, 0, 0, 0, 0)
    [NativeMethods.Win32]::mouse_event(0x04, 0, 0, 0, 0)
}
Start-Sleep -Milliseconds 500

Write-Output "Setting clipboard text..."
if ($Base64) {
    try {
        Write-Output "Decoding Base64 message..."
        $textBytes = [System.Convert]::FromBase64String($Message)
        $text = [System.Text.Encoding]::UTF8.GetString($textBytes)
    } catch {
        Write-Error "Invalid Base64 string provided."
        exit 1
    }
} else {
    $text = $Message
}

[System.Windows.Forms.Clipboard]::SetText($text)
Start-Sleep -Milliseconds 500

Write-Output "Pasting text..."
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 2

Write-Output "Capturing window..."
$bmp = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)

$now = Get-Date -Format "yyyy.MM.dd_HH.mm.ss.fff"
$filename = "$($now)_capture_TelegramWindow.png"
$tmpDir = Join-Path $PSScriptRoot "..\..\.tmp"
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
$savePath = Join-Path $tmpDir $filename

$bmp.Save($savePath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "Screenshot saved to: $savePath"

$graphics.Dispose()
$bmp.Dispose()
