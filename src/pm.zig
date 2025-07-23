const std = @import("std");

pub const PM = struct {
    file: std.fs.File,

    const Map = struct {
        start: usize,
        end: usize,
        path: ?[]const u8,
    };

    pub fn init(pid: ?std.os.linux.pid_t) !PM {
        var path_buf: [64]u8 = undefined;
        const path = try if (pid) |p|
            std.fmt.bufPrint(&path_buf, "/proc/{d}/maps", .{p})
        else
            std.fmt.bufPrint(&path_buf, "/proc/self/maps", .{});

        const file = try std.fs.openFileAbsolute(path, .{});

        return .{ .file = file };
    }

    pub fn findModule(self: *PM, module_name: []const u8) !Map {
        var buf: [65536]u8 = undefined;
        const bytes_read = try self.file.readAll(&buf);
        const maps_data = buf[0..bytes_read];

        var min_start: usize = std.math.maxInt(usize);
        var max_end: usize = 0;
        var found = false;
        var found_path: ?[]const u8 = null;

        var lines = std.mem.tokenizeScalar(u8, maps_data, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, module_name) == null) continue;

            const map = try PM.parse(line);

            min_start = @min(min_start, map.start);
            max_end = @max(max_end, map.end);

            // Only set the path if we haven't found one yet
            if (found_path == null) {
                found_path = map.path;
            }
            found = true;
        }

        if (!found) return error.ModuleNotFound;

        return Map{
            .start = min_start,
            .end = max_end,
            .path = found_path,
        };
    }

    pub inline fn parse(line: []const u8) !Map {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');

        const mem_range_str = tokens.next() orelse return error.FailedToParseMemRange;

        const dash_index = std.mem.indexOfScalar(u8, mem_range_str, '-') orelse return error.FailedToParseMemRange;
        const start = try std.fmt.parseInt(usize, mem_range_str[0..dash_index], 16);
        const end = try std.fmt.parseInt(usize, mem_range_str[dash_index + 1 ..], 16);

        _ = tokens.next() orelse return error.FailedToParsePerms;
        _ = tokens.next() orelse return error.FailedToParseOffset;
        _ = tokens.next() orelse return error.FailedToParseDev;
        _ = tokens.next() orelse return error.FailedToParseInode;

        const path = std.mem.trim(u8, tokens.rest(), " ");

        return Map{
            .start = start,
            .end = end,
            .path = path,
        };
    }

    pub fn deinit(self: *PM) void {
        self.file.close();
    }
};

test "PM" {
    const data =
        \\ 7f88b5af7000-7f88b5b0b000 r--p 00033000 00:17 6420                       /usr/lib/libdbus-1.so.3.38.3
    ;

    const map = try PM.parse(data);
    std.debug.print("{x} - {x}\t{?s}\n", .{ map.start, map.end, map.path });
}
