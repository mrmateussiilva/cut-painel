const std = @import("std");
const zstbi = @import("zstbi");

// Estrutura interna para armazenar dados da imagem
const ImageData = struct {
    image: zstbi.Image,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ImageData) void {
        self.image.deinit();
        self.allocator.destroy(self);
    }
};

// Inicializa zstbi (deve ser chamado antes de usar)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var zstbi_initialized = false;

fn ensureZstbiInit() void {
    if (!zstbi_initialized) {
        zstbi.init(gpa.allocator());
        zstbi_initialized = true;
    }
}

/// Carrega uma imagem do arquivo
/// Retorna ponteiro para ImageData ou null em caso de erro
/// Preenche out_width e out_height com as dimensões da imagem
pub export fn load_image(
    c_path: [*c]const u8,
    out_width: *i32,
    out_height: *i32,
) callconv(.C) ?*anyopaque {
    ensureZstbiInit();
    const allocator = gpa.allocator();

    // Converte C string para Zig string
    const path = std.mem.sliceTo(c_path, 0);
    if (path.len == 0) return null;

    // Carrega a imagem usando zstbi
    const image = zstbi.Image.loadFromFile(path, allocator) catch |err| {
        std.log.err("Erro ao carregar imagem: {s}: {any}", .{ path, err });
        return null;
    };

    // Cria estrutura ImageData
    const image_data = allocator.create(ImageData) catch |err| {
        std.log.err("Erro ao alocar ImageData: {any}", .{err});
        image.deinit();
        return null;
    };

    image_data.image = image;
    image_data.allocator = allocator;

    // Preenche dimensões
    out_width.* = @intCast(image.width);
    out_height.* = @intCast(image.height);

    return @ptrCast(image_data);
}

/// Corta uma região da imagem
/// Retorna ponteiro para nova ImageData cropped ou null em caso de erro
pub export fn crop_image(
    img_ptr: *anyopaque,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
) callconv(.C) ?*anyopaque {
    ensureZstbiInit();
    const allocator = gpa.allocator();

    const image_data: *ImageData = @ptrCast(@alignCast(img_ptr));
    const source = image_data.image;

    // Validação de coordenadas
    if (x < 0 or y < 0 or w <= 0 or h <= 0) {
        std.log.err("Coordenadas inválidas: x={}, y={}, w={}, h={}", .{ x, y, w, h });
        return null;
    }

    if (@as(usize, @intCast(x + w)) > source.width or @as(usize, @intCast(y + h)) > source.height) {
        std.log.err("Região de crop fora dos limites da imagem", .{});
        return null;
    }

    // Cria nova imagem com dimensões do crop
    const cropped_image = zstbi.Image.init(
        allocator,
        @intCast(w),
        @intCast(h),
        source.channels,
    ) catch |err| {
        std.log.err("Erro ao criar imagem cropped: {any}", .{err});
        return null;
    };

    // Copia pixels da região de crop
    const src_x = @intCast(x);
    const src_y = @intCast(y);
    const dst_w = @intCast(w);
    const dst_h = @intCast(h);

    var dst_y: usize = 0;
    while (dst_y < dst_h) : (dst_y += 1) {
        var dst_x: usize = 0;
        while (dst_x < dst_w) : (dst_x += 1) {
            const src_idx = (src_y + dst_y) * source.width + (src_x + dst_x);
            const dst_idx = dst_y * dst_w + dst_x;

            // Copia todos os canais (RGBA ou RGB)
            var channel: usize = 0;
            while (channel < source.channels) : (channel += 1) {
                cropped_image.data[dst_idx * source.channels + channel] =
                    source.data[src_idx * source.channels + channel];
            }
        }
    }

    // Cria nova ImageData para a imagem cropped
    const cropped_data = allocator.create(ImageData) catch |err| {
        std.log.err("Erro ao alocar ImageData cropped: {any}", .{err});
        cropped_image.deinit();
        return null;
    };

    cropped_data.image = cropped_image;
    cropped_data.allocator = allocator;

    return @ptrCast(cropped_data);
}

// Declarações C para stb_image_write
// ASSUMINDO QUE: stb_image_write está linkado (via build.zig)
extern "c" fn stbi_write_png(
    filename: [*c]const u8,
    w: c_int,
    h: c_int,
    comp: c_int,
    data: ?*const anyopaque,
    stride_in_bytes: c_int,
) c_int;

extern "c" fn stbi_write_jpg(
    filename: [*c]const u8,
    w: c_int,
    h: c_int,
    comp: c_int,
    data: ?*const anyopaque,
    quality: c_int,
) c_int;

/// Salva uma imagem em arquivo
/// format: 0 = PNG, 1 = JPG
/// Retorna 0 em caso de sucesso, -1 em caso de erro
pub export fn save_image(
    img_ptr: *anyopaque,
    c_path: [*c]const u8,
    format: i32,
) callconv(.C) i32 {
    ensureZstbiInit();

    const image_data: *ImageData = @ptrCast(@alignCast(img_ptr));
    const image = image_data.image;

    // Converte C string para Zig string
    const path = std.mem.sliceTo(c_path, 0);
    if (path.len == 0) {
        std.log.err("Caminho vazio", .{});
        return -1;
    }

    // Calcula stride (bytes por linha)
    const stride = image.width * image.channels;

    // Salva usando stb_image_write
    const result = if (format == 0) {
        // PNG
        stbi_write_png(
            c_path,
            @intCast(image.width),
            @intCast(image.height),
            @intCast(image.channels),
            image.data.ptr,
            stride,
        )
    } else if (format == 1) {
        // JPG (qualidade 95)
        stbi_write_jpg(
            c_path,
            @intCast(image.width),
            @intCast(image.height),
            @intCast(image.channels),
            image.data.ptr,
            95,
        )
    } else {
        std.log.err("Formato inválido: {}. Use 0 (PNG) ou 1 (JPG)", .{format});
        return -1;
    };

    if (result == 0) {
        std.log.err("Erro ao salvar imagem: {s}", .{path});
        return -1;
    }

    return 0;
}

/// Libera memória de uma imagem
pub export fn free_image(img_ptr: *anyopaque) callconv(.C) void {
    const image_data: *ImageData = @ptrCast(@alignCast(img_ptr));
    image_data.deinit();
}

