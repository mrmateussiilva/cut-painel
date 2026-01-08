const std = @import("std");
const types = @import("types.zig");
const imgops = @import("image.zig");

pub const Cutter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Cutter {
        return .{ .allocator = allocator };
    }

    pub fn cutPanel(self: Cutter, panel_path: []const u8, out_dir: []const u8, params: types.CutParams) !u32 {
        try ensureDir(out_dir);

        var panel = try imgops.ImageOps.load(self.allocator, panel_path);
        defer panel.deinit();

        // Rotação se horizontal
        var working = panel;
        var rotated: ?types.Image = null;
        if (params.horizontal) {
            const r = try imgops.ImageOps.rotate90CW(self.allocator, &panel);
            rotated = r;
            working = r;
        }
        defer if (rotated) |*im| im.deinit();

        const measure_px = params.cmToPx(params.measure_cm);
        const overlap_px = params.cmToPx(params.overlap_cm);
        const pad_px = params.cmToPx(params.pad_cm);

        if (measure_px == 0) return error.InvalidParams;

        // Template (opcional) - carregamos 1x
        var tpl_opt: ?types.Image = null;
        var tpl_scaled_opt: ?types.Image = null;
        if (params.add_template and params.template_path.len > 0) {
            const tpl = try imgops.ImageOps.load(self.allocator, params.template_path);
            tpl_opt = tpl;
            // Heurística: assume que template foi criado para 300 DPI; escala para o DPI atual.
            if (params.dpi != 300.0) {
                const scale = params.dpi / 300.0;
                const nw: u32 = @max(1, @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(tpl.width)) * scale))));
                const nh: u32 = @max(1, @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(tpl.height)) * scale))));
                const tpl_scaled = try imgops.ImageOps.resizeRGBA(self.allocator, &tpl, nw, nh);
                tpl_scaled_opt = tpl_scaled;
            }
        }
        defer if (tpl_scaled_opt) |*im| im.deinit();
        defer if (tpl_opt) |*im| im.deinit();

        const tpl_ref: ?*const types.Image = if (tpl_scaled_opt) |*im| im else if (tpl_opt) |*im| im else null;

        const basename = fileBaseNoExt(panel_path);

        const w_total: u32 = working.width;
        const h_total: u32 = working.height;

        // Implementação seguindo o "start/middle/end" do prompt (larguras variáveis)
        var count: u32 = 0;
        var x_start: i64 = 0;
        var x_end: i64 = @min(@as(i64, measure_px) + @as(i64, overlap_px), @as(i64, w_total));

        while (true) {
            const tile_w_i64 = x_end - x_start;
            if (tile_w_i64 <= 0) break;

            const tile_w: u32 = @intCast(tile_w_i64);
            const tile_h: u32 = h_total;

            var tile = try imgops.ImageOps.crop(self.allocator, &working, @intCast(x_start), 0, tile_w, tile_h);
            defer tile.deinit();

            if (params.add_contour) {
                imgops.ImageOps.addContour1px(&tile);
            }

            var padded = try imgops.ImageOps.addPadding(self.allocator, &tile, pad_px);
            defer padded.deinit();

            // Template opcional (sem numeração por enquanto)
            if (tpl_ref) |tpl_img| {
                const margin: i32 = 10;
                const pad_i32: i32 = @intCast(pad_px);
                const tpl_w: i32 = @intCast(tpl_img.width);
                const dst_w: i32 = @intCast(padded.width);

                const is_first = (count == 0);
                // last: se já atingimos o fim
                const is_last = (x_end >= @as(i64, w_total));

                if (is_first) {
                    // canto superior direito
                    imgops.ImageOps.pasteRGBA(&padded, tpl_img, dst_w - pad_i32 - margin - tpl_w, pad_i32 + margin);
                } else if (is_last) {
                    // canto superior esquerdo
                    imgops.ImageOps.pasteRGBA(&padded, tpl_img, pad_i32 + margin, pad_i32 + margin);
                } else {
                    // dois cantos
                    imgops.ImageOps.pasteRGBA(&padded, tpl_img, pad_i32 + margin, pad_i32 + margin);
                    imgops.ImageOps.pasteRGBA(&padded, tpl_img, dst_w - pad_i32 - margin - tpl_w, pad_i32 + margin);
                }
            }

            var to_save = padded;
            var rotated_back: ?types.Image = null;
            if (params.horizontal) {
                const rb = try imgops.ImageOps.rotate270CW(self.allocator, &padded);
                rotated_back = rb;
                to_save = rb;
            }
            defer if (rotated_back) |*im| im.deinit();

            count += 1;
            const out_name = try std.fmt.allocPrint(self.allocator, "{s} - P{d:0>2}.png", .{ basename, count });
            defer self.allocator.free(out_name);

            const out_path = try joinPath(self.allocator, out_dir, out_name);
            defer self.allocator.free(out_path);

            try imgops.ImageOps.savePng(&to_save, out_path);

            if (x_end >= @as(i64, w_total)) break;

            // Próximo trecho
            x_start = x_end - (@as(i64, overlap_px) * 2);
            if (x_start < 0) x_start = 0;
            x_end = x_start + @as(i64, measure_px) + (@as(i64, overlap_px) * 2);
            if (x_end > @as(i64, w_total)) x_end = @as(i64, w_total);
        }

        return count;
    }

    pub fn cutFolder(self: Cutter, in_dir: []const u8, out_dir: []const u8, params: types.CutParams) !u32 {
        try ensureDir(out_dir);

        var dir = try std.fs.cwd().openDir(in_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        var ok_count: u32 = 0;

        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!isImageFile(entry.name)) continue;

            const in_path = try joinPath(self.allocator, in_dir, entry.name);
            defer self.allocator.free(in_path);

            _ = try self.cutPanel(in_path, out_dir, params);
            ok_count += 1;
        }

        return ok_count;
    }
};

fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn isImageFile(name: []const u8) bool {
    const lower = std.ascii.allocLowerString(std.heap.page_allocator, name) catch return false;
    defer std.heap.page_allocator.free(lower);

    return std.mem.endsWith(u8, lower, ".png") or
        std.mem.endsWith(u8, lower, ".jpg") or
        std.mem.endsWith(u8, lower, ".jpeg") or
        std.mem.endsWith(u8, lower, ".tif") or
        std.mem.endsWith(u8, lower, ".tiff");
}

fn fileBaseNoExt(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return base;
    return base[0..dot];
}

fn joinPath(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ a, b });
}
