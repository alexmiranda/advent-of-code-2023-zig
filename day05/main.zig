const std = @import("std");
const example = @embedFile("example.txt");
const input = @embedFile("input.txt");

const Almanac = struct {
    seed: u32,
    soil: u32,
    fertiliser: u32,
    water: u32,
    light: u32,
    temperature: u32,
    humidity: u32,
    location: u32,
};

const ConversionRule = struct {
    dst_start: u32,
    src_start: u32,
    rng_length: u32,

    fn inRange(self: *@This(), src: u32) std.math.Order {
        if (self.src_start <= src) {
            if (src - self.src_start <= self.rng_length) {
                return .eq;
            }
            return .lt;
        }
        return .gt;
    }
};

fn lowestLocationNumber(allocator: std.mem.Allocator, s: []const u8) !u32 {
    var sections = std.mem.splitSequence(u8, s, "\n\n");
    var seeds = try parseSeeds(allocator, sections.next().?);
    defer allocator.free(seeds);

    var seedToSoilMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(seedToSoilMap);

    var soilToFertiliserMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(soilToFertiliserMap);

    var fertiliserToWaterMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(fertiliserToWaterMap);

    var waterToLightMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(waterToLightMap);

    var lightToTemperatureMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(lightToTemperatureMap);

    var temperatureToHumidityMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(temperatureToHumidityMap);

    // std.debug.print("{s}\n", .{sections.next().?});
    var humidityToLocationMap = try parseMap(allocator, sections.next().?);
    defer allocator.free(humidityToLocationMap);

    var lowestLocation: u32 = std.math.maxInt(u32);
    for (seeds) |*seed| {
        seed.soil = solveVar(seedToSoilMap, seed.seed);
        seed.fertiliser = solveVar(soilToFertiliserMap, seed.soil);
        seed.water = solveVar(fertiliserToWaterMap, seed.fertiliser);
        seed.light = solveVar(waterToLightMap, seed.water);
        seed.temperature = solveVar(lightToTemperatureMap, seed.light);
        seed.humidity = solveVar(temperatureToHumidityMap, seed.temperature);
        seed.location = solveVar(humidityToLocationMap, seed.humidity);
        lowestLocation = @min(lowestLocation, seed.location);
    }

    return lowestLocation;
}

fn parseSeeds(allocator: std.mem.Allocator, s: []const u8) ![]Almanac {
    const size = std.mem.count(u8, s, " ");
    var array = try allocator.alloc(Almanac, size);
    errdefer allocator.free(array);

    const sep_index = std.mem.indexOfScalar(u8, s, ':').?;
    var slide: usize = 0;
    var it = std.mem.tokenizeScalar(u8, s[sep_index + 2 ..], ' ');
    while (it.next()) |seed_as_str| : (slide += 1) {
        const seed = std.fmt.parseInt(u32, seed_as_str, 10) catch unreachable;
        array[slide] = .{
            .seed = seed,
            .soil = seed,
            .fertiliser = seed,
            .water = seed,
            .light = seed,
            .temperature = seed,
            .humidity = seed,
            .location = seed,
        };
    }
    return array;
}

fn parseMap(allocator: std.mem.Allocator, s: []const u8) ![]ConversionRule {
    const size = std.mem.count(u8, s, "\n");
    var map = try allocator.alloc(ConversionRule, size);
    errdefer allocator.free(map);

    var slide: usize = 0;
    var it = std.mem.splitScalar(u8, std.mem.trimRight(u8, s, "\n"), '\n');
    const header = it.next();
    _ = header;

    while (it.next()) |line| : (slide += 1) {
        var values = std.mem.tokenizeScalar(u8, line, ' ');
        const dst_start = std.fmt.parseInt(u32, values.next().?, 10) catch unreachable;
        const src_start = std.fmt.parseInt(u32, values.next().?, 10) catch unreachable;
        const rng_length = std.fmt.parseInt(u32, values.next().?, 10) catch unreachable;
        map[slide] = .{ .dst_start = dst_start, .src_start = src_start, .rng_length = rng_length };
    }

    // sort the map to make search more efficient
    std.sort.block(ConversionRule, map, {}, cmpBySrcStartAndRngLength);

    return map;
}

fn cmpBySrcStartAndRngLength(ctx: void, lhs: ConversionRule, rhs: ConversionRule) bool {
    _ = ctx;
    if (lhs.src_start < rhs.src_start) {
        return true;
    } else if (lhs.src_start == rhs.src_start) {
        // the bigger the range, the earlier it will appear in the map
        return lhs.rng_length > rhs.rng_length;
    }
    return false;
}

fn solveVar(rules: []ConversionRule, src: u32) u32 {
    const S = struct {
        fn orderByInRange(ctx: void, v: u32, rule: ConversionRule) std.math.Order {
            _ = ctx;
            if (v >= rule.src_start) {
                if (v - rule.src_start <= rule.rng_length) {
                    return .eq;
                }
                return .gt;
            }
            return .lt;
        }
    };

    const index = std.sort.binarySearch(ConversionRule, src, rules, {}, S.orderByInRange);
    if (index) |i| {
        return rules[i].dst_start + (src - rules[i].src_start);
    }

    return src;
}

test "example - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, example);
    try std.testing.expectEqual(@as(u32, 35), lowest_location);
}

test "input - part 1" {
    const lowest_location = try lowestLocationNumber(std.testing.allocator, input);
    try std.testing.expectEqual(@as(u32, 403695602), lowest_location);
}
