pub const day01 = @import("day01/main.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
