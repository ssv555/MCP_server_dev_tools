
param(
    [switch]$Reset
)

$ConfigFile = Join-Path $PSScriptRoot "..\..\config.json"
$ConfigRaw = if (Test-Path $ConfigFile) { Get-Content $ConfigFile | ConvertFrom-Json } else { @{} }

# Ensure root "telegram" object exists for new structure
if (-not $ConfigRaw.telegram) { 
    $ConfigRaw | Add-Member -MemberType NoteProperty -Name "telegram" -Value @{} -Force
}
$Config = $ConfigRaw.telegram

# Check if already configured (check if clients and default exist)
if ($Config.clients -and $Config.default -and -not $Reset) {
    $defaultKey = "$($Config.default)"
    if ($Config.clients.$defaultKey) {
        Write-Output "Telegram already configured. Default client: $($Config.clients.$defaultKey)"
        Write-Output "Use -Reset to change."
        exit 0
    }
}

Write-Output "Searching for Telegram installations..."

$FoundPaths = @()

# 1. Standard AppData
$AppDataPath = "$env:APPDATA\Telegram Desktop\Telegram.exe"
if (Test-Path $AppDataPath) { $FoundPaths += $AppDataPath }

# 2. Known Tools Directory
$ToolsDir = "D:\Data\Tools\Telegram"
if (Test-Path $ToolsDir) {
    $ExeFiles = Get-ChildItem -Path $ToolsDir -Recurse -Filter "Telegram.exe" -ErrorAction SilentlyContinue
    foreach ($File in $ExeFiles) {
        $FoundPaths += $File.FullName
    }
}

$FoundPaths = $FoundPaths | Select-Object -Unique

if ($FoundPaths.Count -eq 0) {
    Write-Error "No Telegram installations found!"
    exit 1
}

Write-Output "`nFound Telegram installations:"
for ($i = 0; $i -lt $FoundPaths.Count; $i++) {
    Write-Output "[$i] $($FoundPaths[$i])"
}

$Selection = Read-Host "`nPlease select the Telegram client to use (enter number)"

if ($Selection -match "^\d+$" -and $Selection -lt $FoundPaths.Count) {
    $SelectedPath = $FoundPaths[$Selection]
    Write-Output "Selected: $SelectedPath"
    
    # Update config structure
    if (-not $Config.clients) { 
        $Config | Add-Member -MemberType NoteProperty -Name "clients" -Value @{} -Force
    }
    
    # Map found paths to clients
    for ($i = 0; $i -lt $FoundPaths.Count; $i++) {
        $key = "$($i + 1)" # 1-based index for user friendliness
        $Config.clients | Add-Member -MemberType NoteProperty -Name $key -Value $FoundPaths[$i] -Force
    }
    
    # Set default as integer to match user preference
    $defaultIndex = [int]$Selection + 1
    if ($Config.default) {
        $Config.default = $defaultIndex
    } else {
        $Config | Add-Member -MemberType NoteProperty -Name "default" -Value $defaultIndex -Force
    }

    # Save the whole ConfigRaw object
    $ConfigRaw | ConvertTo-Json -Depth 5 | Set-Content $ConfigFile
    Write-Output "Configuration saved to $ConfigFile"
} else {
    Write-Error "Invalid selection."
    exit 1
}
