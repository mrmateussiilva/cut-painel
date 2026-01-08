const std = @import("std");
const types = @import("types.zig");

pub const c = @cImport({
    @cInclude("tiffio.h");
});

pub const TiffInfo = struct {
    dpi_x: ?f64 = null,
    dpi_y: ?f64 = null,
};

fn toCstr(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    var buf = try allocator.alloc(u8, s.len + 1);
    std.mem.copyForwards(u8, buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

pub fn loadRGBA(allocator: std.mem.Allocator, path: []const u8, info_out: ?*TiffInfo) !types.Image {
    const c_path = try toCstr(allocator, path);
    defer allocator.free(c_path);

    const tif = c.TIFFOpen(c_path.ptr, "r");
    if (tif == null) return error.TiffOpenFailed;
    defer _ = c.TIFFClose(tif);

    var w: c.uint32 = 0;
    var h: c.uint32 = 0;
    if (c.TIFFGetField(tif, c.TIFFTAG_IMAGEWIDTH, &w) != 1) return error.TiffFieldMissing;
    if (c.TIFFGetField(tif, c.TIFFTAG_IMAGELENGTH, &h) != 1) return error.TiffFieldMissing;
    if (w == 0 or h == 0) return error.InvalidImage;

    // DPI (opcional)
    if (info_out) |info| {
        var xres: f32 = 0;
        var yres: f32 = 0;
        if (c.TIFFGetField(tif, c.TIFFTAG_XRESOLUTION, &xres) == 1) info.dpi_x = @as(f64, xres);
        if (c.TIFFGetField(tif, c.TIFFTAG_YRESOLUTION, &yres) == 1) info.dpi_y = @as(f64, yres);
    }

    const npix: usize = @as(usize, w) * @as(usize, h);
    const raster = try allocator.alloc(c.uint32, npix);
    defer allocator.free(raster);

    // ORIENTATION_TOPLEFT = 1
    const ok = c.TIFFReadRGBAImageOriented(tif, w, h, raster.ptr, 1, 0);
    if (ok == 0) return error.TiffReadFailed;

    const out_len = npix * 4;
    var out = try allocator.alloc(u8, out_len);

    // libtiff retorna 32-bit ABGR (0xAABBGGRR); convertemos para RGBA bytes.
    var i: usize = 0;
    while (i < npix) : (i += 1) {
        const px: u32 = @bitCast(raster[i]);
        const r: u8 = @truncate(px & 0xff);
        const g: u8 = @truncate((px >> 8) & 0xff);
        const b: u8 = @truncate((px >> 16) & 0xff);
        const a: u8 = @truncate((px >> 24) & 0xff);

        const o = i * 4;
        out[o + 0] = r;
        out[o + 1] = g;
        out[o + 2] = b;
        out[o + 3] = a;
    }

    const dpi_final: f64 = if (info_out) |info|
        (info.dpi_x orelse info.dpi_y orelse 300.0)
    else
        300.0;

    return .{
        .allocator = allocator,
        .data = out,
        .width = @intCast(w),
        .height = @intCast(h),
        .channels = 4,
        .dpi = dpi_final,
    };
}

pub fn saveRGBA(img: *const types.Image, path: []const u8, dpi: ?f64) !void {
    if (img.channels != 4) return error.UnsupportedFormat;

    const c_path = try toCstr(img.allocator, path);
    defer img.allocator.free(c_path);

    const tif = c.TIFFOpen(c_path.ptr, "w");
    if (tif == null) return error.TiffOpenFailed;
    defer _ = c.TIFFClose(tif);

    const w: c.uint32 = @intCast(img.width);
    const h: c.uint32 = @intCast(img.height);

    _ = c.TIFFSetField(tif, c.TIFFTAG_IMAGEWIDTH, w);
    _ = c.TIFFSetField(tif, c.TIFFTAG_IMAGELENGTH, h);
    _ = c.TIFFSetField(tif, c.TIFFTAG_SAMPLESPERPIXEL, @as(c.uint16, 4));
    _ = c.TIFFSetField(tif, c.TIFFTAG_BITSPERSAMPLE, @as(c.uint16, 8));
    _ = c.TIFFSetField(tif, c.TIFFTAG_ORIENTATION, @as(c.uint16, 1)); // top-left
    _ = c.TIFFSetField(tif, c.TIFFTAG_PLANARCONFIG, @as(c.uint16, c.PLANARCONFIG_CONTIG));
    _ = c.TIFFSetField(tif, c.TIFFTAG_PHOTOMETRIC, @as(c.uint16, c.PHOTOMETRIC_RGB));

    // Alpha (unassociated)
    var extra: c.uint16 = c.EXTRASAMPLE_UNASSALPHA;
    _ = c.TIFFSetField(tif, c.TIFFTAG_EXTRASAMPLES, @as(c.uint16, 1), &extra);

    // Compressão (LZW). Se não suportado no build do sistema, o arquivo ainda pode ser escrito sem compressão mudando para COMPRESSION_NONE.
    _ = c.TIFFSetField(tif, c.TIFFTAG_COMPRESSION, @as(c.uint16, c.COMPRESSION_LZW));

    // DPI (se fornecido) - senão, usa img.dpi
    const dpi_use: ?f64 = dpi orelse img.dpi;
    if (dpi_use) |d| {
        const xres: f32 = @floatCast(d);
        const yres: f32 = @floatCast(d);
        _ = c.TIFFSetField(tif, c.TIFFTAG_XRESOLUTION, xres);
        _ = c.TIFFSetField(tif, c.TIFFTAG_YRESOLUTION, yres);
        _ = c.TIFFSetField(tif, c.TIFFTAG_RESOLUTIONUNIT, @as(c.uint16, c.RESUNIT_INCH));
    }

    const row_bytes: usize = img.stride();
    var y: c.uint32 = 0;
    while (y < h) : (y += 1) {
        const off = @as(usize, y) * row_bytes;
        const rc = c.TIFFWriteScanline(tif, @ptrCast(&img.data[off]), @intCast(y), 0);
        if (rc < 0) return error.TiffWriteFailed;
    }

    if (c.TIFFFlush(tif) != 1) return error.TiffWriteFailed;
}


