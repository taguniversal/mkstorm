const std = @import("std");
const mkrand = @import("mkrand");
const record = @import("record.zig");

pub const Storm = struct {
    originator_id: record.Id,
    state: record.Psi,
    long_count: u64 = 0,
    records: std.ArrayList(record.Record) = .empty,

    pub fn init(originator_id: record.Id) Storm {
        return .{
            .originator_id = originator_id,
            .state = mkrand.seedUnit,
            .long_count = 0,
            .records = .empty,
        };
    }

    pub fn deinit(self: *Storm, allocator: std.mem.Allocator) void {
        self.records.deinit(allocator);
    }

    pub fn nextIndex(self: *Storm) record.Psi {
        self.state = mkrand.next(self.state);
        self.long_count += 1;
        return self.state;
    }

    pub fn ingest(
        self: *Storm,
        psi_text: []const u8,
        long_count: u64,
        short_count: u32,
        payload: []const u8,
    ) record.Record {
        _ = psi_text;

        return .{
            .originator_id = self.originator_id,
            .psi = self.state,
            .long_count = long_count,
            .short_count = @intCast(short_count),
            .payload = payload,
        };
    }

    pub fn append(
        self: *Storm,
        allocator: std.mem.Allocator,
        payload: []const u8,
    ) !record.Record {
        const rec = self.ingest(payload);
        try self.records.append(allocator, rec);
        return rec;
    }
};
