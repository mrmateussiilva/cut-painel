#!/bin/bash

# Script de build para Image Cropper
# Compila backend Zig para Linux (nativo) e Windows (cross-compile)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend-zig"
DIST_DIR="$SCRIPT_DIR/dist"

echo "=== Image Cropper Build Script ==="

# Cria diretório dist se não existir
mkdir -p "$DIST_DIR"

# Verifica se Zig está instalado
if ! command -v zig &> /dev/null; then
    echo "Erro: Zig não está instalado!"
    echo "Instale Zig: https://ziglang.org/download/"
    exit 1
fi

echo "Zig version: $(zig version)"

# Build para Linux (nativo)
echo ""
echo "=== Building for Linux (native) ==="
cd "$BACKEND_DIR"
zig build -Doptimize=ReleaseFast
cp "$BACKEND_DIR/zig-out/lib/libimagecrop.so" "$DIST_DIR/libimagecrop.so" 2>/dev/null || true
echo "✓ Linux build completo: $DIST_DIR/libimagecrop.so"

# Build para Windows (cross-compile)
echo ""
echo "=== Building for Windows (cross-compile) ==="
# ASSUMINDO QUE: usuário tem toolchain Windows configurado
# Se não tiver, pode pular esta parte
if zig targets | grep -q "windows"; then
    zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast
    cp "$BACKEND_DIR/zig-out/lib/imagecrop.dll" "$DIST_DIR/imagecrop.dll" 2>/dev/null || true
    echo "✓ Windows build completo: $DIST_DIR/imagecrop.dll"
else
    echo "⚠ Toolchain Windows não disponível, pulando build Windows"
fi

echo ""
echo "=== Build completo! ==="
echo "Bibliotecas em: $DIST_DIR"
ls -lh "$DIST_DIR"/*.{so,dll} 2>/dev/null || echo "Nenhuma biblioteca encontrada"

