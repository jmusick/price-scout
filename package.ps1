# Packs dist\PriceScout.ba2 and packaging\README.txt into dist\PriceScout-<version>.zip, the file
# uploaded to Nexus Mods and attached to the GitHub Release. The version is PriceScout.BUILD.
# The archive has the ba2 at its root, so its root is the game's Data folder. Run .\build.ps1 first.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$match = Select-String -Path src\scripts\PriceScout.as -Pattern 'BUILD:String\s*=\s*"([^"]+)"'
if (-not $match) { throw "BUILD not found in src\scripts\PriceScout.as" }
$version = $match.Matches[0].Groups[1].Value
if (-not (Test-Path dist\PriceScout.ba2)) { throw "dist\PriceScout.ba2 not found; run .\build.ps1 first" }

$stage = "build\package"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item dist\PriceScout.ba2 $stage

# CRLF, so the readme opens cleanly in Notepad.
$readme = (Get-Content packaging\README.txt) -join "`r`n"
$readme = $readme.Replace("{{VERSION}}", $version) + "`r`n"
[IO.File]::WriteAllText((Join-Path $PWD "$stage\PriceScout_README.txt"), $readme, (New-Object System.Text.UTF8Encoding($false)))

$zip = "dist\PriceScout-$version.zip"
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Write-Host "Packed $zip"
