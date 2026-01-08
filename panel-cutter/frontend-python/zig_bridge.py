"""Bridge ctypes para o backend Zig (libimgcutter).

Regras:
- O processamento pesado (crop/padding/template) é feito no Zig.
- O Pillow é usado apenas para preview/info na GUI.
"""

from __future__ import annotations

import ctypes
import os
import platform
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
        self.lib_path = lib_path or self._default_lib_path()
        if not os.path.exists(self.lib_path):
            raise FileNotFoundError(
                f"Biblioteca do backend não encontrada em: {self.lib_path}\n"
                f"Dica: rode ../build.sh para gerar os binários em ../dist/"
            )

        self.lib = ctypes.CDLL(self.lib_path)
        self._bind()

    def _default_lib_path(self) -> str:
        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        dist = os.path.join(base_dir, "dist")

        system = platform.system().lower()
        if system.startswith("windows"):
            return os.path.join(dist, "imgcutter.dll")
        if system == "darwin":
            return os.path.join(dist, "libimgcutter.dylib")
        return os.path.join(dist, "libimgcutter.so")

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
