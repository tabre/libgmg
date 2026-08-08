const std = @import("std");
const testing = std.testing;

const Io = std.Io;
const IpAddress = Io.net.IpAddress;
const Duration = Io.Duration;

const TestServer = @import("TestServer.zig");
const GMG = @import("GMG.zig");
const discover = @import("discover.zig").discover;

const LOCAL = "127.0.0.1";
const PORT = 8080;

const FREQ = 1 * std.time.ns_per_s;

const TEST_DELAY = 50 * std.time.ns_per_ms;

const DEBUG = false;

const TestEnv = struct {
    io: Io,
    serv: TestServer,
    gmg: GMG,

    const Self = @This();

    fn init(io: std.Io) !Self {
        const addr = try IpAddress.parseIp4(LOCAL, PORT);
        const new = Self{
            .io = io,
            .serv = try TestServer.init(
                io, addr, FREQ / std.time.ns_per_s / 20, false, DEBUG
            ),
            .gmg = try GMG.init(
                io, "GMG69000420", addr, FREQ / std.time.ns_per_s, 2, false
            )
        };

        return new;
    }

    fn startup(self: *Self) void {
        self.serv.init_comm();
        self.gmg.init_comm();
    }

    fn shutdown(self: *Self) void {
        self.serv.stop_listen();
        self.gmg.stop_polling();
    }
};

test "discover" {
    var env = try TestEnv.init(testing.io);
    env.startup();

    const grills = try discover(env.io, std.testing.allocator, LOCAL, PORT, 2000);
    defer std.testing.allocator.free(grills);

    try testing.expectEqual(grills.len, 1);
    try testing.expectEqualStrings("GMG69000420", &grills[0].serial);

    env.shutdown();
}

test "init" {
    var env = try TestEnv.init(testing.io);
    env.startup();

    try testing.expectEqualStrings("DB02SUF0_1.1", env.gmg.get_name());

    env.shutdown();
}

test "set_temp" {
    var env = try TestEnv.init(testing.io);
    env.startup();

    // High limit
    try env.gmg.set_temp(999);
    try testing.io.sleep(Duration{ .nanoseconds = TEST_DELAY }, .awake);
    try testing.expectEqual(550, env.gmg.get_temp_setpoint());

    // In range
    try env.gmg.set_temp(420);
    try testing.io.sleep(Duration{ .nanoseconds = TEST_DELAY }, .awake);
    try testing.expectEqual(420, env.gmg.get_temp_setpoint());

    // Low limit
    try env.gmg.set_temp(69);
    try testing.io.sleep(Duration{ .nanoseconds = TEST_DELAY }, .awake);
    try testing.expectEqual(150, env.gmg.get_temp_setpoint());

    env.shutdown();
}

test "set_probe" {
    var env = try TestEnv.init(testing.io);
    env.startup();

    // High limit
    try env.gmg.set_probe_temp(420);
    try testing.io.sleep(Duration{ .nanoseconds = TEST_DELAY }, .awake);
    try testing.expectEqual(255, env.gmg.get_probe_setpoint());

    // In range
    try env.gmg.set_probe_temp(200);
    try testing.io.sleep(Duration{ .nanoseconds = TEST_DELAY }, .awake);
    try testing.expectEqual(200, env.gmg.get_probe_setpoint());

    // Low limit
    try env.gmg.set_probe_temp(69);
    try testing.io.sleep(Duration{ .nanoseconds = TEST_DELAY }, .awake);
    try testing.expectEqual(150, env.gmg.get_probe_setpoint());

    env.shutdown();
}
