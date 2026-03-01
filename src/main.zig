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
    Flower,
};

const Config = struct {
    agentRadius: f32 = 0.001,
    attractionFactor: f32 = 100,
    collisionPenalty: f32 = 0.0001,
    epsilonAtZero: f32 = 1e-6,
    finalShape: Shape = .Heart,
    maxAgents: u64 = 10000,
    randSeed: u64 = 0xDEADBEEF,
    regionsNumberX: u64 = 131,
    regionsNumberY: u64 = 70,
    screenHeight: i32 = 600,
    screenWidth: i32 = 960,
    showFps: u1 = 1,
    showGrid: u1 = 1,
    showShape: u1 = 1,
    speedFactor: f32 = 0.0004,
    speedLimit: f32 = 1,

    pub fn load(filePath: []const u8) !Config {
        var config = Config{};
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

            if (std.mem.eql(u8, name, "agentRadius")) {
                config.agentRadius = try std.fmt.parseFloat(f32, value);
            } else if (std.mem.eql(u8, name, "attractionFactor")) {
                config.attractionFactor = try std.fmt.parseFloat(f32, value);
            } else if (std.mem.eql(u8, name, "collisionPenalty")) {
                config.collisionPenalty = try std.fmt.parseFloat(f32, value);
            } else if (std.mem.eql(u8, name, "epsilonAtZero")) {
                config.epsilonAtZero = try std.fmt.parseFloat(f32, value);
            } else if (std.mem.eql(u8, name, "finalShape")) {
                config.finalShape = std.meta.stringToEnum(Shape, value) orelse return error.InvalidEnum;
            } else if (std.mem.eql(u8, name, "maxAgents")) {
                config.maxAgents = try std.fmt.parseInt(u64, value, 10);
            } else if (std.mem.eql(u8, name, "regionsNumberX")) {
                config.regionsNumberX = try std.fmt.parseInt(u64, value, 10);
            } else if (std.mem.eql(u8, name, "regionsNumberY")) {
                config.regionsNumberY = try std.fmt.parseInt(u64, value, 10);
            } else if (std.mem.eql(u8, name, "showFps")) {
                config.showFps = try std.fmt.parseInt(u1, value, 10);
            } else if (std.mem.eql(u8, name, "showGrid")) {
                config.showGrid = try std.fmt.parseInt(u1, value, 10);
            } else if (std.mem.eql(u8, name, "showShape")) {
                config.showShape = try std.fmt.parseInt(u1, value, 10);
            } else if (std.mem.eql(u8, name, "screenHeight")) {
                config.screenHeight = try std.fmt.parseInt(i32, value, 10);
            } else if (std.mem.eql(u8, name, "screenWidth")) {
                config.screenWidth = try std.fmt.parseInt(i32, value, 10);
            } else if (std.mem.eql(u8, name, "speedLimit")) {
                config.speedLimit = try std.fmt.parseFloat(f32, value);
            } else if (std.mem.eql(u8, name, "speedFactor")) {
                config.speedFactor = try std.fmt.parseFloat(f32, value);
            } else if (std.mem.eql(u8, name, "randSeed")) {
                config.randSeed = try std.fmt.parseInt(u64, value, 0);
            }
        } else |err| {
            return err;
        }
        return config;
    }
};

