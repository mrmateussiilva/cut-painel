const std = @import("std");
const types = @import("types.zig");
const cutter_mod = @import("cutter.zig");

fn toBool(v: c_int) bool {
    return v != 0;
}

fn cStrToSlice(ptr: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(ptr, 0);
}

/// Cortar um painel individual.
/// Retorna 0 em sucesso, !=0 em erro.
pub export fn cortarPainel(
    caminho_painel: [*:0]const u8,
    pasta_saida: [*:0]const u8,
    largura_cm: f64,
    sobrepor_cm: f64,
    padding_cm: f64,
    horizontal: c_int,
    add_contorno: c_int,
    add_template: c_int,
    caminho_template: [*:0]const u8,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const panel_path = cStrToSlice(caminho_painel);
    const out_dir = cStrToSlice(pasta_saida);
    const template_path = cStrToSlice(caminho_template);

    const params = types.CutParams{
        .measure_cm = largura_cm,
        .overlap_cm = sobrepor_cm,
        .pad_cm = padding_cm,
        .horizontal = toBool(horizontal),
        .add_contour = toBool(add_contorno),
        .add_template = toBool(add_template),
        .template_path = template_path,
        .dpi = 300.0,
    };

    var cutter = cutter_mod.Cutter.init(allocator);
    _ = cutter.cutPanel(panel_path, out_dir, params) catch |err| {
        std.log.err("cortarPainel falhou: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Cortar uma pasta inteira (itera arquivos suportados e chama cutPanel internamente).
/// Retorna 0 em sucesso, !=0 em erro.
pub export fn cortarPasta(
    pasta_origem: [*:0]const u8,
    pasta_saida: [*:0]const u8,
    largura_cm: f64,
    sobrepor_cm: f64,
    padding_cm: f64,
    horizontal: c_int,
    add_contorno: c_int,
    add_template: c_int,
    caminho_template: [*:0]const u8,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const in_dir = cStrToSlice(pasta_origem);
    const out_dir = cStrToSlice(pasta_saida);
    const template_path = cStrToSlice(caminho_template);

    const params = types.CutParams{
        .measure_cm = largura_cm,
        .overlap_cm = sobrepor_cm,
        .pad_cm = padding_cm,
        .horizontal = toBool(horizontal),
        .add_contour = toBool(add_contorno),
        .add_template = toBool(add_template),
        .template_path = template_path,
        .dpi = 300.0,
    };

    var cutter = cutter_mod.Cutter.init(allocator);
    _ = cutter.cutFolder(in_dir, out_dir, params) catch |err| {
        std.log.err("cortarPasta falhou: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}
