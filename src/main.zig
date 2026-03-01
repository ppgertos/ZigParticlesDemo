const std = @import("std");

pub const ray = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

const M = @This();

const Shape = enum(u8) {
    Random,
    Heart,
};

const Constants = struct {
    collisionPenalty: f64 = 0.0001,
    distRequiredForCollision: f64 = 0.001 * 0.001,
    finalShape: Shape = .Heart,
    maxAgents: u64 = 10000,
    agentRadius: f64 = 0.001,
    randSeed: u64 = 0xDEADBEEF,
    regionsNumberX: u64 = 131,
    regionsNumberXf: f64 = 131,
    regionsNumberY: u64 = 70,
    regionsNumberYf: f64 = 70,
    regionEstimatedCapacity: u64 = 222,
    regionWidth: f64 = 0.1,
    regionHeight: f64 = 0.1,
    screenWidth: i32 = 960,
    screenHeight: i32 = 600,
    screenProportion: f64 = 960.0 / 600.0,
    showFps: u1 = 1,
    showGrid: u1 = 1,
    speedLimit: u1 = 1,
    speedFactor: f64 = 0.0004,

    pub fn format(
        self: *const Constants,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("Constants {{ maxAgents = {d}, regionWidth = {d}, regionHeight = {d}, regionEstimatedCapacity = {d}, screenWidth = {d}, screenHeight = {d} }}", .{ self.maxAgents, self.regionWidth, self.regionHeight, self.regionEstimatedCapacity, self.screenWidth, self.screenHeight });
    }
};

const Context = struct {
    agentIds: std.ArrayList(u64),
    positions: std.ArrayList([2]f64),
    speeds: std.ArrayList([2]f64),
    targets: std.ArrayList([2]f64),
    region: std.ArrayList(u64),
    indexInRegion: std.ArrayList(u64),
    agentsInRegions: std.ArrayList(std.ArrayList(u64)),
    vacatsInRegions: std.ArrayList(std.ArrayList(u64)),
    fps: i64,
};

allocator: std.heap.GeneralPurposeAllocator(.{}),
running: bool,
constants: Constants,
context: Context = undefined,

pub fn main() !void {
    var m = try init("config.ini");
    defer m.deinit();

    try m.loop();
}

fn init(confpath: []const u8) !M {
    var m = M{
        .allocator = std.heap.GeneralPurposeAllocator(.{}){},
        .running = true,
        .constants = try loadConstants(confpath),
        .context = undefined,
    };
    errdefer m.deinit();

    m.context = try makeContext(m.allocator.allocator(), &m.constants);

    fillContext(&m.context, &m.constants);

    ray.SetTraceLogLevel(ray.LOG_ERROR);
    ray.InitWindow(m.constants.screenWidth, m.constants.screenHeight, "Zig Particle Demo");

    return m;
}

fn loadConstants(filePath: []const u8) !Constants {
    var constants = Constants{};
    var file = try std.fs.cwd().openFile(filePath, .{ .mode = .read_only });
    defer file.close();
    var rbuf: [50]u8 = undefined;
    var fileReader = file.reader(&rbuf);
    while (fileReader.interface.takeDelimiter('\n')) |maybeLine| {
        const line = maybeLine orelse break;
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) {
            continue;
        }
        var iter = std.mem.splitScalar(u8, line, '=');

        const name = iter.next() orelse break;
        const value = iter.next() orelse break;

        if (std.mem.eql(u8, name, "collisionPenalty")) {
            constants.collisionPenalty = try std.fmt.parseFloat(f64, value);
        } else if (std.mem.eql(u8, name, "finalShape")) {
            constants.finalShape = std.meta.stringToEnum(Shape, value) orelse return error.InvalidEnum;
        } else if (std.mem.eql(u8, name, "maxAgents")) {
            constants.maxAgents = try std.fmt.parseInt(u64, value, 10);
        } else if (std.mem.eql(u8, name, "agentRadius")) {
            constants.agentRadius = try std.fmt.parseFloat(f64, value);
        } else if (std.mem.eql(u8, name, "regionsNumberX")) {
            constants.regionsNumberX = try std.fmt.parseInt(u64, value, 10);
        } else if (std.mem.eql(u8, name, "regionsNumberY")) {
            constants.regionsNumberY = try std.fmt.parseInt(u64, value, 10);
        } else if (std.mem.eql(u8, name, "showFps")) {
            constants.showFps = try std.fmt.parseInt(u1, value, 10);
        } else if (std.mem.eql(u8, name, "showGrid")) {
            constants.showGrid = try std.fmt.parseInt(u1, value, 10);
        } else if (std.mem.eql(u8, name, "speedLimit")) {
            constants.speedLimit = try std.fmt.parseInt(u1, value, 10);
        } else if (std.mem.eql(u8, name, "speedFactor")) {
            constants.speedFactor = try std.fmt.parseFloat(f64, value);
        } else if (std.mem.eql(u8, name, "randSeed")) {
            constants.randSeed = try std.fmt.parseInt(u64, value, 0);
        }
    } else |err| {
        return err;
    }
    constants.distRequiredForCollision = 4 * constants.agentRadius * constants.agentRadius;
    constants.screenProportion = @as(f64, @floatFromInt(constants.screenWidth)) / @as(f64, @floatFromInt(constants.screenHeight));
    constants.regionsNumberXf = @floatFromInt(constants.regionsNumberX);
    constants.regionsNumberYf = @floatFromInt(constants.regionsNumberY);
    constants.regionWidth = constants.screenProportion / @as(f64, @floatFromInt(constants.regionsNumberX));
    constants.regionHeight = 1.0 / @as(f64, @floatFromInt(constants.regionsNumberY));

    const criclesPackedInSquareFactor = 0.906899682118;
    const regionArea = constants.regionWidth * constants.regionHeight;
    const effectivelyUsedArea = regionArea * criclesPackedInSquareFactor;
    const agentArea = std.math.pow(f64, constants.agentRadius, 2) * std.math.pi;
    constants.regionEstimatedCapacity = @intFromFloat(effectivelyUsedArea / agentArea);

    std.log.info("constants: {f}", .{constants});
    return constants;
}

