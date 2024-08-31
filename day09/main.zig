const std = @import("std");
const print = std.debug.print;
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Part = enum {
    part_1,
    part_2,
};

fn Solver(comptime T: type, comptime max_items_per_step: usize) type {
    const StepsIterator = struct {
        allocator: std.mem.Allocator,
        lineIterator: std.mem.TokenIterator(u8, .scalar),

        fn next(self: *@This()) !?[]T {
            if (self.lineIterator.next()) |line| {
                const size = std.mem.count(u8, line, " ") + 1;
                const step = try self.allocator.alloc(T, size);

                // parse all the numbers in the next step
                var it = std.mem.splitScalar(u8, line, ' ');
                var slide: usize = 0;
                while (it.next()) |s| : (slide += 1) {
                    step[slide] = try std.fmt.parseInt(T, s, 10);
                }
                return step;
            }
            return null;
        }
    };

    return struct {
        fn solve(s: []const u8, comptime part: Part) !T {
            // by knowing the maximum number of items per line, we can calculate the amount of bytes that we need
            // by calculating the triangular number and multiplying it by the number of bytes for each item
            const max_capacity = @sizeOf(T) / @sizeOf(u8) * (max_items_per_step * (max_items_per_step + 1) / 2);
            var buf: [max_capacity]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buf);
            var allocator = fba.allocator();

            var it = StepsIterator{
                .allocator = allocator,
                .lineIterator = std.mem.tokenizeScalar(u8, s, '\n'),
            };

            var sum: T = 0;
            while (try it.next()) |step| {
                defer fba.reset(); // using reset is faster than freeing
                sum += predict(allocator, 0, step, part);
            }

            return sum;
        }

        fn predict(allocator: std.mem.Allocator, acc: T, step: []T, comptime part: Part) T {
            if (step.len == 1 or std.mem.allEqual(T, step, 0)) {
                return acc;
            }

            // safe because we always pass down a fixed buffer allocator with sufficient memory
            const next_step = allocator.alloc(T, step.len - 1) catch unreachable;

            // no need to free here because we reset the fba on each iteration
            // using defer prevents zig from correctly compiling this function with tail call optimisation
            // defer allocator.free(next_step);

            var slide: usize = 0;
            for (step[0 .. step.len - 1], step[1..]) |a, b| {
                next_step[slide] = if (part == .part_1) b - a else a - b;
                slide += 1;
            }

            // force the compiler to tail call
            const acc_next = if (part == .part_1) step[step.len - 1] + acc else step[0] + acc;
            return @call(.always_tail, predict, .{ allocator, acc_next, next_step, part });
        }
    };
}

test "example - part 1" {
    const ExampleSolver = Solver(u8, 6);
    const solution = try ExampleSolver.solve(example, .part_1);
    try std.testing.expectEqual(@as(u8, 114), solution);
}

test "input - part 1" {
    const InputSolver = Solver(i32, 21);
    const solution = try InputSolver.solve(input, .part_1);
    try std.testing.expectEqual(@as(i32, 1696140818), solution);
}

test "example - part 2" {
    const ExampleSolver = Solver(i8, 6);
    const solution = try ExampleSolver.solve(example, .part_2);
    try std.testing.expectEqual(@as(i8, 2), solution);
}

test "input - part 2" {
    const InputSolver = Solver(i32, 21);
    const solution = try InputSolver.solve(input, .part_2);
    try std.testing.expectEqual(@as(i32, 1152), solution);
}
