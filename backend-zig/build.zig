const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const default_enable_tiff = target.result.os.tag != .windows;
    const enable_tiff = b.option(bool, "enable_tiff", "Habilita suporte a TIFF via libtiff (Linux/macOS). Para Windows, exige libtiff disponível no toolchain.") orelse default_enable_tiff;
    const tiff_include_dir = b.option([]const u8, "tiff_include_dir", "Diretório de include do libtiff (ex.: vcpkg/installed/x64-windows/include)");
    const tiff_lib_dir = b.option([]const u8, "tiff_lib_dir", "Diretório de libs (.lib/.a) do libtiff (ex.: vcpkg/installed/x64-windows/lib)");

    const opts = b.addOptions();
    opts.addOption(bool, "enable_tiff", enable_tiff);

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = opts.createModule() },
        },
    });

    const lib = b.addLibrary(.{
        .name = "imgcutter",
        .root_module = root_mod,
        .linkage = .dynamic,
    });

    lib.linkLibC();

    // stb (vendored)
    lib.addIncludePath(b.path("vendor/stb"));
    lib.addCSourceFile(.{
        .file = b.path("vendor/stb/stb_impl.c"),
        .flags = &.{"-std=c99"},
    });

    if (enable_tiff) {
        // libtiff (sistema / vcpkg)
        if (tiff_include_dir) |p| lib.addIncludePath(.{ .cwd_relative = p });
        if (tiff_lib_dir) |p| lib.addLibraryPath(.{ .cwd_relative = p });
        lib.linkSystemLibrary("tiff");
    }

    b.installArtifact(lib);
}
