const std = @import("std");
const record = @import("record.zig");

pub fn queryJsonl(
    io: std.Io,
    path: []const u8,
    psi: []const u8,
    writer: anytype,
) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &buffer);

    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (std.mem.indexOf(u8, line, psi) != null) {
            try writer.print("{s}", .{line});
        }
    }
}

pub fn appendJsonl(io: std.Io, path: []const u8, rec: record.Record) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{
        .read = true,
        .truncate = false,
        .exclusive = false,
        .lock = .none,
    });
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);

    try writer.interface.print(
        "{{\"originator\":\"0x{x:0>32}\",\"psi\":\"[<:{x:0>32}:>]\",\"long_count\":{d},\"short_count\":{d},\"payload\":\"{s}\"}}\n",
        .{
            rec.originator_id,
            rec.psi,
            rec.long_count,
            rec.short_count,
            rec.payload,
        },
    );

    try writer.interface.flush();
}
