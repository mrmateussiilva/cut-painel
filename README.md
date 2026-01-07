# Image Cropper

Aplicação para cortar imagens com backend em Zig para processamento pesado e frontend em Python com CustomTkinter para interface gráfica.

## Arquitetura

- **Backend Zig**: Processamento pesado de imagens (carregar, cortar, salvar) usando zstbi
- **Frontend Python**: Interface gráfica com CustomTkinter e Pillow para preview interativo
- **Comunicação**: FFI (Foreign Function Interface) via ctypes

## Estrutura do Projeto

```
image_cropper/
├── backend-zig/
│   ├── src/
│   │   └── main.zig          # Funções FFI: load_image, crop_image, save_image, free_image
│   ├── build.zig              # Configuração de build
│   └── build.zig.zon          # Dependências (zstbi)
├── frontend-python/
│   ├── gui_app.py             # GUI com CustomTkinter
│   ├── zig_bridge.py          # Bridge ctypes para chamar Zig
│   └── requirements.txt       # Dependências Python
├── dist/                      # Bibliotecas compiladas (.so/.dll)
├── build.sh                   # Script de build
└── README.md                  # Este arquivo
```

## Pré-requisitos

### Zig
- Zig 0.11.0 ou superior
- Instale em: https://ziglang.org/download/

### Python
- Python 3.8 ou superior
- pip para instalar dependências

## Build

### 1. Compilar Backend Zig

Execute o script de build:

```bash
chmod +x build.sh
./build.sh
```

Isso irá:
- Compilar para Linux (nativo) → `dist/libimagecrop.so`
- Compilar para Windows (cross-compile, se disponível) → `dist/imagecrop.dll`

**Nota**: Se você não tiver toolchain Windows configurado, apenas o build Linux será feito.

### 2. Instalar Dependências Python

```bash
cd frontend-python
pip install -r requirements.txt
```

## Executar

```bash
cd frontend-python
python gui_app.py
```

## Uso

1. **Abrir Imagem**: Clique em "Abrir Imagem" e selecione um arquivo PNG ou JPG
2. **Definir Região de Crop**: 
   - Clique e arraste no canvas para desenhar um retângulo vermelho
   - O retângulo define a região que será cortada
3. **Cortar e Salvar**: 
   - Clique em "Cortar e Salvar"
   - Escolha o local e nome do arquivo
   - A imagem será cortada usando o backend Zig e salva

## Funcionalidades

- ✅ Carregar imagens PNG/JPG
- ✅ Preview interativo com Pillow
- ✅ Seleção de região de crop arrastando o mouse
- ✅ Corte real feito em Zig (processamento pesado)
- ✅ Salvar em PNG ou JPG
- ✅ Interface dark mode com CustomTkinter

## Notas Técnicas

### Backend Zig

- Usa **zstbi** para carregar imagens (bindings Zig para stb_image)
- Usa **stb_image_write** para salvar imagens (PNG/JPG)
- Funções FFI exportadas com `callconv(.C)` para compatibilidade com ctypes
- Gerenciamento de memória com GeneralPurposeAllocator

### Frontend Python

- **Pillow**: Usado apenas para preview e cálculos de coordenadas
- **Zig Backend**: Usado para o crop real (não usa Pillow para crop final)
- **CustomTkinter**: Interface moderna com tema dark

### Assumptions (Assumindo que)

- zstbi expõe `stbi_write_png` e `stbi_write_jpg` via bindings
- Se zstbi não incluir stb_image_write, será necessário adicionar como dependência separada
- Formato de imagem: PNG e JPG são suportados
- Coordenadas de crop são validadas no backend Zig

## Troubleshooting

### Erro: "Biblioteca não encontrada"
- Certifique-se de executar `./build.sh` primeiro
- Verifique se `dist/libimagecrop.so` (Linux) ou `dist/imagecrop.dll` (Windows) existe

### Erro: "Erro ao carregar biblioteca"
- Verifique se todas as dependências do sistema estão instaladas
- No Linux, pode ser necessário instalar bibliotecas de desenvolvimento

### Erro ao compilar Zig
- Se o hash em `build.zig.zon` estiver incorreto, execute:
  ```bash
  cd backend-zig
  zig fetch --save https://github.com/zig-gamedev/zstbi/archive/refs/heads/main.tar.gz
  ```
  Isso atualizará o hash automaticamente
- Verifique se zstbi está acessível e se stb_image_write está incluído

## Desenvolvimento

### Adicionar Novos Formatos

Para adicionar suporte a novos formatos de imagem:

1. Atualize `main.zig` para suportar o formato em `load_image` e `save_image`
2. Atualize `gui_app.py` para incluir o formato no diálogo de arquivos

### Melhorias Futuras

- [ ] Suporte a mais formatos (BMP, TIFF, etc.)
- [ ] Zoom e pan na imagem
- [ ] Múltiplas seleções de crop
- [ ] Histórico de operações
- [ ] Ajustes de qualidade para JPG

## Licença

Este projeto é um exemplo educacional. Use como desejar.

