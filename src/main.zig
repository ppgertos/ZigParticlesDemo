const std = @import("std");
const Config = @import("config.zig");
const Shape = Config.Shape;

pub const ray = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

const M = @This();

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
            .fps = 0,
        };
        for (0..numberOfRegions) |_| {
            context.agentsInRegions.appendAssumeCapacity(try std.ArrayList(u64).initCapacity(allocator, constants.regionEstimatedCapacity));
        }

        return context;
    }

    fn fill(context: *Context, config: *const Config, constants: *const Constants, randEngine: *std.Random) void {
        for (0..config.maxAgents) |i| {
            context.agentIds.appendAssumeCapacity(i);
            context.indexInRegion.appendAssumeCapacity(0);
            context.speeds.appendAssumeCapacity([_]f32{
                (randEngine.float(f32) - 0.5) * constants.screenHeightf,
                (randEngine.float(f32) - 0.5) * constants.screenHeightf,
            });

            context.positions.appendAssumeCapacity([_]f32{
                (randEngine.float(f32)) * constants.screenWidthf,
                (randEngine.float(f32)) * constants.screenHeightf,
            });
            const p = context.positions.items[i];
            const r = positionToRegion(p, config, constants);
            context.region.appendAssumeCapacity(r);
            context.agentsInRegions.items[r].appendAssumeCapacity(i);
            context.indexInRegion.items[i] = context.agentsInRegions.items[r].items.len - 1;
        }
        context.setTargets(constants, config, config.finalShape, randEngine);
    }

    pub fn setTargets(context: *Context, constants: *const Constants, config: *const Config, shape: Shape, randEngine: *std.Random) void {
        const xOffset = constants.screenWidthf / 2;
        const yOffset = constants.screenHeightf / 2;
        const scale = constants.screenHeightf * 0.45;
        for (0..config.maxAgents) |i| {
            switch (shape) {
                .Random => {
                    context.targets.appendAssumeCapacity([_]f32{
                        (randEngine.float(f32)) * constants.screenWidthf,
                        (randEngine.float(f32)) * constants.screenHeightf,
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
                        xOffset + scale * @cos(k * t) * @cos(t),
                        yOffset + scale * @cos(k * t) * @sin(t),
                    });
                },
                .Lissajous => {
                    const k: f32 = 7;
                    const j: f32 = 5;
                    const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / @as(f32, @floatFromInt(config.maxAgents));
                    context.targets.appendAssumeCapacity([_]f32{
                        xOffset + scale * @cos(k * t),
                        yOffset + scale * @sin(j * t),
                    });
                },
                .Circle => {
                    const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / @as(f32, @floatFromInt(config.maxAgents));
                    context.targets.appendAssumeCapacity([_]f32{
                        xOffset + scale * @cos(t),
                        yOffset + scale * @sin(t),
                    });
                },
            }
        }
    }
};

allocator: std.heap.GeneralPurposeAllocator(.{}),
running: bool,
config: Config,
constants: Constants,
context: Context = undefined,
xoshi: std.Random.Xoshiro256,
randEngine: std.Random,

pub fn main() !void {
    var m = try init("config.ini");
    defer m.deinit();

    try m.loop();
}

fn init(confpath: []const u8) !M {
    ray.SetTraceLogLevel(ray.LOG_ERROR);
    ray.InitWindow(0, 0, "Zig Particle Demo");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    
    const monitor = ray.GetCurrentMonitor();
    const screenWidth = ray.GetMonitorWidth(monitor);
    const screenHeight = ray.GetMonitorHeight(monitor);

    var m = M{
        .allocator = gpa,
        .running = true,
        .config = try Config.load(confpath, screenWidth, screenHeight, gpa.allocator()),
        .constants = undefined,
        .context = undefined,
        .xoshi = undefined,
        .randEngine = undefined,
    };
    errdefer m.deinit();
    m.xoshi = std.Random.DefaultPrng.init(m.config.randSeed);
    m.randEngine = m.xoshi.random();

    m.constants = try Constants.calculate(&m.config);
    m.context = try Context.init(m.allocator.allocator(), &m.config, &m.constants);
    m.context.fill(&m.config, &m.constants, &m.randEngine);

    ray.SetWindowSize(m.config.screenWidth, m.config.screenHeight);

    return m;
}

