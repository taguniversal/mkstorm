const std = @import("std");
const storm = @import("storm.zig");
const store = @import("store.zig");
const record = @import("record.zig");

const Io = std.Io;

fn parsePsi(psi_text: []const u8) !record.Psi {
    if (!std.mem.startsWith(u8, psi_text, "[<:") or
        !std.mem.endsWith(u8, psi_text, ":>]"))
    {
        return error.InvalidPsi;
    }

    const hex = psi_text[3 .. psi_text.len - 3];
    return try std.fmt.parseInt(record.Psi, hex, 16);
}

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

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var store_path: []const u8 = "data/mkstorm.records.jsonl";
    var store_dir: []const u8 = "data";
    var arg_offset: usize = 1;

    if (args.len >= 3 and std.mem.eql(u8, args[1], "--store")) {
        store_dir = args[2];

        store_path = try std.fmt.allocPrint(
            arena,
            "{s}/mkstorm.records.jsonl",
            .{store_dir},
        );

        arg_offset = 3;
    }


    if (args.len == arg_offset + 2 and std.mem.eql(u8, args[arg_offset], "--query")) {
        const psi = args[arg_offset + 1];
        try store.queryJsonl(io, store_path, psi, stdout_writer);
        try stdout_writer.flush();
        return;
    }

    if (args.len != arg_offset + 4) {
        try stdout_writer.print(
            \\Usage:
            \\  mkstorm --store <storage_path> <psi> <long_count:u64> <short_count:u32> <payload>
            \\
            \\Example:
            \\  mkstorm --store "data/" "[<:4aa0da9e7b0a5fd5985ab55c0f0192fe:>]" 1 0 "memo text"
            \\
        , .{});
        try stdout_writer.flush();
        return;
    }

    const psi = args[arg_offset];
    const long_count = try std.fmt.parseInt(u64, args[arg_offset + 1], 10);
    const short_count = try std.fmt.parseInt(u32, args[arg_offset + 2], 10);
    const payload = args[arg_offset + 3];

    const parsed_psi = try parsePsi(psi);

    var db = storm.Storm.init(1);
    db.state = parsed_psi;
    defer db.deinit(arena);

    const rec = db.ingest(
        psi,
        long_count,
        short_count,
        payload,
    );

    try store.appendJsonl(io, store_path, rec);
    try stdout_writer.print("store: {s}\n", .{store_path});
    try stdout_writer.print("originator: 0x{x:0>32}\n", .{rec.originator_id});
    try stdout_writer.print("psi: [<:{x:0>32}:>]\n", .{rec.psi});
    try stdout_writer.print("long_count: {d}\n", .{rec.long_count});
    try stdout_writer.print("short_count: {d}\n", .{rec.short_count});
    try stdout_writer.print("payload: {s}\n", .{rec.payload});

    try stdout_writer.flush();
}
