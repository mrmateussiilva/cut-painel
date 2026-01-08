"""GUI do Cortador de Painéis (CustomTkinter).

- Seleciona pasta de origem/saída e template.
- Valida parâmetros.
- Processa em thread (não trava UI).
- Log com timestamps + progressbar.

Nota: o backend Zig suporta PNG/JPG/JPEG via stb.
TIFF/TIF não é suportado por stb_image/stb_image_write padrão.
"""

from __future__ import annotations

import os
import threading
import time
from dataclasses import replace
from datetime import datetime
from typing import Optional

import customtkinter as ctk
import tkinter as tk
from tkinter import filedialog, messagebox

from PIL import Image

from zig_bridge import CutConfig, ZigImageCutter, ZigBackendError


SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".tif", ".tiff"}


def now_ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def list_images(folder: str) -> list[str]:
    out: list[str] = []
    for name in sorted(os.listdir(folder)):
        p = os.path.join(folder, name)
        if not os.path.isfile(p):
            continue
        ext = os.path.splitext(name)[1].lower()
        if ext in SUPPORTED_EXTS:
            out.append(p)
    return out


def estimate_tiles(width_px: int, measure_cm: float, overlap_cm: float, dpi: float = 300.0) -> int:
    # Espelha o loop do backend (aproximação)
    def cm_to_px(cm: float) -> int:
        return max(0, int(round((cm * dpi) / 2.54)))

    measure_px = cm_to_px(measure_cm)
    overlap_px = cm_to_px(overlap_cm)
    if measure_px <= 0:
        return 0

    w_total = width_px
    x_start = 0
    x_end = min(w_total, measure_px + overlap_px)
    count = 0

    while True:
        if x_end - x_start <= 0:
            break
        count += 1
        if x_end >= w_total:
            break
        x_start = x_end - (2 * overlap_px)
        if x_start < 0:
            x_start = 0
        x_end = x_start + measure_px + (2 * overlap_px)
        if x_end > w_total:
            x_end = w_total

    return count


