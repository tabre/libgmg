const std = @import("std");
const posix = std.posix;
const testing = std.testing;

const TestServer = @import("TestServer.zig");
const GMG = @import("GMG.zig");

const LOCAL = "127.0.0.1";
const PORT = 8080;

const DELAY = 1;
const DLY_SC = std.time.ns_per_s * @as(u64, DELAY);

const TestEnv = struct {
    serv: TestServer,
    gmg: GMG,

    const Self = @This();

    fn init() !Self {
       const new = Self {
           .serv = try TestServer.init(LOCAL, PORT, DELAY / 20, false, false),
           .gmg = try GMG.init(LOCAL, PORT, DELAY, false)
        };

       return new;
    }

    fn startup(self: Self) void {
       self.serv.init_comm();
       self.gmg.init_comm();
    }

    fn shutdown(self: Self) void {
        self.serv.stop_listen();
        self.gmg.stop_polling();
    }
};

var env: TestEnv = undefined;

test "init" { 
    env = try TestEnv.init();
    env.startup();

    std.time.sleep(DLY_SC);
    try testing.expectEqualStrings("DB02SUF0_1.1", env.gmg.get_name());
}

test "set_temp" {
    std.time.sleep(DLY_SC);

    // High limit
    try env.gmg.set_temp(999);
    std.time.sleep(DLY_SC);
    try testing.expectEqual(550, env.gmg.get_temp_setpoint()); 

    // In range
    try env.gmg.set_temp(420);
    std.time.sleep(DLY_SC);
    try testing.expectEqual(420, env.gmg.get_temp_setpoint());
    
    // Low limit
    try env.gmg.set_temp(69);
    std.time.sleep(DLY_SC);
    try testing.expectEqual(150, env.gmg.get_temp_setpoint());
}

test "set_probe" {
    std.time.sleep(DLY_SC);

    // High limit
    try env.gmg.set_probe_temp(420);
    std.time.sleep(DLY_SC);
    try testing.expectEqual(255, env.gmg.get_probe_setpoint()); 

    // In range
    try env.gmg.set_probe_temp(200);
    std.time.sleep(DLY_SC);
    try testing.expectEqual(200, env.gmg.get_probe_setpoint());
    
    // Low limit
    try env.gmg.set_probe_temp(69);
    std.time.sleep(DLY_SC);
    try testing.expectEqual(150, env.gmg.get_probe_setpoint());
}

test "shutdown" {
    env.shutdown();
}
