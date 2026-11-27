# Installs (or with -Uninstall removes) the PriceScout test build.
#   - copies dist\PriceScout.ba2 into <game>\Data
#   - adds PriceScout.ba2 to sResourceArchive2List in Fallout76Custom.ini, before
#     HUDModLoader.ba2 or ChatMod.ba2, which have to stay last
#     (an existing entry after them is moved)
#   - adds PriceScout to <game>\Data\hudmodloader.ini
# Both ini files are backed up next to themselves as *.pricescout-backup the first time.
param(
    [string]$GameDir = "C:\Games\Steam\steamapps\common\Fallout76",
    [string]$CustomIni = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Fallout 76\Fallout76Custom.ini"),
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$data = Join-Path $GameDir "Data"
$customIni = $CustomIni
$hudIni = Join-Path $data "hudmodloader.ini"
$archive = "PriceScout.ba2"
$encoding = New-Object System.Text.UTF8Encoding($false)

foreach ($path in @($data, $customIni, $hudIni)) {
    if (-not (Test-Path $path)) { throw "Not found: $path" }
}

function Backup-Once([string]$path) {
    $backup = "$path.pricescout-backup"
    if (-not (Test-Path $backup)) { Copy-Item $path $backup }
}

function Save-Lines([string]$path, [string[]]$lines) {
    [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $encoding)
}

# Fallout76Custom.ini: sResourceArchive2List under [Archive]
$lines = [Collections.Generic.List[string]](Get-Content $customIni)
$index = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*sResourceArchive2List\s*=') { $index = $i; break }
}
$entries = @()
if ($index -ge 0) {
    $entries = @(($lines[$index] -replace '^[^=]*=', '').Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$original = $entries -join ", "
$entries = @($entries | Where-Object { $_ -ne $archive })
if (-not $Uninstall) {
    # HUD Mod Loader has to stay last (or Text Chat's ChatMod.ba2), so PriceScout goes before it.
    $at = $entries.Count
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ($entries[$i] -in @("HUDModLoader.ba2", "ChatMod.ba2")) { $at = $i; break }
    }
    $list = [Collections.Generic.List[string]]::new([string[]]$entries)
    $list.Insert($at, $archive)
    $entries = $list.ToArray()
}

if (($entries -join ", ") -ne $original) {
    Backup-Once $customIni
    $newLine = "sResourceArchive2List=" + ($entries -join ", ")
    if ($index -ge 0) {
        $lines[$index] = $newLine
    } else {
        $archiveSection = $lines.IndexOf("[Archive]")
        if ($archiveSection -ge 0) { $lines.Insert($archiveSection + 1, $newLine) }
        else { $lines.Add("[Archive]"); $lines.Add($newLine) }
    }
    Save-Lines $customIni $lines.ToArray()
    Write-Host "Updated $customIni"
}

# hudmodloader.ini: one mod name per line
$hudLines = @(Get-Content $hudIni)
$listed = @($hudLines | Where-Object { $_.Trim() -ieq "PriceScout" }).Count -gt 0
if ($Uninstall -and $listed) {
    Backup-Once $hudIni
    Save-Lines $hudIni @($hudLines | Where-Object { $_.Trim() -ine "PriceScout" })
    Write-Host "Updated $hudIni"
} elseif (-not $Uninstall -and -not $listed) {
    Backup-Once $hudIni
    Save-Lines $hudIni (@($hudLines | Where-Object { $_ -ne "" }) + "PriceScout")
    Write-Host "Updated $hudIni"
}

$target = Join-Path $data $archive
if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target; Write-Host "Removed $target" }
    Write-Host "PriceScout uninstalled. Its data files in Data\modsdata\pricescout_*.json were left in place."
} else {
    if (-not (Test-Path "dist\$archive")) { throw "dist\$archive not found; run .\build.ps1 first" }
    Copy-Item "dist\$archive" $target -Force
    Write-Host "Copied $archive to $data"
    Write-Host "PriceScout installed. Start the game and open another player's vending machine."
}