class App(ctk.CTk):
    def __init__(self):
        super().__init__()

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self.title("🔪 Cortador de Painéis")
        self.geometry("1100x720")

        self.cutter: Optional[ZigImageCutter] = None
        self.worker: Optional[threading.Thread] = None
        self.cancel_event = threading.Event()

        self._build_ui()
        self._init_backend()

    def _init_backend(self) -> None:
        try:
            self.cutter = ZigImageCutter()
            self._log(f"Backend carregado: {self.cutter.lib_path}")
        except Exception as e:
            self.cutter = None
            messagebox.showerror("Erro", f"Falha ao carregar backend Zig:\n\n{e}")

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        header = ctk.CTkFrame(self)
        header.grid(row=0, column=0, sticky="ew", padx=14, pady=(14, 8))
        header.grid_columnconfigure(1, weight=1)

        title = ctk.CTkLabel(header, text="🔪 Cortador de Painéis", font=ctk.CTkFont(size=20, weight="bold"))
        title.grid(row=0, column=0, sticky="w", padx=12, pady=10)

        self.theme_var = ctk.StringVar(value="dark")
        theme = ctk.CTkOptionMenu(header, values=["dark", "light"], variable=self.theme_var, command=self._on_theme)
        theme.grid(row=0, column=2, sticky="e", padx=12, pady=10)

        main = ctk.CTkFrame(self)
        main.grid(row=1, column=0, sticky="nsew", padx=14, pady=(0, 14))
        main.grid_columnconfigure(0, weight=2)
        main.grid_columnconfigure(1, weight=3)
        main.grid_rowconfigure(2, weight=1)

        # Coluna esquerda (config)
        left = ctk.CTkFrame(main)
        left.grid(row=0, column=0, rowspan=3, sticky="nsew", padx=(12, 8), pady=12)
        left.grid_columnconfigure(1, weight=1)

        ctk.CTkLabel(left, text="Configuração", font=ctk.CTkFont(size=16, weight="bold")).grid(
            row=0, column=0, columnspan=3, sticky="w", padx=12, pady=(12, 8)
        )

        self.src_var = ctk.StringVar(value="")
        self.out_var = ctk.StringVar(value="")
        self.tpl_var = ctk.StringVar(value="")

        self._path_row(left, 1, "Pasta Origem:", self.src_var, self._pick_src)
        self._path_row(left, 2, "Pasta Saída:", self.out_var, self._pick_out)
        self._path_row(left, 3, "Template:", self.tpl_var, self._pick_tpl, button_text="Selecionar")

        ctk.CTkLabel(left, text="Parâmetros", font=ctk.CTkFont(size=16, weight="bold")).grid(
            row=4, column=0, columnspan=3, sticky="w", padx=12, pady=(16, 8)
        )

        self.w_cm = ctk.StringVar(value="150")
        self.ov_cm = ctk.StringVar(value="0.5")
        self.pad_cm = ctk.StringVar(value="1.0")

        self._entry_row(left, 5, "Largura (cm):", self.w_cm)
        self._entry_row(left, 6, "Sobreposição (cm):", self.ov_cm)
        self._entry_row(left, 7, "Padding (cm):", self.pad_cm)

        self.orient_var = ctk.StringVar(value="Horizontal")
        ctk.CTkLabel(left, text="Orientação:").grid(row=8, column=0, sticky="w", padx=12, pady=(8, 8))
        orient = ctk.CTkOptionMenu(left, values=["Horizontal", "Vertical"], variable=self.orient_var)
        orient.grid(row=8, column=1, sticky="ew", padx=12, pady=(8, 8))

        self.contour_var = ctk.BooleanVar(value=True)
        self.tpl_enable_var = ctk.BooleanVar(value=False)

        ctk.CTkCheckBox(left, text="Adicionar Contorno", variable=self.contour_var).grid(
            row=9, column=0, columnspan=2, sticky="w", padx=12, pady=(8, 4)
        )
        ctk.CTkCheckBox(left, text="Adicionar Template", variable=self.tpl_enable_var).grid(
            row=10, column=0, columnspan=2, sticky="w", padx=12, pady=(4, 12)
        )

        self.btn_start = ctk.CTkButton(left, text="▶ CORTAR PAINÉIS", height=44, command=self._start)
        self.btn_start.grid(row=11, column=0, columnspan=2, sticky="ew", padx=12, pady=(6, 8))

        self.btn_cancel = ctk.CTkButton(left, text="⏹ Cancelar", fg_color="#444", command=self._cancel)
        self.btn_cancel.grid(row=12, column=0, columnspan=2, sticky="ew", padx=12, pady=(0, 12))

        # Coluna direita (preview/info + log)
        right_top = ctk.CTkFrame(main)
        right_top.grid(row=0, column=1, sticky="ew", padx=(8, 12), pady=(12, 8))
        right_top.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(right_top, text="Preview / Info", font=ctk.CTkFont(size=16, weight="bold")).grid(
            row=0, column=0, sticky="w", padx=12, pady=(12, 8)
        )

        self.info_label = ctk.CTkLabel(right_top, text="Selecione uma pasta de origem para ver informações.", justify="left")
        self.info_label.grid(row=1, column=0, sticky="ew", padx=12, pady=(0, 12))

        right_log = ctk.CTkFrame(main)
        right_log.grid(row=1, column=1, rowspan=2, sticky="nsew", padx=(8, 12), pady=(0, 12))
        right_log.grid_rowconfigure(1, weight=1)
        right_log.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(right_log, text="Log de Processamento", font=ctk.CTkFont(size=16, weight="bold")).grid(
            row=0, column=0, sticky="w", padx=12, pady=(12, 8)
        )

        self.log_text = tk.Text(right_log, height=12, wrap="word")
        self.log_text.grid(row=1, column=0, sticky="nsew", padx=12, pady=(0, 8))

        self.progress = ctk.CTkProgressBar(right_log)
        self.progress.grid(row=2, column=0, sticky="ew", padx=12, pady=(0, 6))
        self.progress.set(0.0)

        self.progress_label = ctk.CTkLabel(right_log, text="0%")
        self.progress_label.grid(row=3, column=0, sticky="w", padx=12, pady=(0, 12))

        # Recalcular info quando pasta muda
        self.src_var.trace_add("write", lambda *_: self._refresh_info())
        self.w_cm.trace_add("write", lambda *_: self._refresh_info())
        self.ov_cm.trace_add("write", lambda *_: self._refresh_info())

    def _on_theme(self, v: str) -> None:
        ctk.set_appearance_mode(v)

    def _path_row(self, parent: ctk.CTkFrame, row: int, label: str, var: ctk.StringVar, cmd, button_text: str = "Selecionar") -> None:
        ctk.CTkLabel(parent, text=label).grid(row=row, column=0, sticky="w", padx=12, pady=6)
        ent = ctk.CTkEntry(parent, textvariable=var)
        ent.grid(row=row, column=1, sticky="ew", padx=12, pady=6)
        btn = ctk.CTkButton(parent, text=button_text, width=110, command=cmd)
        btn.grid(row=row, column=2, sticky="e", padx=12, pady=6)

    def _entry_row(self, parent: ctk.CTkFrame, row: int, label: str, var: ctk.StringVar) -> None:
        ctk.CTkLabel(parent, text=label).grid(row=row, column=0, sticky="w", padx=12, pady=6)
        ent = ctk.CTkEntry(parent, textvariable=var)
        ent.grid(row=row, column=1, sticky="ew", padx=12, pady=6)

    def _pick_src(self) -> None:
        d = filedialog.askdirectory(title="Selecionar pasta de origem")
        if d:
            self.src_var.set(d)

    def _pick_out(self) -> None:
        d = filedialog.askdirectory(title="Selecionar pasta de saída")
        if d:
            self.out_var.set(d)

    def _pick_tpl(self) -> None:
        f = filedialog.askopenfilename(title="Selecionar template", filetypes=[("Imagens", "*.png;*.jpg;*.jpeg;*.tif;*.tiff"), ("Todos", "*")])
        if f:
            self.tpl_var.set(f)

    def _log(self, msg: str) -> None:
        self.log_text.insert("end", f"[{now_ts()}] {msg}\n")
        self.log_text.see("end")

    def _ui_log(self, msg: str) -> None:
        self.after(0, lambda: self._log(msg))

    def _ui_progress(self, done: int, total: int) -> None:
        def _upd() -> None:
            frac = 0.0 if total <= 0 else max(0.0, min(1.0, done / total))
            self.progress.set(frac)
            self.progress_label.configure(text=f"{int(frac*100)}% - {done} de {total} painéis")

        self.after(0, _upd)

    def _refresh_info(self) -> None:
        src = self.src_var.get().strip()
        if not src or not os.path.isdir(src):
            self.info_label.configure(text="Selecione uma pasta de origem para ver informações.")
            return

        imgs = list_images(src)
        if not imgs:
            self.info_label.configure(text="Nenhuma imagem encontrada na pasta.")
            return

        sample = imgs[0]
        try:
            with Image.open(sample) as im:
                w_px, h_px = im.size
        except Exception as e:
            self.info_label.configure(text=f"Erro ao ler amostra: {os.path.basename(sample)}\n{e}")
            return

        try:
            largura_cm = float(self.w_cm.get())
            sobrepor_cm = float(self.ov_cm.get())
        except ValueError:
            self.info_label.configure(text="Parâmetros inválidos (Largura/Sobreposição).")
            return

        dpi = 300.0
        w_cm = (w_px * 2.54) / dpi
        h_cm = (h_px * 2.54) / dpi
        placas = estimate_tiles(w_px, largura_cm, sobrepor_cm, dpi=dpi)

        self.info_label.configure(
            text=(
                f"Painel (amostra): {os.path.basename(sample)}\n"
                f"Dimensões (assumindo {dpi:.0f} DPI): {w_cm:.1f}cm x {h_cm:.1f}cm\n"
                f"Painéis na pasta: {len(imgs)}\n"
                f"Placas estimadas por painel: {placas}\n"
                f"Saída: PNG (P01, P02, ...)"
            )
        )

    def _read_cfg(self) -> CutConfig:
        try:
            largura_cm = float(self.w_cm.get())
            sobrepor_cm = float(self.ov_cm.get())
            padding_cm = float(self.pad_cm.get())
        except ValueError:
            raise ValueError("Parâmetros numéricos inválidos.")

        horizontal = self.orient_var.get() == "Horizontal"
        contorno = bool(self.contour_var.get())
        add_template = bool(self.tpl_enable_var.get())
        template_path = self.tpl_var.get().strip()

        if add_template and not template_path:
            raise ValueError("Template marcado, mas nenhum arquivo foi selecionado.")

        return CutConfig(
            largura_cm=largura_cm,
            sobrepor_cm=sobrepor_cm,
            padding_cm=padding_cm,
            horizontal=horizontal,
            contorno=contorno,
            add_template=add_template,
            template_path=template_path,
        )

    def _start(self) -> None:
        if self.worker and self.worker.is_alive():
            messagebox.showinfo("Processando", "Já existe um processamento em andamento.")
            return
        if not self.cutter:
            messagebox.showerror("Erro", "Backend Zig não carregado.")
            return

        src = self.src_var.get().strip()
        out = self.out_var.get().strip()

        if not src or not os.path.isdir(src):
            messagebox.showerror("Erro", "Selecione uma pasta de origem válida.")
            return
        if not out:
            messagebox.showerror("Erro", "Selecione uma pasta de saída.")
            return
        os.makedirs(out, exist_ok=True)

        try:
            cfg = self._read_cfg()
        except ValueError as e:
            messagebox.showerror("Erro", str(e))
            return

        files = list_images(src)
        if not files:
            messagebox.showinfo("Nada a fazer", "Nenhuma imagem encontrada na pasta.")
            return

        self.cancel_event.clear()
        self.progress.set(0.0)
        self.progress_label.configure(text="0%")

        self.btn_start.configure(state="disabled")

        def work() -> None:
            t0 = time.time()
            ok = 0
            total = len(files)
            self._ui_log(f"Iniciando: {total} arquivo(s)")

            for i, f in enumerate(files, start=1):
                if self.cancel_event.is_set():
                    self._ui_log("Cancelado pelo usuário.")
                    break

                ext = os.path.splitext(f)[1].lower()
                if ext in {".tif", ".tiff"}:
                    self._ui_log("Aviso: TIFF/TIF pode falhar (stb não suporta TIFF por padrão).")

                self._ui_log(f"Processando: {os.path.basename(f)}")
                try:
                    self.cutter.cortar_painel(f, out, cfg)
                    ok += 1
                    self._ui_log(f"✓ OK: {os.path.basename(f)}")
                except ZigBackendError as e:
                    self._ui_log(f"✗ Erro (backend): {e}")
                except Exception as e:
                    self._ui_log(f"✗ Erro: {e}")

                self._ui_progress(i, total)

            dt = time.time() - t0
            self._ui_log(f"Concluído. OK={ok}/{total} em {dt:.1f}s")

            self.after(0, lambda: self.btn_start.configure(state="normal"))

        self.worker = threading.Thread(target=work, daemon=True)
        self.worker.start()

    def _cancel(self) -> None:
        self.cancel_event.set()


def main() -> None:
    app = App()
    app.mainloop()


if __name__ == "__main__":
    main()
