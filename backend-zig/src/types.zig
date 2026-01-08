const std = @import("std");

pub const CutParams = struct {
    /// Largura alvo (em cm) de cada placa
    measure_cm: f64,
    /// Sobreposição (em cm) entre placas
    overlap_cm: f64,
    /// Padding/borda branca (em cm) em volta da placa
    pad_cm: f64,

    /// Se true, rotaciona o painel 90° antes de cortar e volta 270° ao salvar.
    horizontal: bool,

    /// Contorno preto 1px antes do padding
    add_contour: bool,

    /// Template/gabarito
    add_template: bool,
    template_path: []const u8,

    /// DPI assumido (stb não lê DPI). Padrão: 300.
    dpi: f64 = 300.0,

    pub fn cmToPx(self: CutParams, cm: f64) u32 {
        // px = (cm * dpi) / 2.54
        const px_f = (cm * self.dpi) / 2.54;
        if (px_f <= 0) return 0;
        return @intFromFloat(@round(px_f));
    }
};

pub const Image = struct {
    allocator: std.mem.Allocator,
    data: []u8,
    width: u32,
    height: u32,
    channels: u8,
    /// DPI (se conhecido). Para stb geralmente será 300. Para TIFF, tentamos ler do arquivo.
    dpi: f64 = 300.0,

    pub fn stride(self: Image) usize {
        return @as(usize, self.width) * @as(usize, self.channels);
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};
