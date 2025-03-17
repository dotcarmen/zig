const std = @import("std");
const uefi = std.os.uefi;
const io = std.io;
const Guid = uefi.Guid;
const Time = uefi.Time;
const Status = uefi.Status;
const cc = uefi.cc;
const Error = Status.Error;

pub const File = extern struct {
    revision: u64,
    _open: *const fn (*const File, **File, [*:0]const u16, u64, u64) callconv(cc) Status,
    _close: *const fn (*File) callconv(cc) Status,
    _delete: *const fn (*File) callconv(cc) Status,
    _read: *const fn (*File, *usize, [*]u8) callconv(cc) Status,
    _write: *const fn (*File, *usize, [*]const u8) callconv(cc) Status,
    _get_position: *const fn (*const File, *u64) callconv(cc) Status,
    _set_position: *const fn (*File, u64) callconv(cc) Status,
    _get_info: *const fn (*const File, *align(8) const Guid, *const usize, [*]u8) callconv(cc) Status,
    _set_info: *const fn (*File, *align(8) const Guid, usize, [*]const u8) callconv(cc) Status,
    _flush: *const fn (*File) callconv(cc) Status,

    pub const OpenError = uefi.UnexpectedError || error{
        NotFound,
        NoMedia,
        MediaChanged,
        DeviceError,
        VolumeCorrupted,
        WriteProtected,
        AccessDenied,
        OutOfResources,
        VolumeFull,
        InvalidParameter,
    };
    pub const CloseError = uefi.UnexpectedError;
    // seek and position have the same errors
    pub const SeekError = uefi.UnexpectedError || error{ Unsupported, DeviceError };
    pub const ReadError = uefi.UnexpectedError || error{ NoMedia, DeviceError, VolumeCorrupted, BufferTooSmall };
    pub const WriteError = uefi.UnexpectedError || error{
        Unsupported,
        NoMedia,
        DeviceError,
        VolumeCorrupted,
        WriteProtected,
        AccessDenied,
        VolumeFull,
    };
    pub const GetInfoError = uefi.UnexpectedError || error{
        Unsupported,
        NoMedia,
        DeviceError,
        VolumeCorrupted,
        BufferTooSmall,
    };
    pub const SetInfoError = uefi.UnexpectedError || error{
        Unsupported,
        NoMedia,
        DeviceError,
        VolumeCorrupted,
        WriteProtected,
        AccessDenied,
        VolumeFull,
        BadBufferWSize,
    };
    pub const FlushError = uefi.UnexpectedError || error{
        DeviceError,
        VolumeCorrupted,
        WriteProtected,
        AccessDenied,
        VolumeFull,
    };

    pub const SeekableStream = io.SeekableStream(
        *File,
        SeekError,
        SeekError,
        setPosition,
        seekBy,
        getPosition,
        getEndPos,
    );
    pub const Reader = io.Reader(*File, ReadError, read);
    pub const Writer = io.Writer(*File, WriteError, write);

    pub fn seekableStream(self: *File) SeekableStream {
        return .{ .context = self };
    }

    pub fn reader(self: *File) Reader {
        return .{ .context = self };
    }

    pub fn writer(self: *File) Writer {
        return .{ .context = self };
    }

    pub fn open(
        self: *const File,
        file_name: [*:0]const u16,
        mode: OpenMode,
        create_attributes: Attributes,
    ) OpenError!*File {
        var new: *File = undefined;
        switch (self._open(self, &new, file_name, @intFromEnum(mode), create_attributes)) {
            .success => return new,
            .not_found => return Error.NotFound,
            .no_media => return Error.NoMedia,
            .media_changed => return Error.MediaChanged,
            .device_error => return Error.DeviceError,
            .volume_corrupted => return Error.VolumeCorrupted,
            .write_protected => return Error.WriteProtected,
            .access_denied => return Error.AccessDenied,
            .out_of_resources => return Error.OutOfResources,
            .volume_full => return Error.VolumeFull,
            .invalid_parameter => return Error.InvalidParameter,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn close(self: *File) CloseError!void {
        switch (self._close(self)) {
            .success => {},
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    /// Delete the file.
    ///
    /// Returns true if the file was deleted, false if the file was not deleted, which is a warning
    /// according to the UEFI specification.
    pub fn delete(self: *File) bool {
        switch (self._delete(self)) {
            .success => return true,
            .warn_delete_failure => return false,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn read(self: *File, buffer: []u8) ReadError!usize {
        var size: usize = buffer.len;
        switch (self._read(self, &size, buffer.ptr)) {
            .success => return size,
            .no_media => return Error.NoMedia,
            .device_error => return Error.DeviceError,
            .volume_corrupted => return Error.VolumeCorrupted,
            .buffer_too_small => return Error.BufferTooSmall,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn write(self: *File, buffer: []const u8) WriteError!usize {
        var size: usize = buffer.len;
        switch (self._write(self, &size, buffer.ptr)) {
            .success => return size,
            .unsupported => return Error.Unsupported,
            .no_media => return Error.NoMedia,
            .device_error => return Error.DeviceError,
            .volume_corrupted => return Error.VolumeCorrupted,
            .write_protected => return Error.WriteProtected,
            .access_denied => return Error.AccessDenied,
            .volume_full => return Error.VolumeFull,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn getPosition(self: *const File) SeekError!u64 {
        var position: u64 = undefined;
        switch (self._get_position(self, &position)) {
            .success => return position,
            .unsupported => return Error.Unsupported,
            .device_error => return Error.DeviceError,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    fn getEndPos(self: *File) SeekError!u64 {
        const start_pos = try self.getPosition();
        // ignore error
        defer _ = self.setPosition(start_pos) catch {};

        try self.setPosition(efi_file_position_end_of_file);
        return self.getPosition();
    }

    pub fn setPosition(self: *File, position: u64) SeekError!void {
        switch (self._set_position(self, position)) {
            .success => {},
            .unsupported => return Error.Unsupported,
            .device_error => return Error.DeviceError,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    fn seekBy(self: *File, offset: i64) SeekError!void {
        var pos = try self.getPosition();
        const seek_back = offset < 0;
        const amt = @abs(offset);
        if (seek_back) {
            pos += amt;
        } else {
            pos -= amt;
        }
        try self.setPosition(pos);
    }

    pub fn getInfo(
        self: *const File,
        comptime information_type: std.meta.Tag(Info),
    ) GetInfoError!@FieldType(Info, @tagName(information_type)) {
        const InfoData = @FieldType(Info, @tagName(information_type));
        var val: InfoData = undefined;
        var len = @sizeOf(InfoData);
        switch (self._get_info(self, &InfoData.guid, &len, @ptrCast(&val))) {
            .success => {},
            .unsupported => return Error.Unsupported,
            .no_media => return Error.NoMedia,
            .device_error => return Error.DeviceError,
            .volume_corrupted => return Error.VolumeCorrupted,
            .buffer_too_small => return Error.BufferTooSmall,
            else => |status| return uefi.unexpectedStatus(status),
        }

        if (len != @sizeOf(InfoData))
            return error.Unexpected
        else
            return val;
    }

    pub fn setInfo(
        self: *const File,
        information_type: *align(8) const Guid,
        buffer: []const u8,
    ) SetInfoError!void {
        switch (self._set_info(self, information_type, buffer.len, buffer.ptr)) {
            .success => {},
            .unsupported => return Error.Unsupported,
            .no_media => return Error.NoMedia,
            .device_error => return Error.DeviceError,
            .volume_corrupted => return Error.VolumeCorrupted,
            .write_protected => return Error.WriteProtected,
            .access_denied => return Error.AccessDenied,
            .volume_full => return Error.VolumeFull,
            .bad_buffer_size => return Error.BadBufferSize,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn flush(self: *File) FlushError!void {
        switch (self._flush(self)) {
            .success => {},
            .device_error => return Error.DeviceError,
            .volume_corrupted => return Error.VolumeCorrupted,
            .write_protected => return Error.WriteProtected,
            .access_denied => return Error.AccessDenied,
            .volume_full => return Error.VolumeFull,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub const OpenMode = enum(u64) {
        read = 0x0000000000000001,
        // implies read
        write = 0x0000000000000002,
        // implies read+write
        create = 0x8000000000000000,
    };

    pub const Attributes = packed struct(u64) {
        // 0x0000000000000001
        read_only: bool = false,
        // 0x0000000000000002
        hidden: bool = false,
        // 0x0000000000000004
        system: bool = false,
        // 0x0000000000000008
        reserved: bool = false,
        // 0x0000000000000010
        directory: bool = false,
        // 0x0000000000000020
        archive: bool = false,
        // used exclusively for `valid_attr` as far as i can tell...
        _flag: bool = false,
        _pad: u57 = 0,

        // 0x0000000000000037
        pub const valid_attr: Attributes = .{
            .read_only = true,
            .system = true,
            ._flag = true,
        };
    };

    pub const Info = union(enum) {
        file: Info.File,
        volume: Info.Volume,
        volume_label: Info.VolumeLabel,

        pub const File = extern struct {
            size: u64,
            file_size: u64,
            physical_size: u64,
            create_time: uefi.Time,
            last_access_time: uefi.Time,
            modification_time: uefi.Time,
            attribute: Attributes,
            file_name: [*:0]const u16,

            pub const guid align(8) = Guid{
                .time_low = 0x9576e92,
                .time_mid = 0x6d3f,
                .time_high_and_version = 0x11d2,
                .clock_seq_high_and_reserved = 0x8e,
                .clock_seq_low = 0x39,
                .node = .{ 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b },
            };
        };

        pub const Volume = extern struct {
            size: u64,
            read_only: bool,
            volume_size: u64,
            free_space: u64,
            block_size: u32,
            volume_label: [*:0]const u16,

            pub const guid align(8) = Guid{
                .time_low = 0x9576e93,
                .time_mid = 0x6d3f,
                .time_high_and_version = 0x11d2,
                .clock_seq_high_and_reserved = 0x8e,
                .clock_seq_low = 0x39,
                .node = .{ 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b },
            };
        };

        pub const VolumeLabel = extern struct {
            volume_label: [*:0]const u16,

            pub const guid align(8) = Guid{
                .time_low = 0xdb47d7d3,
                .time_mid = 0xfe81,
                .time_high_and_version = 0x11d3,
                .clock_seq_high_and_reserved = 0x9a,
                .clock_seq_low = 0x35,
                .node = .{ 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d },
            };
        };
    };

    const efi_file_position_end_of_file: u64 = 0xffffffffffffffff;
};
