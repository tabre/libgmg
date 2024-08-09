const std = @import("std");
const posix = std.posix;

const enums = @import("enums.zig");
const messages = @import("messages.zig");

addr: std.net.Address,
port: u16,
poll_delay: u64,

var go: bool = true;
var polling_thread: std.Thread = undefined;
var sock: posix.socket_t = undefined;

var name: [12]u8 = undefined;
var state: enums.GrillState = enums.GrillState.from_int(0);
var temp: u16 = 0;
var setpoint: u16 = 0;
var probe_temp: u16 = 0;
var probe_setpoint: u16 = 0;
var raw: [36]u8 = undefined;

const Self = @This();

pub fn init(address: []const u8, prt: u16, poll_dly: u8, auto: bool) !Self {
    var new = Self {
        .addr = try std.net.Address.parseIp4(address, prt),
        .port = prt,
        .poll_delay = std.time.ns_per_s * @as(u64, poll_dly)
    };
    
    if (auto) {
        new.init_comm();
    }

    return new;
}

pub fn init_comm(self: Self) void {
    self.sock_init() catch {
        std.debug.print("Error initializing socket", .{});
    };

    self.grill_init() catch |err| {
        std.debug.print("{}", .{err});
    };

    self.start_polling() catch |err| {
        std.debug.print("{}", .{err});
    };
}

fn sock_init(self: Self) !void {
    sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.shutdown(sock, std.posix.ShutdownHow.both) catch |err| {
        std.debug.print("{!}\n", .{err});
    };
    
    try posix.connect(sock, &self.addr.any, self.addr.getOsSockLen());
}

fn send_msg(self: Self, msg: messages.GrillMessage) ![]u8 {
    _ = try posix.sendto(
        sock, msg.msg, 0, &self.addr.any, self.addr.getOsSockLen()
    );

    var buf: [36]u8 = undefined;
    var n_recvd: usize = 0;
    var n_bytes: u64 = 0;

    while (n_bytes < msg.response_size) {
        n_recvd = try posix.recvfrom(sock,  buf[n_bytes..], 0, null, null);
        if ((n_recvd == 1) and (buf[n_bytes] == 21)) break;
        n_bytes += n_recvd;
    }

    return &buf;
}

fn grill_init(self: Self) !void {
    const response = try self.send_msg(messages.MSG_INIT);
    @memcpy(name[0..12], response[2..14]);
}

fn poll(self: Self) !void {
    while (go) {
        parse_poll_data(try self.send_msg(messages.MSG_POLL));
        std.time.sleep(self.poll_delay);
    }
}

pub fn start_polling(self: Self) !void {
    go = true;
    polling_thread = try std.Thread.spawn(.{}, poll, .{self}); 
}

pub fn stop_polling(self: Self) void {
    go = false;
    _ = self.send_msg(messages.MSG_EOT) catch |err| {
        std.debug.print("Error sending EOT message: {!}", .{err});
    };
    polling_thread.join();
}

fn parse_poll_data(buf: []u8) void {
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

pub fn set_temp(self: Self, tmp: u16) !void {
    parse_poll_data(try self.send_msg(messages.GrillMessage.set_temp(
        tmp,
        enums.GrillSPRegister.MAIN
    )));
}

pub fn set_probe_temp(self: Self, tmp: u16) !void {
    parse_poll_data(try self.send_msg(messages.GrillMessage.set_temp(
        tmp,
        enums.GrillSPRegister.PROBE1
    )));
}

pub fn show(self: Self, show_raw: bool) void {
    std.debug.print("GMG - {s} @ {any}\n", .{name, self.addr});
    std.debug.print("State     : {s}\n", .{@tagName(state)});
    std.debug.print("Temp      : {}\n", .{temp});
    std.debug.print("Set       : {}\n", .{setpoint});
    std.debug.print("Probe Set : {}\n", .{probe_setpoint});
    if (show_raw) {
        std.debug.print("Raw       : {any}\n", .{raw});
    }
    std.debug.print("\n", .{});
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