fn makeContext(allocator: std.mem.Allocator, constants: *const Constants) !Context {
    const numberOfRegions = constants.regionsNumberX * constants.regionsNumberY;

    var context = Context{
        .agentIds = try std.ArrayList(u64).initCapacity(allocator, constants.maxAgents),
        .positions = try std.ArrayList([2]f64).initCapacity(allocator, constants.maxAgents),
        .speeds = try std.ArrayList([2]f64).initCapacity(allocator, constants.maxAgents),
        .targets = try std.ArrayList([2]f64).initCapacity(allocator, constants.maxAgents),
        .region = try std.ArrayList(u64).initCapacity(allocator, constants.maxAgents),
        .indexInRegion = try std.ArrayList(u64).initCapacity(allocator, constants.maxAgents),
        .agentsInRegions = try std.ArrayList(std.ArrayList(u64)).initCapacity(allocator, numberOfRegions),
        .vacatsInRegions = try std.ArrayList(std.ArrayList(u64)).initCapacity(allocator, numberOfRegions),
        .fps = 0,
    };
    for (0..numberOfRegions) |_| {
        context.agentsInRegions.appendAssumeCapacity(try std.ArrayList(u64).initCapacity(allocator, constants.regionEstimatedCapacity));
        context.vacatsInRegions.appendAssumeCapacity(try std.ArrayList(u64).initCapacity(allocator, constants.regionEstimatedCapacity));
    }

    return context;
}

fn fillContext(context: *Context, constants: *const Constants) void {
    var randEngine = std.Random.DefaultPrng.init(constants.randSeed);
    for (0..constants.maxAgents) |i| {
        context.agentIds.appendAssumeCapacity(i);
        context.indexInRegion.appendAssumeCapacity(0);
        context.speeds.appendAssumeCapacity([_]f64{
            (randEngine.random().float(f64) - 0.5) * constants.screenProportion,
            (randEngine.random().float(f64) - 0.5),
        });
        switch (constants.finalShape) {
            .Random => {
                context.targets.appendAssumeCapacity([_]f64{
                    (randEngine.random().float(f64)) * constants.screenProportion,
                    (randEngine.random().float(f64)),
                });
            },
            .Heart => {
                const t = @as(f64, @floatFromInt(i)) * 2 * std.math.pi / @as(f64, @floatFromInt(constants.maxAgents));
                const st = @sin(t);
                context.targets.appendAssumeCapacity([_]f64{
                    (constants.screenProportion / 2) + 0.03 * 16 * st * st * st,
                    0.42 - 0.03 * (13 * @cos(t) - 5 * @cos(2 * t) - 2 * @cos(3 * t) - @cos(4 * t)),
                });
            },
            .Ganja => {
                context.targets.appendAssumeCapacity([_]f64{ 0.25, 0.25 });
            },
        }
        context.positions.appendAssumeCapacity([_]f64{
            (randEngine.random().float(f64)) * constants.screenProportion,
            (randEngine.random().float(f64)),
        });
        const p = context.positions.items[i];
        const r = positionToRegion(p, constants);
        context.region.appendAssumeCapacity(r);
        context.agentsInRegions.items[r].appendAssumeCapacity(i);
        context.indexInRegion.items[i] = context.agentsInRegions.items[r].items.len - 1;
    }
}