fn loop(m: *M) !void {
    while (m.running) {
        try m.simulate();
        try m.blit();
        try m.handleEvents();
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
        const nx = p[0] + s[0] / m.config.frictionFactor;
        const ny = p[1] + s[1] / m.config.frictionFactor;

        // bumping on edges
        if (nx <= m.config.epsilonAtZero or m.constants.screenWidthf <= nx) {
            s[0] = -s[0];
            p[0] += s[0] / m.config.frictionFactor;
        } else {
            p[0] = nx;
        }
        if (ny <= m.config.epsilonAtZero or m.constants.screenHeightf <= ny) {
            s[1] = -s[1];
            p[1] += s[1] / m.config.frictionFactor;
        } else {
            p[1] = ny;
        }

        // attracting agent toward target
        const t = m.context.targets.items[i];
        const tdiff = [2]f32{ t[0] - p[0], t[1] - p[1] };
        const tdist = tdiff[0] * tdiff[0] + tdiff[1] * tdiff[1];
        if (tdist > m.config.epsilonAtZero) {
            s[0] += tdiff[0] * (m.config.attractionFactor / tdist);
            s[1] += tdiff[1] * (m.config.attractionFactor / tdist);
        }

        // calculating determinant to find out direction toward the target
        const d = s[0] * (t[1] - p[1]) - s[1] * (t[0] - p[0]);

        //       0.5 deg 1 deg            5 deg
        // sin() 0.0087  0.0174524064373  0.0348994967025
        // cos() 0.9999  0.999847695156   0.999390827019

        // rotating speed vector, slightly toward target
        const rotationSin = 0.0174524064373;
        const rotationCos = 0.999847695156;
        var newS = s.*;
        if (d > 0) {
            newS = [_]f32{
                s[0] * rotationCos - s[1] * rotationSin,
                s[0] * rotationSin + s[1] * rotationCos,
            };
        } else if (d < 0) {
            newS = [_]f32{
                s[0] * rotationCos + s[1] * rotationSin,
                s[0] * (-rotationSin) + s[1] * rotationCos,
            };
        }
        s.* = newS;

        // handling transitions between regions
        const r = &m.context.region.items[i];
        const newR = positionToRegion(p.*, &m.config, &m.constants);
        if (r.* != newR) {
            const oldIndexInRegion = m.context.indexInRegion.items[i];

            if (m.context.agentsInRegions.items[r.*].getLast() == i) {
                _ = m.context.agentsInRegions.items[r.*].pop() orelse return;
            } else {
                const lastAgent = m.context.agentsInRegions.items[r.*].pop() orelse return error.AgentOutOfNowhere;
                m.context.indexInRegion.items[lastAgent] = oldIndexInRegion;
                m.context.agentsInRegions.items[r.*].items[oldIndexInRegion] = lastAgent;
            }
            m.context.indexInRegion.items[i] = m.context.agentsInRegions.items[newR].items.len;
            m.context.agentsInRegions.items[newR].appendAssumeCapacity(i);

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
        if (m.config.speedLimit * m.config.speedLimit < s[0] * s[0] + s[1] * s[1]) {
            const scale = m.config.speedLimit / @sqrt(s[0] * s[0] + s[1] * s[1]);
            s[0] *= scale;
            s[1] *= scale;
        }
    }
}

fn blit(m: *M) !void {
    ray.BeginDrawing();
    defer ray.EndDrawing();
    ray.ClearBackground(ray.BLACK);
    const here = struct {
        var buf: [15]u8 = [_]u8{0x0} ** 15;
    };

    if (m.config.showGrid == 1) {
        var x: f32 = 0;
        while (x < m.constants.screenWidthf) : (x += m.constants.regionWidth) {
            ray.DrawLineV(.{ .x = x, .y = 0 }, .{ .x = x, .y = m.constants.screenHeightf }, ray.DARKGRAY);
            const numAsString = try std.fmt.bufPrintZ(&here.buf, "{d}", .{x});
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
            const numAsString = try std.fmt.bufPrintZ(&here.buf, "{d}", .{y});
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
}

fn handleEvents(m: *M) !void {
    if (ray.WindowShouldClose()) {
        m.running = false;
    }
    switch (ray.GetKeyPressed()) {
        // Shapes
        ray.KEY_GRAVE => {
            m.context.targets.clearRetainingCapacity();
            m.context.setTargets(&m.constants, &m.config, Shape.Random, &m.randEngine);
        },
        ray.KEY_ONE => {
            m.context.targets.clearRetainingCapacity();
            m.context.setTargets(&m.constants, &m.config, Shape.Heart, &m.randEngine);
        },
        ray.KEY_TWO => {
            m.context.targets.clearRetainingCapacity();
            m.context.setTargets(&m.constants, &m.config, Shape.Flower, &m.randEngine);
        },
        ray.KEY_THREE => {
            m.context.targets.clearRetainingCapacity();
            m.context.setTargets(&m.constants, &m.config, Shape.Lissajous, &m.randEngine);
        },
        ray.KEY_FOUR => {
            m.context.targets.clearRetainingCapacity();
            m.context.setTargets(&m.constants, &m.config, Shape.Circle, &m.randEngine);
        },
        // config
        ray.KEY_F => {
            m.config.showFps = 1 - m.config.showFps;
        },
        ray.KEY_S => {
            m.config.showShape = 1 - m.config.showShape;
        },
        ray.KEY_G => {
            m.config.showGrid = 1 - m.config.showGrid;
        },
        else => {},
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
