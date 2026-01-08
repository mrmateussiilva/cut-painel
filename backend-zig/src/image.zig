const std = @import("std");
const types = @import("types.zig");
const stb = @import("stb.zig");
const build_options = @import("build_options");

const tiff = if (build_options.enable_tiff) @import("tiff.zig") else void;

pub const ImageOps = struct {
    fn toCstr(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
        var buf = try allocator.alloc(u8, s.len + 1);
        std.mem.copyForwards(u8, buf[0..s.len], s);
        buf[s.len] = 0;
        return buf[0..s.len :0];
    }

    fn isTiff(path: []const u8) bool {
        // case-insensitive endsWith(.tif/.tiff)
        if (path.len < 4) return false;
        const ext4 = path[path.len - 4 ..];
        if (std.ascii.eqlIgnoreCase(ext4, ".tif")) return true;
        if (path.len >= 5) {
            const ext5 = path[path.len - 5 ..];
            if (std.ascii.eqlIgnoreCase(ext5, ".tiff")) return true;
        }
        return false;
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !types.Image {
        if (build_options.enable_tiff and isTiff(path)) {
            var info = tiff.TiffInfo{};
            return try tiff.loadRGBA(allocator, path, &info);
        }

        var w: c_int = 0;
        var h: c_int = 0;
        var comp_in_file: c_int = 0;

        const c_path = try toCstr(allocator, path);
        defer allocator.free(c_path);

        const desired_comp: c_int = 4; // RGBA
        const raw = stb.c.stbi_load(c_path.ptr, &w, &h, &comp_in_file, desired_comp);
        if (raw == null) {
            const reason = stb.c.stbi_failure_reason();
            if (reason != null) {
                std.log.err("stbi_load falhou: {s}", .{std.mem.sliceTo(reason, 0)});
            }
            return error.LoadFailed;
        }
        defer stb.c.stbi_image_free(raw);

        if (w <= 0 or h <= 0) return error.InvalidImage;

        const width: u32 = @intCast(w);
        const height: u32 = @intCast(h);
        const channels: u8 = 4;
        const len = @as(usize, width) * @as(usize, height) * @as(usize, channels);

        const data = try allocator.alloc(u8, len);
        std.mem.copyForwards(u8, data, @as([*]const u8, @ptrCast(raw))[0..len]);

        return .{
            .allocator = allocator,
            .data = data,
            .width = width,
            .height = height,
            .channels = channels,
            .dpi = 300.0,
        };
    }

    pub fn savePng(img: *const types.Image, path: []const u8) !void {
        const c_path = try toCstr(img.allocator, path);
        defer img.allocator.free(c_path);

        const ok = stb.c.stbi_write_png(
            c_path.ptr,
            @intCast(img.width),
            @intCast(img.height),
            @intCast(img.channels),
            img.data.ptr,
            @intCast(img.stride()),
        );
        if (ok == 0) return error.SaveFailed;
    }

    pub fn saveJpg(img: *const types.Image, path: []const u8, quality: i32) !void {
        const c_path = try toCstr(img.allocator, path);
        defer img.allocator.free(c_path);

        const ok = stb.c.stbi_write_jpg(
            c_path.ptr,
            @intCast(img.width),
            @intCast(img.height),
            @intCast(img.channels),
            img.data.ptr,
            @intCast(quality),
        );
        if (ok == 0) return error.SaveFailed;
    }

    pub fn saveTiff(img: *const types.Image, path: []const u8) !void {
        if (!build_options.enable_tiff) return error.TiffDisabled;
        try tiff.saveRGBA(img, path, null);
    }

    pub fn crop(allocator: std.mem.Allocator, img: *const types.Image, x: u32, y: u32, w: u32, h: u32) !types.Image {
        if (w == 0 or h == 0) return error.InvalidCrop;
        if (x + w > img.width or y + h > img.height) return error.InvalidCrop;
        if (img.channels != 4) return error.UnsupportedFormat;

        const channels: u8 = 4;
        const out_len = @as(usize, w) * @as(usize, h) * @as(usize, channels);
        var out = try allocator.alloc(u8, out_len);

        const src_stride = img.stride();
        const dst_stride = @as(usize, w) * channels;

        var row: u32 = 0;
        while (row < h) : (row += 1) {
            const src_off = (@as(usize, y + row) * src_stride) + (@as(usize, x) * channels);
            const dst_off = @as(usize, row) * dst_stride;
            std.mem.copyForwards(u8, out[dst_off .. dst_off + dst_stride], img.data[src_off .. src_off + dst_stride]);
        }

        return .{
            .allocator = allocator,
            .data = out,
            .width = w,
            .height = h,
            .channels = channels,
            .dpi = img.dpi,
        };
    }

    pub fn rotate90CW(allocator: std.mem.Allocator, img: *const types.Image) !types.Image {
        if (img.channels != 4) return error.UnsupportedFormat;

        const new_w: u32 = img.height;
        const new_h: u32 = img.width;
        const channels: u8 = 4;
        const out_len = @as(usize, new_w) * @as(usize, new_h) * channels;
        var out = try allocator.alloc(u8, out_len);

        var y: u32 = 0;
        while (y < img.height) : (y += 1) {
            var x: u32 = 0;
            while (x < img.width) : (x += 1) {
                const src_i = (@as(usize, y) * img.stride()) + (@as(usize, x) * channels);

                const dx: u32 = (img.height - 1) - y;
                const dy: u32 = x;
                const dst_i = (@as(usize, dy) * @as(usize, new_w) * channels) + (@as(usize, dx) * channels);

                std.mem.copyForwards(u8, out[dst_i .. dst_i + channels], img.data[src_i .. src_i + channels]);
            }
        }

        return .{
            .allocator = allocator,
            .data = out,
            .width = new_w,
            .height = new_h,
            .channels = channels,
            .dpi = img.dpi,
        };
    }

    pub fn rotate270CW(allocator: std.mem.Allocator, img: *const types.Image) !types.Image {
        if (img.channels != 4) return error.UnsupportedFormat;

        const new_w: u32 = img.height;
        const new_h: u32 = img.width;
        const channels: u8 = 4;
        const out_len = @as(usize, new_w) * @as(usize, new_h) * channels;
        var out = try allocator.alloc(u8, out_len);

        var y: u32 = 0;
        while (y < img.height) : (y += 1) {
            var x: u32 = 0;
            while (x < img.width) : (x += 1) {
                const src_i = (@as(usize, y) * img.stride()) + (@as(usize, x) * channels);

                const dx: u32 = y;
                const dy: u32 = (img.width - 1) - x;
                const dst_i = (@as(usize, dy) * @as(usize, new_w) * channels) + (@as(usize, dx) * channels);

                std.mem.copyForwards(u8, out[dst_i .. dst_i + channels], img.data[src_i .. src_i + channels]);
            }
        }

        return .{
            .allocator = allocator,
            .data = out,
            .width = new_w,
            .height = new_h,
            .channels = channels,
            .dpi = img.dpi,
        };
    }

    pub fn addContour1px(img: *types.Image) void {
        if (img.channels != 4 or img.width < 2 or img.height < 2) return;

        const channels: usize = 4;
        const w = img.width;
        const h = img.height;
        const stride = img.stride();

        // top + bottom
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            setRGBA(img.data, (@as(usize, 0) * stride) + (@as(usize, x) * channels), 0, 0, 0, 255);
            setRGBA(img.data, (@as(usize, h - 1) * stride) + (@as(usize, x) * channels), 0, 0, 0, 255);
        }

        // left + right
        var y: u32 = 0;
        while (y < h) : (y += 1) {
            setRGBA(img.data, (@as(usize, y) * stride) + (@as(usize, 0) * channels), 0, 0, 0, 255);
            setRGBA(img.data, (@as(usize, y) * stride) + (@as(usize, w - 1) * channels), 0, 0, 0, 255);
        }
    }

    pub fn addPadding(allocator: std.mem.Allocator, img: *const types.Image, pad_px: u32) !types.Image {
        if (pad_px == 0) {
            // clone
            const out = try allocator.alloc(u8, img.data.len);
            std.mem.copyForwards(u8, out, img.data);
            return .{ .allocator = allocator, .data = out, .width = img.width, .height = img.height, .channels = img.channels, .dpi = img.dpi };
        }
        if (img.channels != 4) return error.UnsupportedFormat;

        const new_w: u32 = img.width + 2 * pad_px;
        const new_h: u32 = img.height + 2 * pad_px;
        const channels: u8 = 4;
        const out_len = @as(usize, new_w) * @as(usize, new_h) * 4;

        const out = try allocator.alloc(u8, out_len);
        // fill white
        var i: usize = 0;
        while (i < out.len) : (i += 4) {
            out[i + 0] = 255;
            out[i + 1] = 255;
            out[i + 2] = 255;
            out[i + 3] = 255;
        }

        const src_stride = img.stride();
        const dst_stride = @as(usize, new_w) * 4;
        var row: u32 = 0;
        while (row < img.height) : (row += 1) {
            const src_off = @as(usize, row) * src_stride;
            const dst_off = (@as(usize, row + pad_px) * dst_stride) + (@as(usize, pad_px) * 4);
            std.mem.copyForwards(u8, out[dst_off .. dst_off + src_stride], img.data[src_off .. src_off + src_stride]);
        }

        return .{
            .allocator = allocator,
            .data = out,
            .width = new_w,
            .height = new_h,
            .channels = channels,
            .dpi = img.dpi,
        };
    }

    pub fn pasteRGBA(dst: *types.Image, src: *const types.Image, x0: i32, y0: i32) void {
        if (dst.channels != 4 or src.channels != 4) return;

        const dst_w: i32 = @intCast(dst.width);
        const dst_h: i32 = @intCast(dst.height);
        const src_w: i32 = @intCast(src.width);
        const src_h: i32 = @intCast(src.height);

        var y: i32 = 0;
        while (y < src_h) : (y += 1) {
            const dy = y0 + y;
            if (dy < 0 or dy >= dst_h) continue;

            var x: i32 = 0;
            while (x < src_w) : (x += 1) {
                const dx = x0 + x;
                if (dx < 0 or dx >= dst_w) continue;

                const si: usize = (@as(usize, @intCast(y)) * src.stride()) + (@as(usize, @intCast(x)) * 4);
                const di: usize = (@as(usize, @intCast(dy)) * dst.stride()) + (@as(usize, @intCast(dx)) * 4);

                const sa: u8 = src.data[si + 3];
                if (sa == 0) continue;

                // alpha blend simples
                const a: f32 = @as(f32, @floatFromInt(sa)) / 255.0;
                const inv: f32 = 1.0 - a;

                dst.data[di + 0] = @intFromFloat(@min(255.0, a * @as(f32, @floatFromInt(src.data[si + 0])) + inv * @as(f32, @floatFromInt(dst.data[di + 0]))));
                dst.data[di + 1] = @intFromFloat(@min(255.0, a * @as(f32, @floatFromInt(src.data[si + 1])) + inv * @as(f32, @floatFromInt(dst.data[di + 1]))));
                dst.data[di + 2] = @intFromFloat(@min(255.0, a * @as(f32, @floatFromInt(src.data[si + 2])) + inv * @as(f32, @floatFromInt(dst.data[di + 2]))));
                dst.data[di + 3] = 255;
            }
        }
    }

    pub fn resizeRGBA(allocator: std.mem.Allocator, src: *const types.Image, new_w: u32, new_h: u32) !types.Image {
        if (src.channels != 4) return error.UnsupportedFormat;
        if (new_w == 0 or new_h == 0) return error.InvalidResize;

        const out_len = @as(usize, new_w) * @as(usize, new_h) * 4;
        const out = try allocator.alloc(u8, out_len);

        _ = stb.c.stbir_resize_uint8_linear(
            src.data.ptr,
            @intCast(src.width),
            @intCast(src.height),
            @intCast(src.stride()),
            out.ptr,
            @intCast(new_w),
            @intCast(new_h),
            @intCast(@as(usize, new_w) * 4),
            stb.c.STBIR_RGBA,
        );

        return .{ .allocator = allocator, .data = out, .width = new_w, .height = new_h, .channels = 4, .dpi = src.dpi };
    }

    fn setRGBA(buf: []u8, idx: usize, r: u8, g: u8, b: u8, a: u8) void {
        buf[idx + 0] = r;
        buf[idx + 1] = g;
        buf[idx + 2] = b;
        buf[idx + 3] = a;
    }
};
