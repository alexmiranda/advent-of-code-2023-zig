pub const day01 = @import("day01/main.zig");
pub const day02 = @import("day02/main.zig");
pub const day03 = @import("day03/main.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
