#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend-zig"
DIST_DIR="$ROOT_DIR/dist"

mkdir -p "$DIST_DIR"

if ! command -v zig >/dev/null 2>&1; then
  echo "Erro: Zig não encontrado no PATH. Instale Zig 0.15.2." >&2
  exit 1
fi

echo "Zig: $(zig version)"

cd "$BACKEND_DIR"

echo "== Build (Linux native) =="
zig build -Doptimize=ReleaseFast

# Linux
if [[ -f zig-out/lib/libimgcutter.so ]]; then
  cp zig-out/lib/libimgcutter.so "$DIST_DIR/"
  echo "OK: $DIST_DIR/libimgcutter.so"
fi

# macOS (se aplicável)
if [[ -f zig-out/lib/libimgcutter.dylib ]]; then
  cp zig-out/lib/libimgcutter.dylib "$DIST_DIR/"
  echo "OK: $DIST_DIR/libimgcutter.dylib"
fi

echo "== Build (Windows x86_64) =="
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast

if [[ -f zig-out/bin/imgcutter.dll ]]; then
  cp zig-out/bin/imgcutter.dll "$DIST_DIR/"
  echo "OK: $DIST_DIR/imgcutter.dll"
elif [[ -f zig-out/lib/imgcutter.dll ]]; then
  cp zig-out/lib/imgcutter.dll "$DIST_DIR/"
  echo "OK: $DIST_DIR/imgcutter.dll"
fi

echo "Concluído."
