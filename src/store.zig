const std = @import("std");
const record = @import("record.zig");

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
