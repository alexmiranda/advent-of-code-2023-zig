pub const day01 = @import("day01/main.zig");
pub const day02 = @import("day02/main.zig");
pub const day03 = @import("day03/main.zig");
pub const day04 = @import("day04/main.zig");
pub const day05 = @import("day05/main.zig");
pub const day06 = @import("day06/main.zig");
pub const day07 = @import("day07/main.zig");
pub const day08 = @import("day08/main.zig");
pub const day09 = @import("day09/main.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
