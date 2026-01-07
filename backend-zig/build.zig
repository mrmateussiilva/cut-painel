const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Adiciona dependência zstbi
    const zstbi_dep = b.dependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    });

    // Cria shared library
    const lib = b.addSharedLibrary(.{
        .name = "imagecrop",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Linka zstbi
    lib.linkLibrary(zstbi_dep.artifact("zstbi"));
    lib.addIncludePath(zstbi_dep.path("src"));

    // Linka libc (necessário para stb_image_write)
    lib.linkLibC();

    // ASSUMINDO QUE: zstbi inclui stb_image_write ou precisamos adicionar separadamente
    // Se zstbi não incluir, descomente as linhas abaixo para adicionar stb_image_write:
    // const stbi_write_path = zstbi_dep.path("src/stb_image_write.c");
    // lib.addCSourceFile(.{ .file = stbi_write_path, .flags = &.{"-std=c99"} });

    // Instala a biblioteca compartilhada
    // O build.sh copiará para dist/ após compilação
    b.installArtifact(lib);
}

