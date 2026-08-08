const std = @import("std");

const posix = std.posix;
const Io = std.Io;
const Duration = Io.Duration;
const Socket = Io.net.Socket;
const IpAddress = Io.net.IpAddress;
const IncomingMessage = Io.net.IncomingMessage;

const messages = @import("messages.zig");
const GrillMessage = messages.GrillMessage;
const DiscoveredGrill = @import("discover.zig").DiscoveredGrill;
const GrillState = @import("enums.zig").GrillState;

io: Io,
addr: IpAddress,
poll_freq: u64,
recv_timeout: u32,
sock: Socket,

var go: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);
var polling_thread: ?std.Thread = null;

var name: [12]u8 = [_]u8{0} ** 12;
var serial: []const u8 = &[_]u8{0} ** 11;
var state: GrillState = GrillState.from_int(0);
var temp: u16 = 0;
var setpoint: u16 = 0;
var probe_temp: u16 = 0;
var probe_setpoint: u16 = 0;
var raw: [36]u8 = [_]u8{0} ** 36;

const Self = @This();

pub fn init(
    io: Io,
    ser: ?[]const u8,
    addr: IpAddress,
    poll_freq: u8,
    recv_timeout: u8,
    auto: bool
) !Self {
    var new = Self{
        .io = io,
        .addr = addr,
        .poll_freq = std.time.ns_per_s * @as(u64, poll_freq),
        .recv_timeout = std.time.ms_per_s * @as(u32, recv_timeout),
        // SAFETY: sock will be set before use
        .sock = undefined,
    };

    serial = if (ser) |s| s else "";

    if (auto) {
        new.init_comm();
    }

    return new;
}

pub fn from_discovered(
    io: Io,
    dg: DiscoveredGrill,
    poll_freq: u8,
    recv_timeout: u8,
    auto: bool
) !Self {
    return init(io, &dg.serial, dg.addr, poll_freq, recv_timeout, auto);
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

    if (self.recv_timeout > 0) {
        const tv: std.os.linux.timeval = .{
            .sec = @intCast(self.recv_timeout / 1000),
            .usec = @intCast((self.recv_timeout % 1000) * 1000)
        };

        _ = std.os.linux.setsockopt(
            self.sock.handle,
            posix.SOL.SOCKET,
            posix.SO.RCVTIMEO,
            std.mem.asBytes(&tv),
            @sizeOf(std.os.linux.timeval)
        );
    }
}

fn send_msg(self: *Self, msg: GrillMessage) ![36]u8 {
    try self.sock.send(self.io, &self.addr, msg.msg);

    var buf: [36]u8 = undefined;
    var storage: std.Io.Threaded.PosixAddress = undefined;
    var from_len: posix.socklen_t = @sizeOf(std.Io.Threaded.PosixAddress);

    const rc = std.os.linux.recvfrom(
        self.sock.handle,
        @ptrCast(&buf),
        buf.len,
        0,
        @ptrCast(&storage.any),
        &from_len,
    );

    const signed_rc: isize = @bitCast(rc);
    if (signed_rc < 0) {
        if (signed_rc == -@as(isize, @intFromEnum(std.os.linux.E.AGAIN)))
            return error.Timeout;
        return error.UnexpectedError;
    }

    var result: [36]u8 = [_]u8{0} ** 36;
    @memcpy(result[0..rc], buf[0..rc]);

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
        self.io.sleep(Duration{ .nanoseconds = self.poll_freq }, .awake) catch break;
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
    state = GrillState.from_int(raw[30]);
}

pub fn start(self: Self) void {
    self.send_msg(messages.MSG_START);
}

pub fn stop(self: Self) void {
    self.send_msg(messages.MSG_STOP);
}

pub fn set_temp(self: *Self, tmp: u16) !void {
    var data = try self.send_msg(GrillMessage.set_temp(tmp, .Main));
    parse_poll_data(&data);
}

pub fn set_probe_temp(self: *Self, tmp: u16) !void {
    var data = try self.send_msg(GrillMessage.set_temp(tmp, .Probe1));
    parse_poll_data(&data);
}

// Getters
pub fn get_serial(self: Self) []u8 {
    _ = self;
    return &serial;
}

pub fn get_name(self: Self) []u8 {
    _ = self;
    return &name;
}

pub fn get_state(self: Self) GrillState {
    _ = self;
    return &state;
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
