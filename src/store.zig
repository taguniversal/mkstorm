const std = @import("std");
const record = @import("record.zig");

fn cleanPsi(psi: []const u8) []const u8 {
    return std.mem.trim(u8, psi, " \t\r\n[]<>:");
}

fn recordPath(
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    genesis: []const u8,
    block: []const u8,
) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}/{s}/{s}/records.jsonl",
        .{
            store_dir,
            cleanPsi(genesis),
            cleanPsi(block),
        },
    );
}

pub fn appendJsonl(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    genesis: []const u8,
    block: []const u8,
    rec: record.Record,
) !void {
    try ensurePath(io, allocator, store_dir, genesis, block);
    const path = try recordPath(allocator, store_dir, genesis, block);

    var file = try std.Io.Dir.cwd().createFile(io, path, .{
        .read = true,
        .truncate = false,
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

pub fn queryJsonl(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    genesis: []const u8,
    block: []const u8,
    writer: anytype,
) !void {
    const path = try recordPath(allocator, store_dir, genesis, block);

    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &buffer);

    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        try writer.print("{s}", .{line});
    }
}

fn ensurePath(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    genesis: []const u8,
    block: []const u8,
) !void {
    const block_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}/{s}",
        .{ store_dir, cleanPsi(genesis), cleanPsi(block) },
    );
    defer allocator.free(block_dir);

    try std.Io.Dir.cwd().createDirPath(io, block_dir);
}

test "store records under genesis and block psi directories" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = std.Io.default;

    const store_dir = "test_store";

    const genesis = "[<:677c09a5d6610026b0f807bd2e29ae8a:>]";

    const blocks = [_][]const u8{
        "[<:677c09a5d6610026b0f807bd2e29ae8a:>]",
        "[<:d2ec8a622f5d1b3a369a0d86e856099d:>]",
        "[<:3e92d5a498acc85ca92a1259b8f0383e:>]",
        "[<:5d97d28e1a405efa8d3268a73752d132:>]",
        "[<:7dae35c4e51ae25089f9e04eaa3b88e5:>]",
    };

    for (blocks, 0..) |block, i| {
        const rec = record.Record{
            .originator_id = 1,
            .psi = try std.fmt.parseInt(record.Psi, block[3 .. block.len - 3], 16),
            .long_count = @intCast(i + 1),
            .short_count = 0,
            .payload = try std.fmt.allocPrint(
                allocator,
                "memo for block {d}",
                .{i + 1},
            ),
        };

        const path = try recordPath(allocator, store_dir, genesis, block);
        std.debug.print("path={s}\n", .{path});

        try appendJsonl(
            io,
            allocator,
            store_dir,
            genesis,
            block,
            rec,
        );
    }

    for (blocks, 0..) |block, i| {
        const path = try recordPath(
            allocator,
            store_dir,
            genesis,
            block,
        );

        const file_contents =
            try std.Io.Dir.cwd().readFileAlloc(io, allocator, path, 4096);

        defer allocator.free(file_contents);

        const expected = try std.fmt.allocPrint(
            allocator,
            "memo for block {d}",
            .{i + 1},
        );

        defer allocator.free(expected);

        try testing.expect(std.mem.indexOf(u8, file_contents, expected) != null);
        try testing.expect(std.mem.indexOf(u8, file_contents, block) != null);
    }
}
