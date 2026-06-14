const mkrand = @import("mkrand");

pub const Id = u128;
pub const Psi = u128;

pub const Record = struct {
    originator_id: Id,
    psi: Psi,
    long_count: u64,
    short_count: u16,
    payload: []const u8,
};