const Constants = struct {
    distRequiredForCollision: f32 = 0.001 * 0.001,
    regionEstimatedCapacity: u64 = 222,
    regionHeight: f32 = 0.1,
    regionWidth: f32 = 0.1,
    regionsNumberXf: f32 = 131,
    regionsNumberYf: f32 = 70,
    screenHeightf: f32 = 600,
    screenWidthf: f32 = 960,
    screenProportion: f32 = 960.0 / 600.0,

    fn calculate(config: *const Config) !Constants {
        var constants = Constants{};

        constants.distRequiredForCollision = 4 * config.agentRadius * config.agentRadius;
        constants.screenHeightf = @floatFromInt(config.screenHeight);
        constants.screenWidthf = @floatFromInt(config.screenWidth);
        constants.screenProportion = constants.screenWidthf / constants.screenHeightf;
        constants.regionsNumberXf = @floatFromInt(config.regionsNumberX);
        constants.regionsNumberYf = @floatFromInt(config.regionsNumberY);
        constants.regionWidth = constants.screenWidthf / constants.regionsNumberXf;
        constants.regionHeight = constants.screenHeightf / constants.regionsNumberYf;

        const circlesPackedInSquareFactor = 1; // 0.906899682118;
        const regionArea = constants.regionWidth * constants.regionHeight;
        const effectivelyUsedArea = regionArea * circlesPackedInSquareFactor;
        const agentArea = std.math.pow(f32, config.agentRadius, 2) * std.math.pi;
        constants.regionEstimatedCapacity = @intFromFloat(effectivelyUsedArea / agentArea);

        std.log.info("Constants {{ \n" ++
            "distRequiredForCollision = {d},\n" ++
            "regionEstimatedCapacity = {d},\n" ++
            "regionHeight = {d},\n" ++
            "regionWidth = {d},\n" ++
            "screenProportion = {d},\n" ++
            "}}", .{
            constants.distRequiredForCollision,
            constants.regionEstimatedCapacity,
            constants.regionHeight,
            constants.regionWidth,
            constants.screenProportion,
        });

        return constants;
    }
};

const Context = struct {
    agentIds: std.ArrayList(u64),
    positions: std.ArrayList([2]f32),
    speeds: std.ArrayList([2]f32),
    targets: std.ArrayList([2]f32),
    region: std.ArrayList(u64),
    indexInRegion: std.ArrayList(u64),
    agentsInRegions: std.ArrayList(std.ArrayList(u64)),
    vacatsInRegions: std.ArrayList(std.ArrayList(u64)),
    fps: i64,

    fn init(allocator: std.mem.Allocator, config: *const Config, constants: *const Constants) !Context {
        const numberOfRegions = config.regionsNumberX * config.regionsNumberY;

        var context = Context{
            .agentIds = try std.ArrayList(u64).initCapacity(allocator, config.maxAgents),
            .positions = try std.ArrayList([2]f32).initCapacity(allocator, config.maxAgents),
            .speeds = try std.ArrayList([2]f32).initCapacity(allocator, config.maxAgents),
            .targets = try std.ArrayList([2]f32).initCapacity(allocator, config.maxAgents),
            .region = try std.ArrayList(u64).initCapacity(allocator, config.maxAgents),
            .indexInRegion = try std.ArrayList(u64).initCapacity(allocator, config.maxAgents),
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

    fn fill(context: *Context, config: *const Config, constants: *const Constants) void {
        var randEngine = std.Random.DefaultPrng.init(config.randSeed);
        for (0..config.maxAgents) |i| {
            context.agentIds.appendAssumeCapacity(i);
            context.indexInRegion.appendAssumeCapacity(0);
            context.speeds.appendAssumeCapacity([_]f32{
                (randEngine.random().float(f32) - 0.5) * constants.screenHeightf,
                (randEngine.random().float(f32) - 0.5) * constants.screenHeightf,
            });
            switch (config.finalShape) {
                .Random => {
                    context.targets.appendAssumeCapacity([_]f32{
                        (randEngine.random().float(f32)) * constants.screenWidthf,
                        (randEngine.random().float(f32)) * constants.screenHeightf,
                    });
                },
                .Heart => {
                    const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / @as(f32, @floatFromInt(config.maxAgents));
                    const st = @sin(t);
                    context.targets.appendAssumeCapacity([_]f32{
                        (constants.screenWidthf / 2) + constants.screenHeightf * 0.03 * 16 * st * st * st,
                        constants.screenHeightf * 0.42 - constants.screenHeightf * 0.03 * (13 * @cos(t) - 5 * @cos(2 * t) - 2 * @cos(3 * t) - @cos(4 * t)),
                    });
                },
                .Flower => {
                    const k: f32 = 7.0 / 5.0;
                    const t = @as(f32, @floatFromInt(i)) * (3.5716 * std.math.pi * k) / (@as(f32, @floatFromInt(config.maxAgents)));
                    context.targets.appendAssumeCapacity([_]f32{
                        constants.screenWidthf / 2 + constants.screenHeightf / 2 * @cos(k * t) * @cos(t),
                        constants.screenHeightf / 2 + constants.screenHeightf / 2 * @cos(k * t) * @sin(t),
                    });
                },
            }
            context.positions.appendAssumeCapacity([_]f32{
                (randEngine.random().float(f32)) * constants.screenWidthf,
                (randEngine.random().float(f32)) * constants.screenHeightf,
            });
            const p = context.positions.items[i];
            const r = positionToRegion(p, config, constants);
            context.region.appendAssumeCapacity(r);
            context.agentsInRegions.items[r].appendAssumeCapacity(i);
            context.indexInRegion.items[i] = context.agentsInRegions.items[r].items.len - 1;
        }
    }
};

allocator: std.heap.GeneralPurposeAllocator(.{}),
running: bool,
config: Config,
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
        .config = try Config.load(confpath),
        .constants = undefined,
        .context = undefined,
    };
    errdefer m.deinit();
    m.constants = try Constants.calculate(&m.config);
    m.context = try Context.init(m.allocator.allocator(), &m.config, &m.constants);
    m.context.fill(&m.config, &m.constants);

    ray.SetTraceLogLevel(ray.LOG_ERROR);
    ray.InitWindow(m.config.screenWidth, m.config.screenHeight, "Zig Particle Demo");

    return m;
}

