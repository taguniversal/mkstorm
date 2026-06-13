const std = @import("std");
const storm = @import("storm.zig");

const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var db = storm.Storm.init(1);
    defer db.deinit(init.arena.allocator());

    const rec = db.ingest("temperature=72.5");

    try stdout_writer.print("originator: 0x{x:0>32}\n", .{rec.originator_id});
    try stdout_writer.print("index: [<:{x:0>32}:>]\n", .{rec.index});
    try stdout_writer.print("long_count: {d}\n", .{rec.long_count});
    try stdout_writer.print("short_count: {d}\n", .{rec.short_count});
    try stdout_writer.print("payload: {s}\n", .{rec.payload});

    try stdout_writer.flush(); // Don't forget to flush!
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "append three records and print log" {
    var db = storm.Storm.init(1);
    defer db.deinit(std.testing.allocator);

    _ = try db.append(
        std.testing.allocator,
        "temperature=72.5",
    );

    _ = try db.append(
        std.testing.allocator,
        "humidity=44",
    );

    _ = try db.append(
        std.testing.allocator,
        "pressure=1013",
    );

    try std.testing.expectEqual(
        @as(usize, 3),
        db.records.items.len,
    );

    for (db.records.items) |rec| {
        std.debug.print(
            \\Record
            \\  originator: 0x{x:0>32}
            \\  index     : [<:{x:0>32}:>]
            \\  long_count: {d}
            \\  short_count: {d}
            \\  payload   : {s}
            \\
        ,
            .{
                rec.originator_id,
                rec.index,
                rec.long_count,
                rec.short_count,
                rec.payload,
            },
        );
    }

    // Verify counts advanced correctly.
    try std.testing.expectEqual(
        @as(u64, 1),
        db.records.items[0].long_count,
    );

    try std.testing.expectEqual(
        @as(u64, 2),
        db.records.items[1].long_count,
    );

    try std.testing.expectEqual(
        @as(u64, 3),
        db.records.items[2].long_count,
    );
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
