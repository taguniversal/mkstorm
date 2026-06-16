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

fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage:
        \\  mkstorm --store <store_dir> ingest <genesis_psi> <block_psi> <long_count:u64> <short_count:u32> <payload>
        \\  mkstorm --store <store_dir> query <genesis_psi> <block_psi>
        \\
        \\Examples:
        \\  mkstorm --store data ingest "[<:genesis:>]" "[<:block:>]" 1 0 "memo text"
        \\  mkstorm --store data query "[<:genesis:>]" "[<:block:>]"
        \\
        \\Storage:
        \\  <store_dir>/<genesis>/<block>/records.jsonl
        \\
    , .{});
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var store_dir: []const u8 = "data";

    var arg_offset: usize = 1;

    if (args.len < arg_offset + 1) {
        try usage(stdout_writer);
        try stdout_writer.flush();
        return;
    }
    if (args.len >= 3 and std.mem.eql(u8, args[1], "--store")) {
        store_dir = args[2];
        arg_offset = 3;
    }

    const command = args[arg_offset];

    if (std.mem.eql(u8, command, "ingest")) {
        if (args.len != arg_offset + 6) {
            try usage(stdout_writer);
            try stdout_writer.flush();
            return;
        }

        const genesis = args[arg_offset + 1];
        const block = args[arg_offset + 2];
        const long_count = try std.fmt.parseInt(u64, args[arg_offset + 3], 10);
        const short_count = try std.fmt.parseInt(u32, args[arg_offset + 4], 10);
        const payload = args[arg_offset + 5];

        var db = storm.Storm.init(1);
        defer db.deinit(arena);

        const rec = db.ingest(
            block,
            long_count,
            short_count,
            payload,
        );

        try store.appendJsonl(
            io,
            arena,
            store_dir,
            genesis,
            block,
            rec,
        );

        try stdout_writer.print("originator: 0x{x:0>32}\n", .{rec.originator_id});
        try stdout_writer.print("psi: [<:{x:0>32}:>]\n", .{rec.psi});
        try stdout_writer.print("long_count: {d}\n", .{rec.long_count});
        try stdout_writer.print("short_count: {d}\n", .{rec.short_count});
        try stdout_writer.print("payload: {s}\n", .{rec.payload});

        try stdout_writer.flush();
        return;
    }

    if (std.mem.eql(u8, command, "query")) {
        if (args.len != arg_offset + 3) {
            try usage(stdout_writer);
            try stdout_writer.flush();
            return;
        }

        const genesis = args[arg_offset + 1];
        const block = args[arg_offset + 2];

        try store.queryJsonl(
            io,
            arena,
            store_dir,
            genesis,
            block,
            stdout_writer,
        );

        try stdout_writer.flush();
        return;
    }

    try usage(stdout_writer);
    try stdout_writer.flush();
}