fn loop(m: *M) !void {
    var frameStart: i64 = 0;
    while (m.running) {
        try m.simulate();
        try m.blit();
        try m.handleEvents();
        if (m.constants.showFps == 1) {
            const frameEnd = std.time.milliTimestamp();
            const frameTime = (frameEnd - frameStart);
            if (frameTime == 0) {
                m.context.fps = 999;
            } else {
                m.context.fps = @divTrunc(std.time.ms_per_s, frameTime);
            }
            frameStart = frameEnd;
        }
    }
}

fn simulate(m: *M) !void {
    for (m.context.agentIds.items) |i| {
        if (i > m.constants.maxAgents) {
            continue;
        }

        var p = &m.context.positions.items[i];
        const s = &m.context.speeds.items[i];
        // moving agents
        const nx = p[0] + s[0] * m.constants.speedFactor;
        const ny = p[1] + s[1] * m.constants.speedFactor;

        // bumping on edges
        if (nx <= 0.0 or m.constants.screenProportion <= nx) {
            s[0] = -s[0];
            p[0] += s[0] * m.constants.speedFactor;
        } else {
            p[0] = nx;
        }
        if (ny <= 0.0 or 1.0 <= ny) {
            s[1] = -s[1];
            p[1] += s[1] * m.constants.speedFactor;
        } else {
            p[1] = ny;
        }

        // homing to target
        const t = m.context.targets.items[i];
        const d = s[0] * (t[1] - p[1]) - s[1] * (t[0] - p[0]);

        //       0.5 deg 1 deg            5 deg
        // sin() 0.0087  0.0174524064373  0.0348994967025
        // cos() 0.9999  0.999847695156   0.999390827019

        // rotating speed vector, slightly toward target
        const rots = 0.0174524064373;
        const rotc = 0.999847695156;
        if (d > 0) {
            const nsx = s[0] * rotc - s[1] * rots;
            s[1] = s[0] * rots + s[1] * rotc;
            s[0] = nsx;
        } else if (d < 0) {
            const nsx = s[0] * rotc + s[1] * rots;
            s[1] = s[0] * (-rots) + s[1] * rotc;
            s[0] = nsx;
        }

        // attracting agent toward target
        const tdiff = [2]f64{ t[0] - p[0], t[1] - p[1] };
        const tdist = tdiff[0] * tdiff[0] + tdiff[1] * tdiff[1];
        s[0] += tdiff[0] * (0.002 / tdist);
        s[1] += tdiff[1] * (0.002 / tdist);

        // handling transitions between regions
        const r = &m.context.region.items[i];
        const newR = positionToRegion(p.*, &m.constants);
        if (r.* != newR) {
            const oldIndexInRegion = m.context.indexInRegion.items[i];
            m.context.vacatsInRegions.items[r.*].appendAssumeCapacity(oldIndexInRegion);
            m.context.agentsInRegions.items[r.*].items[oldIndexInRegion] = m.constants.maxAgents + 1;

            const vacantIndexInRegion = m.context.vacatsInRegions.items[newR].pop();
            if (vacantIndexInRegion != null) {
                m.context.agentsInRegions.items[newR].items[vacantIndexInRegion.?] = i;
                m.context.indexInRegion.items[i] = vacantIndexInRegion.?;
            } else {
                const newIndexInRegion = m.context.agentsInRegions.items[newR].items.len;
                m.context.agentsInRegions.items[newR].appendAssumeCapacity(i);
                m.context.indexInRegion.items[i] = newIndexInRegion;
            }
            r.* = newR;
        }

        // detecting and handling collisions
        for (m.context.agentsInRegions.items[m.context.region.items[i]].items) |neighbor| {
            if (neighbor == i or neighbor > m.constants.maxAgents) {
                continue;
            }
            const np = m.context.positions.items[neighbor];
            const diff = [2]f64{ np[0] - p[0], np[1] - p[1] };
            const dist2 = diff[0] * diff[0] + diff[1] * diff[1];
            if (dist2 < m.constants.distRequiredForCollision) {
                s[0] = s[0] * m.constants.collisionPenalty - s[0];
                s[1] = s[1] * m.constants.collisionPenalty - s[1];
                break;
            }
        }

        // speed clamping
        if (m.constants.speedLimit == 1) {
            const maxV = 5;
            if (s[0] < -maxV) {
                s[0] = -maxV;
            } else if (maxV < s[0]) {
                s[0] = maxV;
            }
            if (s[1] < -maxV) {
                s[1] = -maxV;
            } else if (maxV < s[1]) {
                s[1] = maxV;
            }
        }
    }

}

