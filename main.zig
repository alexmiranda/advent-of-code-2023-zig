pub const day01 = @import("day01/main.zig");
pub const day02 = @import("day02/main.zig");
pub const day03 = @import("day03/main.zig");
pub const day04 = @import("day04/main.zig");
pub const day05 = @import("day05/main.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
