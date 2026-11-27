# Builds dist\PriceScout.ba2 from src\scripts\PriceScout.as.
# Needs Python 3 and JPEXS Free Flash Decompiler (its bundled AS3 compiler does the compiling).
# -Ffdec takes ffdec-cli.exe or, with Java on PATH, ffdec.jar.
param(
    [string]$Ffdec = "C:\Program Files (x86)\FFDec\ffdec-cli.exe"
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path $Ffdec)) { throw "JPEXS not found at $Ffdec (pass -Ffdec <path to ffdec-cli.exe or ffdec.jar>)" }
New-Item -ItemType Directory -Force build, dist | Out-Null

python -I tools\make_skeleton.py build\skeleton.swf PriceScout
if ($LASTEXITCODE) { throw "make_skeleton failed" }

Remove-Item build\PriceScout.swf -ErrorAction SilentlyContinue
$ffdecArgs = @("-importScript", "build\skeleton.swf", "build\PriceScout.swf", "src")
if ($Ffdec -like "*.jar") { $log = & java -jar $Ffdec @ffdecArgs 2>&1 }
else { $log = & $Ffdec @ffdecArgs 2>&1 }
$log | Out-File build\ffdec.log
if ($LASTEXITCODE -or -not (Test-Path build\PriceScout.swf) -or ($log -match "error|exception")) {
    $log
    throw "JPEXS compile failed (see build\ffdec.log)"
}

python -I tools\ba2.py pack dist\PriceScout.ba2 "Interface/PriceScout.swf=build\PriceScout.swf"
if ($LASTEXITCODE) { throw "ba2 pack failed" }
python -I tools\ba2.py list dist\PriceScout.ba2