fn blit(m: *M) !void {
    ray.BeginDrawing();
    defer ray.EndDrawing();
    ray.ClearBackground(ray.BLACK);
    var buf = [_]u8{0x0} ** 6;

    if (m.constants.showGrid == 1) {
        const stepx = @divFloor(m.constants.screenWidth, @as(i32, @intCast(m.constants.regionsNumberX)));
        var x: i32 = 0;
        while (x < m.constants.screenWidth) : (x += stepx) {
            ray.DrawLine(x, 0, x, m.constants.screenHeight, ray.DARKGRAY);
            const numAsString = try std.fmt.bufPrintZ(&buf, "{d}", .{x});
            ray.DrawText(@ptrCast(numAsString), x + 3, m.constants.screenHeight - 12, 10, ray.DARKGRAY);
        }
        const stepy = @divFloor(m.constants.screenHeight, @as(i32, @intCast(m.constants.regionsNumberY)));
        var y: i32 = 0;
        while (y < m.constants.screenHeight) : (y += stepy) {
            ray.DrawLine(0, y, m.constants.screenWidth, y, ray.DARKGRAY);
            const numAsString = try std.fmt.bufPrintZ(&buf, "{d}", .{y});
            ray.DrawText(@ptrCast(numAsString), m.constants.screenWidth - 20, y + 2, 10, ray.DARKGRAY);
        }
    }

    for (m.context.agentIds.items) |i| {
        if (i > m.constants.maxAgents) {
            continue;
        }
        const p = m.context.positions.items[i];

        const c = switch (@divFloor(m.context.region.items[i], 2) % 2) {
            0 => ray.SKYBLUE,
            else => ray.ORANGE,
        };

        const px: c_int = @intFromFloat(p[0] * @as(f64, @floatFromInt(m.constants.screenHeight)));
        const py: c_int = @intFromFloat(p[1] * @as(f64, @floatFromInt(m.constants.screenHeight)));
        ray.DrawPixel(px, py, c);
    }

    if (m.constants.showFps == 1) {
        ray.DrawText(@ptrCast(try std.fmt.bufPrintZ(&buf, "{d}", .{m.context.fps})), 10, 10, 10, ray.WHITE);
    }
}

fn handleEvents(m: *M) !void {
    if (ray.WindowShouldClose()) {
        m.running = false;
    }
}

fn positionToRegion(p: [2]f64, constants: *const Constants) u64 {
    errdefer std.log.err("position ({d}, {d})", .{ p[0], p[1] });
    var x: f64 = @divFloor(p[0], constants.regionWidth);
    if (x < 0) {
        x = 0;
    } else if (x >= constants.regionsNumberXf) {
        x = constants.regionsNumberXf - 1;
    }

    var y: f64 = @divFloor(p[1], constants.regionHeight);
    if (y < 0) {
        y = 0;
    } else if (y > constants.regionsNumberYf) {
        y = constants.regionsNumberYf - 1;
    }

    return @as(u64, @intFromFloat(x)) + @as(u64, @intFromFloat(y)) * constants.regionsNumberX;
}

fn deinit(m: *M) void {
    const alloc = m.allocator.allocator();
    for (m.context.agentsInRegions.items) |*regionAgents| {
        regionAgents.deinit(alloc);
    }
    m.context.agentsInRegions.deinit(alloc);
    for (m.context.vacatsInRegions.items) |*regionAgents| {
        regionAgents.deinit(alloc);
    }
    m.context.vacatsInRegions.deinit(alloc);
    m.context.positions.deinit(alloc);
    m.context.agentIds.deinit(alloc);
    m.context.region.deinit(alloc);
    m.context.indexInRegion.deinit(alloc);
    m.context.speeds.deinit(alloc);
    m.context.targets.deinit(alloc);

    const result = m.allocator.deinit();
    std.log.info("Alloc leak check: {s}", .{@tagName(result)});

    if (ray.GetWindowHandle() != null) {
        ray.CloseWindow();
    }
}
