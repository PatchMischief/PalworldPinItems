param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Palworld')
$ErrorActionPreference = 'Stop'
$taskGameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$taskBinary = Join-Path $taskGameRoot 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe'
if (-not (Test-Path -LiteralPath $taskBinary)) { throw 'This is not a Windows Palworld installation.' }
if (Get-Process -Name 'Palworld*' -ErrorAction SilentlyContinue) { throw 'Close Palworld before installing.' }
$taskLoader = Join-Path $taskGameRoot 'Pal/Binaries/Win64/ue4ss'
if (-not (Test-Path -LiteralPath "$taskLoader/UE4SS.dll")) { throw 'Install the Palworld-compatible UE4SS loader first.' }
$taskPak = Join-Path $PSScriptRoot 'build/PalworldPinItems_P.pak'
if (-not (Test-Path -LiteralPath $taskPak)) { throw 'Run Build.ps1 first.' }
$taskMod = Join-Path $taskLoader 'Mods/PalworldPinItems'
$taskPaks = Join-Path $taskGameRoot 'Pal/Content/Paks'
$taskInstalledPak = Join-Path $taskPaks 'PalworldPinItems_P.pak'
if ((Test-Path -LiteralPath $taskMod) -or (Test-Path -LiteralPath $taskInstalledPak)) {
    $taskBackup = Join-Path $PSScriptRoot ('build/previous-install/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $taskBackup | Out-Null
    if (Test-Path -LiteralPath $taskMod) { Copy-Item -LiteralPath $taskMod -Destination $taskBackup -Recurse }
    if (Test-Path -LiteralPath $taskInstalledPak) { Copy-Item -LiteralPath $taskInstalledPak -Destination $taskBackup }
}
New-Item -ItemType Directory -Force -Path "$taskMod/Scripts",$taskPaks | Out-Null
Copy-Item -LiteralPath "$PSScriptRoot/Scripts/main.lua","$PSScriptRoot/Scripts/recipes.lua" -Destination "$taskMod/Scripts" -Force
Set-Content -LiteralPath "$taskMod/enabled.txt" -Value ''
Copy-Item -LiteralPath $taskPak -Destination $taskInstalledPak -Force
$taskList = Join-Path $taskLoader 'Mods/mods.txt'
if (Test-Path -LiteralPath $taskList) {
    $taskText = Get-Content -LiteralPath $taskList -Raw
    $taskLines = @($taskText -split '\r?\n' | Where-Object { $_ -notmatch '^\s*PalworldPinItems\s*:' })
    ($taskLines + 'PalworldPinItems : 1') | Set-Content -LiteralPath $taskList -Encoding utf8
}
Write-Output "Installed PalworldPinItems into $taskGameRoot"
