
$paths = @()
$appData = "$env:APPDATA\Telegram Desktop\Telegram.exe"
if (Test-Path $appData) { $paths += $appData }

$toolsPath = "D:\Data\Tools\Telegram"
if (Test-Path $toolsPath) {
    $tools = Get-ChildItem -Path $toolsPath -Recurse -Filter "Telegram.exe" -ErrorAction SilentlyContinue
    if ($tools) {
        foreach ($t in $tools) {
            $paths += $t.FullName
        }
    }
}

$uniquePaths = $paths | Select-Object -Unique
Write-Output "FOUND_PATHS_START"
$uniquePaths
Write-Output "FOUND_PATHS_END"
