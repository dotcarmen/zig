const std = @import("std");
const uefi = std.os.uefi;
const Guid = uefi.Guid;

pub const Handle = *opaque {};

/// The header found at the start of each package.
pub const PackageHeader = packed struct(u32) {
    length: u24,
    type: PackageType,

    pub fn getDataBytes(self: *PackageHeader) ?[]u8 {
        if (self.length == @sizeOf(PackageHeader)) return null;
        const ptr: [*]u8 = @ptrCast(&self._data);
        const size: usize = @sizeOf(PackageHeader);
        return ptr[size .. size + self.length];
    }

    pub fn getData(self: *PackageHeader) PackageType.Data {
        switch (self.type) {
            inline .type_all, .end, .type_system_begin, .type_system_end => |tag| {
                return @unionInit(PackageType.Data, tag, {});
            },
            .type_guid => {
                const bytes = self.getDataBytes().?;
                const guid: *const Guid = @ptrCast(bytes[0..16].ptr);
                const data: *const anyopaque = @ptrCast(bytes[16..].ptr);
                return @unionInit(PackageType.Data, .type_guid, .{
                    .guid = guid,
                    .data = data,
                });
            },
            inline else => |tag| {
                const Payload = std.meta.TagPayload(PackageType.Data, tag);
                const payload: Payload = @ptrCast(self.getDataBytes().?.ptr);
                return @unionInit(
                    PackageType.Data,
                    @tagName(tag),
                    payload,
                );
            },
        }
    }

    pub fn next(self: *PackageHeader) ?*PackageHeader {
        // The package lists form ... terminated with ... a Type of EFI_HII_PACKAGE_END
        if (self.type == .end) return null;
        const ptr: [*]u8 = @ptrCast(self);
        // When added to a pointer pointing to the start of the header, Length
        // points at the next package.
        return @ptrCast(ptr[self.length]);
    }
};

pub const PackageType = enum(u8) {
    type_all = 0x00,
    type_guid = 0x01,
    forms = 0x02,
    strings = 0x04,
    fonts = 0x05,
    images = 0x06,
    simple_fonts = 0x07,
    device_path = 0x08,
    keyboard_layout = 0x09,
    animations = 0x0a,
    end = 0xdf,
    type_system_begin = 0xe0,
    type_system_end = 0xff,

    pub const Data = union(PackageType) {
        type_all,
        type_guid: struct {
            guid: *const Guid,
            data: *const anyopaque,
        },
        forms: *FormPackage,
        strings: *StringPackage,
        fonts: *FontPackage,
        images: *ImagePackage,
        simple_fonts: *SimpleFontPackage,
        device_path: *DevicePathPackage,
        keyboard_layout: *KeyboardLayoutPackage,
        animations: *AnimationPackage,
        end,
        type_system_begin,
        type_system_end,
    };
};

/// The header found at the start of each package list.
pub const PackageList = extern struct {
    package_list_guid: Guid,

    /// The size of the package list (in bytes), including the header.
    package_list_length: u32,

    // TODO implement iterator
};

pub const FormPackage = extern struct {};

pub const StringPackage = extern struct {
    header: PackageHeader,
    hdr_size: u32,
    string_info_offset: u32,
    language_window: [16]u16,
    language_name: u16,
    language: [3]u8,
};

pub const FontPackage = extern struct {
    header: PackageHeader,
    hdr_size: u32,
    glyph_block_offset: u32,
    cell: GlyphInfo,
    font_style: FontStyle,
    _font_family: u16,

    pub fn fontFamily(self: *FontPackage) [*:0]u16 {
        return @ptrCast(&self._font_family);
    }

    pub fn block(self: *FontPackage) *GlyphBlock {
        const ptr: [*]u8 = @ptrCast(self);
        return @ptrCast(ptr[self.glyph_block_offset..]);
    }

    pub const FontStyle = packed struct(u32) {
        // 0x00000001
        bold: bool = false,
        // 0x00000002
        italic: bool = false,
        _pad0: u14 = 0,
        // 0x00010000
        emboss: bool = false,
        // 0x00020000
        outline: bool = false,
        // 0x00040000
        shadow: bool = false,
        // 0x00080000
        underline: bool = false,
        // 0x00100000
        dbl_under: bool = false,
        _pad1: u21 = 0,
    };

    pub const GlyphBlock = extern struct {
        block_type: BlockType,
        _block_body: u8,

        pub fn next(self: *GlyphBlock) ?*GlyphBlock {
            const bytes: [*]u8 = @ptrCast(self);
            const next_block: *GlyphBlock = @ptrCast(bytes + @sizeOf(GlyphBlock));
            if (next_block.block_type == BlockType.end) return null;
            return next_block;
        }

        pub const BlockType = enum(u8) {
            end = 0x00,
            glyph = 0x10,
            glyphs = 0x11,
            glyph_default = 0x12,
            glyphs_default = 0x13,
            glyph_variability = 0x14,
            duplicate = 0x20,
            skip2 = 0x21,
            skip1 = 0x22,
            defaults = 0x23,
            ext1 = 0x30,
            ext2 = 0x31,
            ext4 = 0x32,
        };
    };

    pub const GlyphInfo = extern struct {
        width: u16,
        height: u16,
        offset_x: i16,
        offset_y: i16,
        advance_x: i16,
    };
};

pub const ImagePackage = extern struct {};

pub const SimpleFontPackage = extern struct {
    header: PackageHeader,
    number_of_narrow_glyphs: u16,
    number_of_wide_glyphs: u16,

    pub fn getNarrowGlyphs(self: *SimpleFontPackage) []NarrowGlyph {
        const bytes: [*]u8 = @ptrCast(self);
        const glyphs: [*]NarrowGlyph = @ptrCast(bytes + @sizeOf(SimpleFontPackage));
        return glyphs[0..self.number_of_narrow_glyphs];
    }

    pub fn getWideGlyphs(self: *SimpleFontPackage) []WideGlyph {
        const narrow_glyphs = self.getNarrowGlyphs();
        const glyphs: [*]WideGlyph = @ptrCast(narrow_glyphs.ptr[narrow_glyphs.len + 1]);
        return glyphs[0..self.number_of_wide_glyphs];
    }
};

pub const DevicePathPackage = extern struct {};

pub const KeyboardLayoutPackage = extern struct {};

pub const AnimationPackage = extern struct {};

pub const NarrowGlyph = extern struct {
    unicode_weight: u16,
    attributes: Attributes,
    glyph_col_1: [19]u8,

    pub const Attributes = packed struct(u8) {
        non_spacing: bool,
        wide: bool,
        _pad: u6 = 0,
    };
};

pub const WideGlyph = extern struct {
    unicode_weight: u16,
    attributes: Attributes,
    glyph_col_1: [19]u8,
    glyph_col_2: [19]u8,
    _pad: [3]u8 = [_]u8{0} ** 3,

    pub const Attributes = packed struct(u8) {
        non_spacing: bool,
        wide: bool,
        _pad: u6 = 0,
    };
};
