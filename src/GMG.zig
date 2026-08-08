const std = @import("std");

const Io = std.Io;
const Duration = Io.Duration;
const Socket = Io.net.Socket;
const IpAddress = Io.net.IpAddress;
const IncomingMessage = Io.net.IncomingMessage;

const enums = @import("enums.zig");
const messages = @import("messages.zig");
const DiscoveredGrill = @import("discover.zig").DiscoveredGrill;

io: Io,
addr: IpAddress,
port: u16,
poll_delay: u64,
sock: Socket,

var go: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);
var polling_thread: ?std.Thread = null;

var name: [12]u8 = [_]u8{0} ** 12;
var state: enums.GrillState = enums.GrillState.from_int(0);
var temp: u16 = 0;
var setpoint: u16 = 0;
var probe_temp: u16 = 0;
var probe_setpoint: u16 = 0;
var raw: [36]u8 = [_]u8{0} ** 36;

const Self = @This();

pub fn init(io: Io, address: []const u8, prt: u16, poll_dly: u8, auto: bool) !Self {
    var new = Self {
        .io = io,
        .addr = try IpAddress.parseIp4(address, prt),
        .port = prt,
        .poll_delay = std.time.ns_per_s * @as(u64, poll_dly),
        // SAFETY: sock will be set before use
        .sock = undefined
    };
    
    if (auto) {
        new.init_comm();
    }

    return new;
}

pub fn from_discovered(io: Io, dg: DiscoveredGrill, poll_dly: u8, auto: bool) !Self {
    return init(io, dg.addr, dg.port, poll_dly, auto);
}

pub fn init_comm(self: *Self) void {
    self.sock_init() catch {
        std.log.defaultLog(.err, .GMG, "Error initializing socket", .{});
    };

    self.grill_init() catch |err| {
        std.log.defaultLog(.err, .GMG, "{}", .{err});
    };

    self.start_polling() catch |err| {
        std.log.defaultLog(.err, .GMG, "{}", .{err});
    };
}

fn sock_init(self: *Self) !void {
    const src: IpAddress = .{ .ip4 = .unspecified(0) };
    self.sock = try src.bind(self.io, .{ .mode = .dgram });
    errdefer self.sock.close(self.io);
}

fn send_msg(self: *Self, msg: messages.GrillMessage) ![36]u8 {
    try self.sock.send(self.io, &self.addr, msg.msg);

    var buf: [36]u8 = [_]u8{0} ** 36;
    const inc_msg: IncomingMessage = try self.sock.receive(self.io, &buf);
    
    var result: [36]u8 = [_]u8{0} ** 36;
    @memcpy(result[0..inc_msg.data.len], inc_msg.data);

    return result;
}

fn grill_init(self: *Self) !void {
    const response = try self.send_msg(messages.MSG_INIT);
    @memcpy(name[0..12], response[2..14]);
}

fn poll(self: *Self) !void {
    while (go.load(.acquire)) {
        const data = self.send_msg(messages.MSG_POLL) catch break;
        parse_poll_data(&data);
        self.io.sleep(Duration{ .nanoseconds = self.poll_delay}, .awake) catch break;
    }
}

pub fn start_polling(self: *Self) !void {
    go.store(true, .release);
    polling_thread = try std.Thread.spawn(.{}, poll, .{self}); 
}

pub fn stop_polling(self: Self) void {
    go.store(false, .release);
    if (polling_thread) |t| t.join();
    self.sock.close(self.io);
}

fn parse_poll_data(buf: *const [36]u8) void {
    @memcpy(raw[0..36], buf);
    temp = @bitCast(raw[2..4].*);
    setpoint = @bitCast(raw[6..8].*);
    probe_temp = @bitCast(raw[4..6].*);
    probe_setpoint = @bitCast(raw[28..30].*);
    state = enums.GrillState.from_int(raw[30]);
}

pub fn start(self: Self) void {
    self.send_msg(messages.MSG_START);
}

pub fn stop(self: Self) void {
    self.send_msg(messages.MSG_STOP);
}

pub fn set_temp(self: *Self, tmp: u16) !void {
    var data = try self.send_msg(messages.GrillMessage.set_temp(
        tmp,
        .Main
    ));
    parse_poll_data(&data);
}

pub fn set_probe_temp(self: *Self, tmp: u16) !void {
    var data = try self.send_msg(messages.GrillMessage.set_temp(
        tmp,
        .Probe1
    ));
    parse_poll_data(&data);
}

// Getters
pub fn get_name(self: Self) []u8 {
    _ = self;
    return &name;
}

pub fn get_temp(self: Self) u16 {
    _ = self;
    return temp;
}

pub fn get_probe_temp(self: Self) u16 {
    _ = self;
    return probe_temp;
}

pub fn get_temp_setpoint(self: Self) u16 {
    _ = self;
    return setpoint;
}

pub fn get_probe_setpoint(self: Self) u16 {
    _ = self;
    return probe_setpoint;
}
