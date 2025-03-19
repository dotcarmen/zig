const std = @import("std");
const uefi = std.os.uefi;
const Guid = uefi.Guid;
const Status = uefi.Status;
const hii = uefi.hii;
const cc = uefi.cc;
const Error = Status.Error;
const Handle = uefi.Handle;

/// Database manager for HII-related data structures.
pub const HiiDatabase = extern struct {
    pub const NotifyFn = *const fn (u8, *const Guid, *const hii.PackageHeader, hii.Handle, usize) Status;

    _new_package_list: *const fn (*HiiDatabase, *const hii.PackageHeader) callconv(cc) Status,
    _remove_package_list: *const fn (*HiiDatabase, hii.Handle) callconv(cc) Status,
    _update_package_list: *const fn (*HiiDatabase, hii.Handle, *const hii.PackageList) callconv(cc) Status,
    _list_package_lists: *const fn (*const HiiDatabase, u8, ?*const Guid, *usize, [*]hii.Handle) callconv(cc) Status,
    _export_package_lists: *const fn (*const HiiDatabase, ?hii.Handle, *usize, [*]hii.PackageList) callconv(cc) Status,
    _register_package_notify: *const fn (*HiiDatabase, u8, ?*const Guid, NotifyFn, usize, *Handle) callconv(cc) Status,
    _unregister_package_notify: *const fn (*HiiDatabase, Handle) callconv(cc) Status,
    _find_keyboard_layouts: Status, // TODO
    _get_keyboard_layout: Status, // TODO
    _set_keyboard_layout: Status, // TODO
    _get_package_list_handle: Status, // TODO

    pub const NewPackageListError = uefi.UnexpectedError || error{
        OutOfResources,
        InvalidParameter,
    };
    pub const RemovePackageListError = uefi.UnexpectedError || error{NotFound};
    pub const UpdatePackageListError = uefi.UnexpectedError || error{
        OutOfResources,
        InvalidParameter,
        NotFound,
    };
    pub const ListPackageListsError = uefi.UnexpectedError || error{
        BufferTooSmall,
        InvalidParameter,
        NotFound,
    };
    pub const ExportPackageListError = uefi.UnexpectedError || error{
        BufferTooSmall,
        InvalidParameter,
        NotFound,
    };
    pub const RegisterPackageNotifyError = uefi.UnexpectedError || error{
        OutOfResources,
        InvalidParameter,
    };
    pub const UnregisterPackageNotifyError = uefi.UnexpectedError || error{NotFound};

    // pub fn newPackageList(self: *HiiDatabase, header: *)

    /// Removes a package list from the HII database.
    pub fn removePackageList(self: *HiiDatabase, handle: hii.Handle) !void {
        switch (self._remove_package_list(self, handle)) {
            .success => {},
            .not_found => return Error.NotFound,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    /// Update a package list in the HII database.
    pub fn updatePackageList(
        self: *HiiDatabase,
        handle: hii.Handle,
        buffer: *const hii.PackageList,
    ) UpdatePackageListError!void {
        switch (self._update_package_list(self, handle, buffer)) {
            .success => {},
            .out_of_resources => return Error.OutOfResources,
            .invalid_parameter => return Error.InvalidParameter,
            .not_found => return Error.NotFound,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    /// Determines the handles that are currently active in the database.
    pub fn listPackageLists(
        self: *const HiiDatabase,
        package_type: u8,
        package_guid: ?*const Guid,
        handles: []hii.Handle,
    ) ListPackageListsError![]hii.Handle {
        var len: usize = handles.len;
        switch (self._list_package_lists(
            self,
            package_type,
            package_guid,
            &len,
            handles.ptr,
        )) {
            .success => return handles[0..len],
            .buffer_too_small => return Error.BufferTooSmall,
            .invalid_parameter => return Error.InvalidParameter,
            .not_found => return Error.NotFound,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    /// Exports the contents of one or all package lists in the HII database into a buffer.
    pub fn exportPackageLists(
        self: *const HiiDatabase,
        handle: ?hii.Handle,
        buffer: []hii.PackageList,
    ) ExportPackageListError![]hii.PackageList {
        var len = buffer.len;
        switch (self._export_package_lists(self, handle, &len, buffer.ptr)) {
            .success => return buffer[0..len],
            .buffer_too_small => return Error.BufferTooSmall,
            .invalid_parameter => return Error.InvalidParameter,
            .not_found => return Error.NotFound,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn registerPackageNotify(
        self: *HiiDatabase,
        ty: hii.PackageType,
        package_guid: *const Guid,
        notify: NotifyFn,
        notify_type: NotifyType,
    ) RegisterPackageNotifyError!Handle {
        var result: Handle = undefined;
        switch (self._register_package_notify(
            self,
            @bitCast(ty),
            package_guid,
            notify,
            @bitCast(notify_type),
            &result,
        )) {
            .success => return result,
            .out_of_resources => return Error.OutOfResources,
            .invalid_parameter => return Error.InvalidParameter,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub fn unregisterPackageNotify(
        self: *HiiDatabase,
        handle: Handle,
    ) UnregisterPackageNotifyError!void {
        switch (self._unregister_package_notify(self, handle)) {
            .success => return,
            .not_found => return Error.NotFound,
            else => |status| return uefi.unexpectedStatus(status),
        }
    }

    pub const guid align(8) = Guid{
        .time_low = 0xef9fc172,
        .time_mid = 0xa1b2,
        .time_high_and_version = 0x4693,
        .clock_seq_high_and_reserved = 0xb3,
        .clock_seq_low = 0x27,
        .node = [_]u8{ 0x6d, 0x32, 0xfc, 0x41, 0x60, 0x42 },
    };

    pub const NotifyType = packed struct(usize) {
        new_pack: bool,
        remove_pack: bool,
        export_pack: bool,
        add_pack: bool,
        _pad: std.meta.Int(.unsigned, @typeInfo(usize).int.bits - 4),
    };
};
