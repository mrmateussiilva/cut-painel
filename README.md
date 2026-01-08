# Panel Cutter (Python + Zig)

Sistema híbrido para **cortar painéis grandes de impressão** em placas menores.

- **Backend Zig**: processamento pesado (load/crop/rotate/padding/contorno/template)
- **Frontend Python**: GUI moderna (CustomTkinter) + Pillow **somente para preview/info**
- **Integração**: FFI via `ctypes`

## Estrutura

```
panel-cutter/
├── backend-zig/
│   ├── src/
│   │   ├── main.zig      # exports FFI: cortarPainel, cortarPasta
│   │   ├── cutter.zig    # lógica de corte
│   │   ├── image.zig     # operações de imagem (crop/rotate/border/paste/resize)
│   │   ├── types.zig     # structs
│   │   └── stb.zig       # @cImport stb
│   ├── vendor/stb/       # stb_image, stb_image_write, stb_image_resize2
│   ├── build.zig
│   └── build.zig.zon
├── frontend-python/
│   ├── gui_app.py
│   ├── zig_bridge.py
│   ├── requirements.txt
│   └── court.py          # placeholder (cole o original aqui depois)
├── templates/
│   └── README.md
├── dist/                 # saída dos binários (libimgcutter.so/imgcutter.dll)
├── build.sh
└── README.md
```

## Requisitos

- **Zig**: 0.15.2
- **Python**: 3.10+

## Build do backend (Zig)

Na raiz de `panel-cutter/`:

```bash
./build.sh
```

Isso compila e copia a lib para `panel-cutter/dist/`.

## Rodar a GUI (Python)

```bash
cd frontend-python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python gui_app.py
```

## Status do backend (prioridades)

- **OK**: corte básico em placas (P01, P02, ...)
- **OK**: contorno preto 1px + padding branco (cm → px via DPI assumido)
- **OK**: rotação para modo horizontal (90° antes e 270° ao salvar)
- **OK (opcional)**: template colado (top-left/top-right conforme posição)
- **Pendente**: numeração (texto) no Zig (recomendado fazer pós-processamento em Python)

## Limitações importantes (TIFF/DPI)

- **TIFF/TIF**: agora é suportado no **Linux/macOS** via **libtiff** (backend Zig).
  - No **Windows (cross-compile)** o `build.sh` desabilita TIFF por padrão (`-Denable_tiff=false`), porque precisaria de libtiff disponível no toolchain/SDK.
- **DPI**: stb não lê DPI nativamente. O backend assume **300 DPI**.
  - Para TIFF, tentamos ler DPI do arquivo (X/YResolution) e usar na conversão cm → px.

## Windows (profissional) — TIFF + Instalador

### Visão geral

Para ter **TIFF no Windows**, você precisa distribuir junto:
- `imgcutter.dll` (seu backend Zig compilado com TIFF ligado)
- `tiff.dll` e dependências (vindas do `vcpkg`), na **mesma pasta do executável**

E para ficar “produto final”, empacotamos a GUI com **PyInstaller (onedir)** e geramos instalador com **Inno Setup**.

### Pré-requisitos (máquina de build Windows)

- Zig 0.15.2 (`zig` no PATH)
- Python 3.10+
- Git
- **Inno Setup** (com `iscc.exe` no PATH)
- Visual Studio Build Tools (recomendado para `vcpkg` no triplet `x64-windows`)

### Build automatizado (recomendado)

No Windows PowerShell:

```powershell
.\scripts\windows\build_installer.ps1 -Version 0.1.0
```

Isso vai:
- baixar/usar `vcpkg` em `vendor\vcpkg`
- instalar `tiff` (`x64-windows`)
- compilar `imgcutter.dll` com `-Denable_tiff=true`
- empacotar a GUI em `release\windows\PanelCutter\PanelCutter.exe` (onedir)
- copiar `imgcutter.dll` + `tiff.dll` e dependências ao lado do exe

### Gerar instalador

Após o staging existir, gere o instalador:

```powershell
iscc.exe .\installer\PanelCutter.iss /DMyAppVersion=0.1.0 /DSourceDir=\"$(Resolve-Path .\\release\\windows\\PanelCutter)\"
```

Saída: `release\\windows\\PanelCutter-Setup-0.1.0.exe`

### Troubleshooting (Windows)

- **Erro: DLL não encontrada (tiff.dll / zlib1.dll / etc)**:
  - copie a DLL faltante de `vendor\\vcpkg\\installed\\x64-windows\\bin` para a pasta do app (ao lado do `PanelCutter.exe`)
- **TIFF desabilitado**:
  - no Windows, você precisa compilar com `-Denable_tiff=true` e fornecer `-Dtiff_include_dir` e `-Dtiff_lib_dir` apontando para o `vcpkg`.

## Próximo passo para ficar 1:1 com seu `court.py`

Cole o `court.py` original em `frontend-python/court.py` (ou me envie aqui) e eu ajusto:
- cálculo exato de `start/middle/end`
- tamanho/posicionamento do template conforme seu gabarito real
- estratégia final para numeração (Python ou integração de lib de fonte)
