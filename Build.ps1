param([string]$EngineRoot = 'C:\Program Files\Epic Games\UE_5.1', [switch]$CreateZip)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskProject = Join-Path $taskRoot 'PalworldPinItems.uproject'
$taskEditor = Join-Path $EngineRoot 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe'
$taskPakTool = Join-Path $EngineRoot 'Engine/Binaries/Win64/UnrealPak.exe'
$taskOutput = Join-Path $taskRoot 'build'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
# Single-package mode ignores CookDir; list each owned asset package explicitly.
$taskAssets = Get-ChildItem -LiteralPath (Join-Path $taskRoot 'Content/Mods/PalworldPinItems') -File -Recurse -Filter '*.uasset' | ForEach-Object {
    '/Game/' + [IO.Path]::GetRelativePath((Join-Path $taskRoot 'Content'), $_.FullName).Replace('\','/').Replace('.uasset','')
}
if (-not $taskAssets) { throw 'No mod assets to cook' }
& $taskEditor $taskProject -run=Cook -TargetPlatform=Windows "-Package=$($taskAssets -join '+')" -CookSinglePackageNoRefs -unattended -NoSound -NullRHI -UTF8Output -abslog="$taskOutput/cook.log"
if ($LASTEXITCODE -ne 0) { throw "Cook failed: $LASTEXITCODE. See build/cook.log." }
$taskCooked = Join-Path $taskRoot 'Saved/Cooked/Windows/PalworldPinItems/Content/Mods/PalworldPinItems'
$taskFiles = Get-ChildItem -LiteralPath $taskCooked -File -Recurse
if (-not ($taskFiles | Where-Object Name -eq 'WBP_PinItems.uasset')) { throw 'Cooked widget missing' }
$taskResponse = $taskFiles | ForEach-Object {
    $taskRelative = [IO.Path]::GetRelativePath($taskCooked, $_.FullName).Replace('\','/')
    '"' + $_.FullName + '" "../../../Pal/Content/Mods/PalworldPinItems/' + $taskRelative + '"'
}
$taskResponse | Set-Content -LiteralPath "$taskOutput/pak-response.txt" -Encoding utf8
& $taskPakTool "$taskOutput/PalworldPinItems_P.pak" "-Create=$taskOutput/pak-response.txt" -compress
if ($LASTEXITCODE -ne 0) { throw "Pak creation failed: $LASTEXITCODE" }
$taskPackage = Join-Path $taskOutput 'package'
$taskLua = Join-Path $taskPackage 'Pal/Binaries/Win64/ue4ss/Mods/PalworldPinItems/Scripts'
$taskPaks = Join-Path $taskPackage 'Pal/Content/Paks'
New-Item -ItemType Directory -Force -Path $taskLua,$taskPaks | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'Scripts/main.lua'),(Join-Path $taskRoot 'Scripts/recipes.lua') -Destination $taskLua -Force
Set-Content -LiteralPath (Join-Path (Split-Path $taskLua) 'enabled.txt') -Value ''
Copy-Item -LiteralPath "$taskOutput/PalworldPinItems_P.pak" -Destination $taskPaks -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'README.md') -Destination $taskPackage -Force
if ($CreateZip) {
    Compress-Archive -Path "$taskPackage/*" -DestinationPath "$taskOutput/PalworldPinItems.zip" -Force
    Write-Output "Built $taskOutput/PalworldPinItems.zip"
} else {
    Write-Output "Built $taskOutput/PalworldPinItems_P.pak and $taskPackage"
}
