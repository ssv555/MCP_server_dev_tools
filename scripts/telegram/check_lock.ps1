
param(
    [string]$ProcessName = "Telegram"
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$proc = Get-Process $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) {
    Write-Output "Telegram not running"
    exit 0
}

$root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
if (-not $root) {
    Write-Output "Could not attach to window"
    exit 0
}

# Find all Edit controls
$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
$edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)

$isLocked = $false
$lockReason = ""

foreach ($edit in $edits) {
    $name = $edit.Current.Name
    if ($name -match "Passcode" -or $name -match "Password" -or $name -match "Код доступа" -or $name -match "Пароль") {
        $isLocked = $true
        $lockReason = "Found Edit control with name: $name"
        break
    }
}

# Alternative: Check for "Lock" icon or specific text
if (-not $isLocked) {
    $textCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $texts = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCondition)
    foreach ($text in $texts) {
        if ($text.Current.Name -match "Enter passcode" -or $text.Current.Name -match "Введите код") {
            $isLocked = $true
            $lockReason = "Found Text control: $($text.Current.Name)"
            break
        }
    }
}

if ($isLocked) {
    Write-Output "LOCKED: $lockReason"
} else {
    Write-Output "UNLOCKED"
}
