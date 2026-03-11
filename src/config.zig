const std = @import("std");

const Config = @This();

pub const Shape = enum(u8) {
    Random,
    Heart,
    Flower,
    Lissajous,
    Circle,
};

agentRadius: f32 = 0.4,
attractionFactor: f32 = 100,
collisionPenalty: f32 = 0.0001,
epsilonAtZero: f32 = 1e-6,
finalShape: Shape = .Heart,
frictionFactor: f32 = 125,
maxAgents: u64 = 10000,
randSeed: u64 = 0xDEADBEEF,
regionsNumberX: u64 = 131,
regionsNumberY: u64 = 70,
screenHeight: i32 = 600,
screenWidth: i32 = 960,
showFps: u1 = 0,
showGrid: u1 = 0,
showShape: u1 = 0,
speedLimit: f32 = 200,

fn buildFieldsMeta(self: *Config, alloc: std.mem.Allocator) !std.StringArrayHashMap(FieldInfo) {
    var result = std.StringArrayHashMap(FieldInfo).init(alloc);
    const numberOfFields = @typeInfo(Config).@"struct".fields.len;
    try result.ensureTotalCapacity(numberOfFields);
    try result.put("agentRadius", .{ .f32 = &self.agentRadius });
    try result.put("attractionFactor", .{ .f32 = &self.attractionFactor });
    try result.put("collisionPenalty", .{ .f32 = &self.collisionPenalty });
    try result.put("epsilonAtZero", .{ .f32 = &self.epsilonAtZero });
    try result.put("finalShape", .{ .Shape = &self.finalShape });
    try result.put("frictionFactor", .{ .f32 = &self.frictionFactor });
    try result.put("maxAgents", .{ .u64 = &self.maxAgents });
    try result.put("randSeed", .{ .u64_auto = &self.randSeed });
    try result.put("regionsNumberX", .{ .u64 = &self.regionsNumberX });
    try result.put("regionsNumberY", .{ .u64 = &self.regionsNumberY });
    try result.put("screenHeight", .{ .i32 = &self.screenHeight });
    try result.put("screenWidth", .{ .i32 = &self.screenWidth });
    try result.put("showFps", .{ .u1 = &self.showFps });
    try result.put("showGrid", .{ .u1 = &self.showGrid });
    try result.put("showShape", .{ .u1 = &self.showShape });
    try result.put("speedLimit", .{ .f32 = &self.speedLimit });
    if (result.keys().len != numberOfFields) return error.MetaDoesNotMatchConfigFields;
    return result;
}

pub fn load(filePath: []const u8, detectedScreenWidth: i32, detectedScreenHeight: i32, alloc: std.mem.Allocator) !Config {
    var config = Config{};
    var meta = try config.buildFieldsMeta(alloc);
    defer meta.deinit();

    config.screenWidth = detectedScreenWidth;
    config.screenHeight = detectedScreenHeight;

    var file = try std.fs.cwd().openFile(filePath, .{ .mode = .read_only });
    defer file.close();
    var rbuf: [50]u8 = undefined;
    var fileReader = file.reader(&rbuf);
    while (fileReader.interface.takeDelimiter('\n')) |maybeLine| {
        const line = maybeLine orelse break;
        const trimmedLine = std.mem.trim(u8, line, " ");
        if (trimmedLine.len == 0 or trimmedLine[0] == '#' or trimmedLine[0] == ';') {
            continue;
        }
        var iter = std.mem.splitScalar(u8, trimmedLine, '=');
        const name = std.mem.trim(u8, iter.next() orelse break, " ");
        const value = std.mem.trim(u8, iter.next() orelse break, " ");

        if (meta.get(name)) |f| {
            try convertField(f, value);
        }
    } else |err| {
        return err;
    }
    return config;
}

const FieldInfo = union(enum) {
    Shape: *Shape,
    f32: *f32,
    i32: *i32,
    u1: *u1,
    u64: *u64,
    u64_auto: *u64,
};

fn convertField(field: FieldInfo, buf: []const u8) !void {
    switch (field) {
        .Shape => |ptr| {
            ptr.* = std.meta.stringToEnum(Shape, buf) orelse return error.InvalidEnum;
        },
        .f32 => |ptr| {
            ptr.* = try std.fmt.parseFloat(f32, buf);
        },
        .i32 => |ptr| {
            ptr.* = try std.fmt.parseInt(i32, buf, 10);
        },
        .u1 => |ptr| {
            ptr.* = try std.fmt.parseInt(u1, buf, 10);
        },
        .u64 => |ptr| {
            ptr.* = try std.fmt.parseInt(u64, buf, 10);
        },
        .u64_auto => |ptr| {
            ptr.* = try std.fmt.parseInt(u64, buf, 0);
        },
    }
}
