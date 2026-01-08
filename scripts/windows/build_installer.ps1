param(
  [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\.."),
  [string]$Triplet = "x64-windows",
  [string]$Version = "0.1.0",
  [string]$VcpkgRoot = "$ProjectRoot\vendor\vcpkg"
)

$ErrorActionPreference = "Stop"

function Require-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Comando '$name' não encontrado. Instale e tente novamente."
  }
}

Write-Host "== PanelCutter Windows Installer Build =="
Write-Host "ProjectRoot: $ProjectRoot"

Require-Cmd zig
Require-Cmd python

$BackendDir = Join-Path $ProjectRoot "backend-zig"
$FrontendDir = Join-Path $ProjectRoot "frontend-python"
$ReleaseRoot = Join-Path $ProjectRoot "release\windows"
$StageDir = Join-Path $ReleaseRoot "PanelCutter"
$DistDir = Join-Path $ProjectRoot "dist"

New-Item -ItemType Directory -Force -Path $ReleaseRoot | Out-Null
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# --- vcpkg (libtiff) ---
if (-not (Test-Path $VcpkgRoot)) {
  Write-Host "Clonando vcpkg em $VcpkgRoot ..."
  git clone https://github.com/microsoft/vcpkg $VcpkgRoot
}

if (-not (Test-Path (Join-Path $VcpkgRoot "vcpkg.exe"))) {
  Write-Host "Bootstrapping vcpkg ..."
  Push-Location $VcpkgRoot
  .\bootstrap-vcpkg.bat
  Pop-Location
}

Write-Host "Instalando libtiff via vcpkg ($Triplet) ..."
Push-Location $VcpkgRoot
.\vcpkg.exe install tiff --triplet $Triplet
Pop-Location

$VcpkgInstalled = Join-Path $VcpkgRoot "installed\$Triplet"
$TiffInclude = Join-Path $VcpkgInstalled "include"
$TiffLib = Join-Path $VcpkgInstalled "lib"
$TiffBin = Join-Path $VcpkgInstalled "bin"

if (-not (Test-Path $TiffInclude)) { throw "include não encontrado: $TiffInclude" }
if (-not (Test-Path $TiffLib)) { throw "lib não encontrado: $TiffLib" }
if (-not (Test-Path $TiffBin)) { throw "bin não encontrado: $TiffBin" }

# --- Build Zig (TIFF ON) ---
Write-Host "Build Zig backend (TIFF ON) ..."
Push-Location $BackendDir
zig build -Doptimize=ReleaseFast -Denable_tiff=true -Dtiff_include_dir="$TiffInclude" -Dtiff_lib_dir="$TiffLib"
Pop-Location

# Copiar DLL do backend para dist
$Candidates = @(
  Join-Path $BackendDir "zig-out\bin\imgcutter.dll",
  Join-Path $BackendDir "zig-out\lib\imgcutter.dll"
)
$BackendDll = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $BackendDll) { throw "imgcutter.dll não encontrado em zig-out (candidatos: $Candidates)" }
Copy-Item $BackendDll (Join-Path $DistDir "imgcutter.dll") -Force

# --- Build Python GUI (PyInstaller onedir) ---
Write-Host "Build Python GUI (PyInstaller onedir) ..."
Push-Location $FrontendDir
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt pyinstaller

# onedir é mais previsível para instalador (DLLs ficam ao lado do exe)
pyinstaller --noconsole --onedir --name PanelCutter gui_app.py

$PyDist = Join-Path $FrontendDir "dist\PanelCutter"
if (-not (Test-Path $PyDist)) { throw "PyInstaller dist não encontrado: $PyDist" }

# Limpa staging e copia tudo
Remove-Item -Recurse -Force $StageDir
Copy-Item $PyDist $StageDir -Recurse -Force
Pop-Location

# --- Colocar DLL do backend e deps do libtiff ao lado do exe ---
Copy-Item (Join-Path $DistDir "imgcutter.dll") (Join-Path $StageDir "imgcutter.dll") -Force

# Copiar tiff.dll e deps comuns do vcpkg bin.
# Observação: dependendo do build do vcpkg, podem existir outras DLLs. Se faltar alguma,
# o Windows exibirá erro de DLL ausente ao iniciar; nesse caso, copie a DLL faltante do $TiffBin.
$Common = @(
  "tiff.dll",
  "zlib1.dll",
  "jpeg62.dll",
  "liblzma.dll",
  "zstd.dll",
  "deflate.dll",
  "webp.dll",
  "jbig.dll"
)

foreach ($n in $Common) {
  $p = Join-Path $TiffBin $n
  if (Test-Path $p) {
    Copy-Item $p (Join-Path $StageDir $n) -Force
  }
}

Write-Host "Staging pronto: $StageDir"
Write-Host "Agora gere o instalador com Inno Setup (ISCC)."
Write-Host "Exemplo: iscc.exe $ProjectRoot\installer\PanelCutter.iss /DMyAppVersion=$Version /DSourceDir=$StageDir"
