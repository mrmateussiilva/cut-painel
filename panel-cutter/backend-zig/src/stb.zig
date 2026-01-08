// Wrappers C para stb_* (vendored em vendor/stb)

pub const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
    @cInclude("stb_image_resize2.h");
});
