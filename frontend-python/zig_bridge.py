"""Bridge ctypes para o backend Zig (libimgcutter).

Regras:
- O processamento pesado (crop/padding/template) é feito no Zig.
- O Pillow é usado apenas para preview/info na GUI.
"""

from __future__ import annotations

import ctypes
import os
import platform
import sys
from pathlib import Path
from ctypes import c_char_p, c_double, c_int
from dataclasses import dataclass


class ZigBackendError(RuntimeError):
    pass


@dataclass(frozen=True)
class CutConfig:
    largura_cm: float = 150.0
    sobrepor_cm: float = 0.5
    padding_cm: float = 1.0
    horizontal: bool = True
    contorno: bool = True
    add_template: bool = False
    template_path: str = ""


class ZigImageCutter:
    def __init__(self, lib_path: str | None = None):
        self.lib_path = lib_path or str(self._default_lib_path())
        self.lib_path = os.path.abspath(self.lib_path)

        if not os.path.exists(self.lib_path):
            raise FileNotFoundError(
                f"Biblioteca do backend não encontrada em: {self.lib_path}\n"
                f"Dica (dev): rode ../build.sh para gerar os binários em ../dist/\n"
                f"Dica (Windows): confirme que imgcutter.dll e dependências (tiff.dll, etc) estão na mesma pasta do app."
            )

        # Windows: garantir que o diretório da DLL (e deps) está no search path
        self._configure_windows_dll_search(Path(self.lib_path).parent)

        self.lib = ctypes.CDLL(self.lib_path)
        self._bind()

    def _default_lib_path(self) -> Path:
        # Prioridade:
        # 1) Mesma pasta do executável (PyInstaller onefile/onedir)
        # 2) Pasta temporária do PyInstaller (_MEIPASS)
        # 3) dist/ do projeto (dev)
        exe_dir = Path(sys.executable).resolve().parent
        meipass_dir = Path(getattr(sys, "_MEIPASS", "")) if hasattr(sys, "_MEIPASS") else None
        repo_dir = Path(__file__).resolve().parent.parent

        system = platform.system().lower()
        if system.startswith("windows"):
            name = "imgcutter.dll"
        elif system == "darwin":
            name = "libimgcutter.dylib"
        else:
            name = "libimgcutter.so"

        candidates: list[Path] = []
        candidates.append(exe_dir / name)
        if meipass_dir and str(meipass_dir):
            candidates.append(meipass_dir / name)
        candidates.append(repo_dir / "dist" / name)

        for c in candidates:
            if c.exists():
                return c
        # fallback: dev path esperado
        return candidates[-1]

    def _configure_windows_dll_search(self, dll_dir: Path) -> None:
        if not platform.system().lower().startswith("windows"):
            return
        try:
            if hasattr(os, "add_dll_directory"):
                os.add_dll_directory(str(dll_dir))
        except Exception:
            # Melhor esforço; se falhar, o usuário precisa colocar as DLLs no PATH ou na mesma pasta.
            pass

    def _bind(self) -> None:
        # cortarPainel
        self.lib.cortarPainel.argtypes = [
            c_char_p,
            c_char_p,
            c_double,
            c_double,
            c_double,
            c_int,
            c_int,
            c_int,
            c_char_p,
        ]
        self.lib.cortarPainel.restype = c_int

        # cortarPasta
        self.lib.cortarPasta.argtypes = [
            c_char_p,
            c_char_p,
            c_double,
            c_double,
            c_double,
            c_int,
            c_int,
            c_int,
            c_char_p,
        ]
        self.lib.cortarPasta.restype = c_int

    @staticmethod
    def _b(v: bool) -> int:
        return 1 if v else 0

    @staticmethod
    def _enc(path: str) -> bytes:
        # Zig recebe UTF-8
        return path.encode("utf-8")

    def cortar_painel(self, painel: str, saida: str, cfg: CutConfig) -> None:
        rc = self.lib.cortarPainel(
            self._enc(painel),
            self._enc(saida),
            float(cfg.largura_cm),
            float(cfg.sobrepor_cm),
            float(cfg.padding_cm),
            self._b(cfg.horizontal),
            self._b(cfg.contorno),
            self._b(cfg.add_template),
            self._enc(cfg.template_path or ""),
        )
        if rc != 0:
            raise ZigBackendError(f"cortarPainel retornou erro (rc={rc})")

    def cortar_pasta(self, origem: str, saida: str, cfg: CutConfig) -> None:
        rc = self.lib.cortarPasta(
            self._enc(origem),
            self._enc(saida),
            float(cfg.largura_cm),
            float(cfg.sobrepor_cm),
            float(cfg.padding_cm),
            self._b(cfg.horizontal),
            self._b(cfg.contorno),
            self._b(cfg.add_template),
            self._enc(cfg.template_path or ""),
        )
        if rc != 0:
            raise ZigBackendError(f"cortarPasta retornou erro (rc={rc})")