fn loop(m: *M) !void {
    //    var frameStart: i64 = 0;
    while (m.running) {
        try m.simulate();
        try m.blit();
        try m.handleEvents();
        //        if (m.constants.showFps == 1) {
        //            const frameEnd = std.time.milliTimestamp();
        //            const frameTime = (frameEnd - frameStart);
        //            if (frameTime == 0) {
        //                m.context.fps = 999;
        //            } else {
        //                m.context.fps = @divTrunc(std.time.ms_per_s, frameTime);
        //            }
        //            frameStart = frameEnd;
        //        }
    }
}

fn simulate(m: *M) !void {
    for (m.context.agentIds.items) |i| {
        if (i > m.config.maxAgents) {
            continue;
        }

        var p = &m.context.positions.items[i];
        const s = &m.context.speeds.items[i];
        // moving agents
        const nx = p[0] + s[0] * m.config.speedFactor;
        const ny = p[1] + s[1] * m.config.speedFactor;

        // bumping on edges
        if (nx <= 0.0 or m.constants.screenWidthf <= nx) {
            s[0] = -s[0];
            p[0] += s[0] * m.config.speedFactor;
        } else {
            p[0] = nx;
        }
        if (ny <= 0.0 or m.constants.screenHeightf <= ny) {
            s[1] = -s[1];
            p[1] += s[1] * m.config.speedFactor;
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
        const tdiff = [2]f32{ t[0] - p[0], t[1] - p[1] };
        const tdist = tdiff[0] * tdiff[0] + tdiff[1] * tdiff[1];
        if (tdist > m.config.epsilonAtZero) {
            s[0] += tdiff[0] * (m.config.attractionFactor / tdist);
            s[1] += tdiff[1] * (m.config.attractionFactor / tdist);
        }

        // handling transitions between regions
        const r = &m.context.region.items[i];
        const newR = positionToRegion(p.*, &m.config, &m.constants);
        if (r.* != newR) {
            const oldIndexInRegion = m.context.indexInRegion.items[i];
            m.context.vacatsInRegions.items[r.*].appendAssumeCapacity(oldIndexInRegion);
            //           m.context.agentsInRegions.items[r.*].items[oldIndexInRegion] = m.config.maxAgents + 1;

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
            if (neighbor == i or neighbor > m.config.maxAgents) {
                continue;
            }
            const np = m.context.positions.items[neighbor];
            const diff = [2]f32{ np[0] - p[0], np[1] - p[1] };
            const dist2 = diff[0] * diff[0] + diff[1] * diff[1];
            if (dist2 < m.constants.distRequiredForCollision) {
                s[0] = -s[0] * (1.0 - m.config.collisionPenalty);
                s[1] = -s[1] * (1.0 - m.config.collisionPenalty);
                break;
            }
        }

        // speed clamping
        if (m.config.speedLimit != 0.0) {
            const maxV = m.config.speedLimit;
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
    var buf = [_]u8{0x0} ** 15;

    if (m.config.showGrid == 1) {
        var x: f32 = 0;
        while (x < m.constants.screenWidthf) : (x += m.constants.regionWidth) {
            ray.DrawLineV(.{ .x = x, .y = 0 }, .{ .x = x, .y = m.constants.screenHeightf }, ray.DARKGRAY);
            const numAsString = try std.fmt.bufPrintZ(&buf, "{d}", .{x});
            ray.DrawTextEx(
                ray.GetFontDefault(),
                @ptrCast(numAsString),
                .{ .x = x + 3, .y = m.constants.screenHeightf - 12 },
                10,
                0.5,
                ray.DARKGRAY,
            );
        }
        var y: f32 = 0;
        while (y < m.constants.screenHeightf) : (y += m.constants.regionHeight) {
            ray.DrawLineV(.{ .x = 0, .y = y }, .{ .x = m.constants.screenWidthf, .y = y }, ray.DARKGRAY);
            const numAsString = try std.fmt.bufPrintZ(&buf, "{d}", .{y});
            ray.DrawTextEx(
                ray.GetFontDefault(),
                @ptrCast(numAsString),
                .{ .x = m.constants.screenWidthf - 20, .y = y + 2 },
                10,
                0.5,
                ray.DARKGRAY,
            );
        }
    }

    for (m.context.agentIds.items) |i| {
        if (i > m.config.maxAgents) {
            continue;
        }
        const p = m.context.positions.items[i];

        //const c = switch (@divFloor(m.context.region.items[i], 2) % 2) {
        //    0 => ray.SKYBLUE,
        //    else => ray.ORANGE,
        //};
        const c = switch (i % 4) {
            0 => ray.SKYBLUE,
            1 => ray.PINK,
            2 => ray.LIME,
            else => ray.ORANGE,
        };

        ray.DrawPixelV(.{ .x = p[0], .y = p[1] }, c);
    }

    if (m.config.showShape == 1) {
        ray.DrawLineStrip(@as([*c]ray.struct_Vector2, @ptrCast(m.context.targets.items)), @intCast(m.config.maxAgents), ray.RED);
    }

    if (m.config.showFps == 1) {
        ray.DrawFPS(10, 10);
    }

    //    if (m.constants.showFps == 1) {
    //        ray.DrawText(@ptrCast(try std.fmt.bufPrintZ(&buf, "{d}", .{m.context.fps})), 10, 10, 10, ray.WHITE);
    //    }
}

fn handleEvents(m: *M) !void {
    if (ray.WindowShouldClose()) {
        m.running = false;
    }
}

fn positionToRegion(p: [2]f32, config: *const Config, constants: *const Constants) u64 {
    var x: f32 = @divFloor(p[0], constants.regionWidth);
    if (x < 0) {
        x = 0;
    } else if (x >= constants.regionsNumberXf) {
        x = constants.regionsNumberXf - 1;
    }

    var y: f32 = @divFloor(p[1], constants.regionHeight);
    if (y < 0) {
        y = 0;
    } else if (y >= constants.regionsNumberYf) {
        y = constants.regionsNumberYf - 1;
    }

    return @as(u64, @intFromFloat(x)) + @as(u64, @intFromFloat(y)) * config.regionsNumberX;
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
