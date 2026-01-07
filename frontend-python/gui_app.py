"""
GUI principal do Image Cropper usando CustomTkinter.
Permite abrir imagens, definir região de crop arrastando o mouse,
e salvar a imagem cortada usando o backend Zig.
"""

import customtkinter as ctk
import tkinter as tk
from tkinter import filedialog, messagebox
from PIL import Image, ImageTk
import os
from typing import Optional, Tuple
from zig_bridge import ZigBackend


class ImageCropperApp(ctk.CTk):
    """
    Aplicação principal de corte de imagens.
    """

    def __init__(self):
        super().__init__()

        # Configuração da janela
        self.title("Image Cropper")
        self.geometry("1000x700")
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        # Inicializa backend Zig
        try:
            lib_path = self._get_lib_path()
            self.backend = ZigBackend(lib_path)
        except Exception as e:
            messagebox.showerror(
                "Erro",
                f"Erro ao carregar backend Zig:\n{e}\n\n"
                "Certifique-se de que executou build.sh para compilar o backend.",
            )
            self.backend = None

        # Estado da aplicação
        self.image_path: Optional[str] = None
        self.pil_image: Optional[Image.Image] = None
        self.tk_image: Optional[ImageTk.PhotoImage] = None
        self.img_ptr: Optional[int] = None  # Ponteiro para imagem no backend Zig
        self.original_width: int = 0
        self.original_height: int = 0

        # Estado do crop (régua/retângulo)
        self.rect_id: Optional[int] = None
        self.start_x: Optional[int] = None
        self.start_y: Optional[int] = None
        self.current_x: Optional[int] = None
        self.current_y: Optional[int] = None
        self.crop_x: int = 0
        self.crop_y: int = 0
        self.crop_w: int = 0
        self.crop_h: int = 0

        # Fator de escala para exibição
        self.scale_factor: float = 1.0

        self._init_ui()

    def _get_lib_path(self) -> str:
        """
        Retorna o caminho para a biblioteca compartilhada baseado no OS.

        Returns:
            Caminho para .so (Linux) ou .dll (Windows)
        """
        if os.name == "nt":
            lib_name = "imagecrop.dll"
        else:
            lib_name = "libimagecrop.so"

        # Tenta vários caminhos possíveis
        possible_paths = [
            os.path.join(os.getcwd(), "dist", lib_name),
            os.path.join(os.path.dirname(__file__), "..", "dist", lib_name),
            os.path.join(os.path.dirname(__file__), "dist", lib_name),
        ]

        for path in possible_paths:
            if os.path.exists(path):
                return path

        # Retorna o primeiro caminho como padrão (erro será tratado depois)
        return possible_paths[0]

    def _init_ui(self):
        """Inicializa a interface gráfica."""
        # Frame superior com botões
        top_frame = ctk.CTkFrame(self)
        top_frame.pack(pady=10, padx=10, fill="x")

        self.open_button = ctk.CTkButton(
            top_frame, text="Abrir Imagem", command=self._open_image
        )
        self.open_button.pack(side="left", padx=5)

        self.crop_button = ctk.CTkButton(
            top_frame,
            text="Cortar e Salvar",
            command=self._crop_and_save,
            state="disabled",
        )
        self.crop_button.pack(side="left", padx=5)

        self.clear_button = ctk.CTkButton(
            top_frame, text="Limpar Seleção", command=self._clear_selection
        )
        self.clear_button.pack(side="left", padx=5)

        # Canvas para exibir imagem
        canvas_frame = ctk.CTkFrame(self)
        canvas_frame.pack(pady=10, padx=10, fill="both", expand=True)

        # Usa tk.Canvas dentro do frame CustomTkinter para melhor compatibilidade
        self.canvas = tk.Canvas(
            canvas_frame,
            bg="gray20",
            highlightthickness=0,
            width=800,
            height=500,
        )
        self.canvas.pack(fill="both", expand=True, padx=5, pady=5)

        # Bind eventos de mouse para desenhar retângulo de crop
        self.canvas.bind("<ButtonPress-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)

        # Frame inferior com informações
        info_frame = ctk.CTkFrame(self)
        info_frame.pack(pady=5, padx=10, fill="x")

        self.coords_label = ctk.CTkLabel(
            info_frame, text="Coordenadas: x=0, y=0, w=0, h=0"
        )
        self.coords_label.pack(side="left", padx=10)

        self.size_label = ctk.CTkLabel(info_frame, text="Tamanho: 0x0")
        self.size_label.pack(side="left", padx=10)

    def _open_image(self):
        """Abre diálogo para selecionar imagem e carrega no canvas."""
        file_path = filedialog.askopenfilename(
            title="Selecionar Imagem",
            filetypes=[
                ("Imagens", "*.png *.jpg *.jpeg"),
                ("PNG", "*.png"),
                ("JPEG", "*.jpg *.jpeg"),
                ("Todos", "*.*"),
            ],
        )

        if not file_path:
            return

        try:
            # Carrega imagem com Pillow para preview
            self.pil_image = Image.open(file_path)
            self.image_path = file_path

            # Carrega imagem no backend Zig
            if self.backend:
                # Libera imagem anterior se existir
                if self.img_ptr:
                    try:
                        self.backend.free_image(self.img_ptr)
                    except:
                        pass

                self.img_ptr, self.original_width, self.original_height = (
                    self.backend.load_image(file_path)
                )

            # Calcula escala para caber no canvas
            canvas_width = self.canvas.winfo_width() or 800
            canvas_height = self.canvas.winfo_height() or 500

            img_width, img_height = self.pil_image.size
            scale_w = canvas_width / img_width
            scale_h = canvas_height / img_height
            self.scale_factor = min(scale_w, scale_h, 1.0)  # Não amplia

            # Redimensiona para preview
            display_width = int(img_width * self.scale_factor)
            display_height = int(img_height * self.scale_factor)
            display_image = self.pil_image.resize(
                (display_width, display_height), Image.Resampling.LANCZOS
            )

            # Converte para PhotoImage
            self.tk_image = ImageTk.PhotoImage(display_image)

            # Limpa canvas e exibe imagem
            self.canvas.delete("all")
            self.canvas.create_image(
                canvas_width // 2,
                canvas_height // 2,
                image=self.tk_image,
                anchor="center",
            )

            # Atualiza labels
            self.size_label.configure(
                text=f"Tamanho: {img_width}x{img_height}"
            )

            # Habilita botão de crop
            self.crop_button.configure(state="normal")

            # Limpa seleção anterior
            self._clear_selection()

        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao carregar imagem:\n{e}")

    def _on_press(self, event):
        """Inicia desenho do retângulo de crop."""
        if not self.tk_image:
            return

        self.start_x = self.canvas.canvasx(event.x)
        self.start_y = self.canvas.canvasy(event.y)

        # Remove retângulo anterior se existir
        if self.rect_id:
            self.canvas.delete(self.rect_id)

    def _on_drag(self, event):
        """Atualiza retângulo de crop enquanto arrasta."""
        if self.start_x is None or self.start_y is None:
            return

        self.current_x = self.canvas.canvasx(event.x)
        self.current_y = self.canvas.canvasy(event.y)

        # Remove retângulo anterior
        if self.rect_id:
            self.canvas.delete(self.rect_id)

        # Desenha novo retângulo (linhas vermelhas como "régua")
        self.rect_id = self.canvas.create_rectangle(
            self.start_x,
            self.start_y,
            self.current_x,
            self.current_y,
            outline="red",
            width=2,
            tags="crop_rect",
        )

        # Calcula coordenadas reais (desescaladas)
        x1 = min(self.start_x, self.current_x)
        y1 = min(self.start_y, self.current_y)
        x2 = max(self.start_x, self.current_x)
        y2 = max(self.start_y, self.current_y)

        # Converte coordenadas do canvas para coordenadas da imagem original
        canvas_width = self.canvas.winfo_width() or 800
        canvas_height = self.canvas.winfo_height() or 500

        # Imagem está centralizada
        img_display_width = int(self.original_width * self.scale_factor)
        img_display_height = int(self.original_height * self.scale_factor)

        img_x_offset = (canvas_width - img_display_width) // 2
        img_y_offset = (canvas_height - img_display_height) // 2

        # Ajusta coordenadas relativas à imagem
        rel_x1 = (x1 - img_x_offset) / self.scale_factor
        rel_y1 = (y1 - img_y_offset) / self.scale_factor
        rel_x2 = (x2 - img_x_offset) / self.scale_factor
        rel_y2 = (y2 - img_y_offset) / self.scale_factor

        # Garante que está dentro dos limites
        rel_x1 = max(0, min(rel_x1, self.original_width))
        rel_y1 = max(0, min(rel_y1, self.original_height))
        rel_x2 = max(0, min(rel_x2, self.original_width))
        rel_y2 = max(0, min(rel_y2, self.original_height))

        self.crop_x = int(rel_x1)
        self.crop_y = int(rel_y1)
        self.crop_w = int(rel_x2 - rel_x1)
        self.crop_h = int(rel_y2 - rel_y1)

        # Atualiza label
        self.coords_label.configure(
            text=f"Coordenadas: x={self.crop_x}, y={self.crop_y}, "
            f"w={self.crop_w}, h={self.crop_h}"
        )

    def _on_release(self, event):
        """Finaliza desenho do retângulo de crop."""
        if self.start_x is None or self.start_y is None:
            return

        # Atualiza coordenadas finais
        self._on_drag(event)

        self.start_x = None
        self.start_y = None

    def _clear_selection(self):
        """Limpa a seleção de crop."""
        if self.rect_id:
            self.canvas.delete(self.rect_id)
            self.rect_id = None

        self.start_x = None
        self.start_y = None
        self.current_x = None
        self.current_y = None
        self.crop_x = 0
        self.crop_y = 0
        self.crop_w = 0
        self.crop_h = 0

        self.coords_label.configure(text="Coordenadas: x=0, y=0, w=0, h=0")

    def _crop_and_save(self):
        """Corta a imagem usando backend Zig e salva."""
        if not self.backend or not self.img_ptr:
            messagebox.showerror("Erro", "Backend não disponível ou imagem não carregada.")
            return

        if self.crop_w <= 0 or self.crop_h <= 0:
            messagebox.showwarning(
                "Aviso", "Selecione uma região válida para cortar (arraste o mouse)."
            )
            return

        try:
            # Corta imagem usando backend Zig
            cropped_ptr = self.backend.crop_image(
                self.img_ptr, self.crop_x, self.crop_y, self.crop_w, self.crop_h
            )

            # Diálogo para salvar
            file_path = filedialog.asksaveasfilename(
                title="Salvar Imagem Cortada",
                defaultextension=".png",
                filetypes=[
                    ("PNG", "*.png"),
                    ("JPEG", "*.jpg *.jpeg"),
                    ("Todos", "*.*"),
                ],
            )

            if not file_path:
                # Libera imagem cropped se usuário cancelar
                self.backend.free_image(cropped_ptr)
                return

            # Determina formato baseado na extensão
            format_type = 0  # PNG padrão
            if file_path.lower().endswith((".jpg", ".jpeg")):
                format_type = 1  # JPG

            # Salva imagem
            self.backend.save_image(cropped_ptr, file_path, format_type)

            # Libera memória
            self.backend.free_image(cropped_ptr)

            messagebox.showinfo("Sucesso", f"Imagem salva em:\n{file_path}")

        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao cortar/salvar imagem:\n{e}")

    def __del__(self):
        """Libera recursos ao fechar."""
        if hasattr(self, "backend") and self.backend and self.img_ptr:
            try:
                self.backend.free_image(self.img_ptr)
            except:
                pass


def main():
    """Função principal."""
    app = ImageCropperApp()
    app.mainloop()


if __name__ == "__main__":
    main()

