"""
Bridge Python para comunicação com backend Zig via ctypes.
Carrega a biblioteca compartilhada e expõe funções FFI.
"""

import ctypes
from ctypes import c_int, c_char_p, c_void_p, POINTER
import os
from typing import Tuple, Optional


class ZigBackend:
    """
    Classe para interagir com o backend Zig compilado.
    Carrega a biblioteca compartilhada (.so no Linux, .dll no Windows)
    e fornece métodos Pythonic para as funções FFI.
    """

    def __init__(self, lib_path: str):
        """
        Inicializa o bridge carregando a biblioteca compartilhada.

        Args:
            lib_path: Caminho para a biblioteca (.so ou .dll)

        Raises:
            OSError: Se a biblioteca não puder ser carregada
        """
        if not os.path.exists(lib_path):
            raise FileNotFoundError(
                f"Biblioteca não encontrada: {lib_path}\n"
                "Execute build.sh para compilar o backend Zig."
            )

        try:
            self.lib = ctypes.CDLL(lib_path)
        except OSError as e:
            raise OSError(f"Erro ao carregar biblioteca {lib_path}: {e}") from e

        # Define tipos de argumentos e retorno para load_image
        self.lib.load_image.argtypes = [
            c_char_p,  # c_path: [*c]const u8
            POINTER(c_int),  # out_width: *i32
            POINTER(c_int),  # out_height: *i32
        ]
        self.lib.load_image.restype = c_void_p  # ?*anyopaque

        # Define tipos para crop_image
        self.lib.crop_image.argtypes = [
            c_void_p,  # img_ptr: *anyopaque
            c_int,  # x: i32
            c_int,  # y: i32
            c_int,  # w: i32
            c_int,  # h: i32
        ]
        self.lib.crop_image.restype = c_void_p  # ?*anyopaque

        # Define tipos para save_image
        self.lib.save_image.argtypes = [
            c_void_p,  # img_ptr: *anyopaque
            c_char_p,  # c_path: [*c]const u8
            c_int,  # format: i32 (0=PNG, 1=JPG)
        ]
        self.lib.save_image.restype = c_int  # i32 (0=sucesso, -1=erro)

        # Define tipos para free_image
        self.lib.free_image.argtypes = [c_void_p]  # img_ptr: *anyopaque
        self.lib.free_image.restype = None  # void

    def load_image(self, path: str) -> Tuple[int, int, int]:
        """
        Carrega uma imagem do arquivo.

        Args:
            path: Caminho para o arquivo de imagem (PNG/JPG)

        Returns:
            Tupla (img_ptr, width, height) onde:
            - img_ptr: Ponteiro interno para a imagem (use para outras operações)
            - width: Largura da imagem em pixels
            - height: Altura da imagem em pixels

        Raises:
            RuntimeError: Se a imagem não puder ser carregada
        """
        # Converte string Python para bytes (UTF-8)
        path_bytes = path.encode("utf-8")

        # Cria variáveis para receber width e height
        width = c_int()
        height = c_int()

        # Chama função Zig
        img_ptr = self.lib.load_image(
            path_bytes,
            ctypes.byref(width),
            ctypes.byref(height),
        )

        if not img_ptr:
            raise RuntimeError(f"Falha ao carregar imagem: {path}")

        return (img_ptr, width.value, height.value)

    def crop_image(
        self, img_ptr: int, x: int, y: int, w: int, h: int
    ) -> int:
        """
        Corta uma região da imagem.

        Args:
            img_ptr: Ponteiro retornado por load_image
            x: Coordenada X do canto superior esquerdo
            y: Coordenada Y do canto superior esquerdo
            w: Largura da região de crop
            h: Altura da região de crop

        Returns:
            Novo ponteiro para a imagem cropped

        Raises:
            RuntimeError: Se o crop falhar (coordenadas inválidas, etc.)
        """
        new_img_ptr = self.lib.crop_image(
            c_void_p(img_ptr),
            c_int(x),
            c_int(y),
            c_int(w),
            c_int(h),
        )

        if not new_img_ptr:
            raise RuntimeError(
                f"Falha ao cortar imagem: x={x}, y={y}, w={w}, h={h}"
            )

        return new_img_ptr

    def save_image(
        self, img_ptr: int, path: str, format: int = 0
    ) -> None:
        """
        Salva uma imagem em arquivo.

        Args:
            img_ptr: Ponteiro retornado por load_image ou crop_image
            path: Caminho onde salvar a imagem
            format: Formato (0=PNG, 1=JPG). Padrão: 0 (PNG)

        Raises:
            RuntimeError: Se a imagem não puder ser salva
        """
        path_bytes = path.encode("utf-8")

        result = self.lib.save_image(
            c_void_p(img_ptr),
            path_bytes,
            c_int(format),
        )

        if result != 0:
            raise RuntimeError(f"Falha ao salvar imagem: {path}")

    def free_image(self, img_ptr: int) -> None:
        """
        Libera a memória de uma imagem.

        Args:
            img_ptr: Ponteiro retornado por load_image ou crop_image
        """
        self.lib.free_image(c_void_p(img_ptr))

