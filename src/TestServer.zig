const std = @import("std");

const Io = std.Io;
const Socket = Io.net.Socket;
const IpAddress = Io.net.IpAddress;
const IncomingMessage = Io.net.IncomingMessage;

io: Io,
addr: IpAddress,
port: u16,
listen_delay: u64,
debug: bool,
sock: Socket = undefined,

var go: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);
var listen_thread: std.Thread = undefined;
const default = [_]u8{ 85, 82, 78, 0, 81, 0, 150, 0, 1, 11, 20, 50, 25, 25, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 };

const Self = @This();

pub fn init(io: Io, address: []const u8, prt: u16, listen_dly: u8, auto: bool, dbg: bool) !Self {
    var new = Self {
        .io = io,
        .addr = try IpAddress.parseIp4(address, prt),
        .port = prt,
        .listen_delay = std.time.ns_per_s * @as(u64, listen_dly),
        .debug=dbg
    };

    if (auto) {
        new.init_comm();
    }

    return new;
}

pub fn init_comm(self: *Self) void {
    self.sock_init() catch {
        std.log.defaultLog(.err, .Testing, "Error initializing socket\n", .{});
    };
    
    self.start_listen() catch |err| {
        std.log.defaultLog(.err, .Testing, "{}", .{err});
    };
}

fn sock_init(self: *Self) !void {
    self.sock = try self.addr.bind(self.io, .{ .mode = .dgram });
    errdefer self.sock.close(self.io);

    if (self.debug) {
        std.log.defaultLog(.debug, .Testing, "TEST_SERVER: Socket connected.\n", .{});
    }
}

fn listen(self: Self) !void {
    var resp: [36]u8 = [_]u8{0} ** 36;
    @memcpy(&resp, &default);

    var buf: [6]u8 = [_]u8{0} ** 6;
    // SAFETY: inc_msg will be set before use
    var inc_msg: IncomingMessage = undefined;

    while(go.load(.acquire)) {
        inc_msg = self.sock.receive(self.io, &buf) catch break;
        if (self.debug) {
            std.log.defaultLog(.debug, .Testing, 
                "TEST_SERVER: {} bytes received: {s}\n", 
                .{inc_msg.data.len, buf}
            );
        }

        switch (inc_msg.data.len) {
            3 => {
                self.sock.send(self.io, &inc_msg.from, "UNDB02SUF0_1.1") catch break;
            },
            1 => {
                if (self.debug) {
                    std.log.defaultLog(.debug, .Testing, "TEST_SERVER: Received EOT signal.\n", .{});
                    self.sock.send(self.io, &inc_msg.from, "!") catch break;
                    break;
                }
            },
            else => switch (buf[1]) {
                75 => switch (buf[4]) {
                    49 => {
                        resp[30] = 1;
                        self.sock.send(self.io, &inc_msg.from, "OK") catch break;
                    },
                    52 => {
                        resp[30] = 0;
                        self.sock.send(self.io, &inc_msg.from, "OK") catch break;
                    },
                    else => {}
                },
                82 => {
                    self.sock.send(self.io, &inc_msg.from, &resp) catch break;
                },
                84 => { 
                    const i: u16 = try std.fmt.parseInt(u16, buf[2..5], 10);
                    const split: [2]u8 = @bitCast(i);
                    @memcpy(resp[6..8], &split); 
                    self.sock.send(self.io, &inc_msg.from, &resp) catch break;

                },
                70 => { 
                    const i: u16 = try std.fmt.parseInt(u16, buf[2..5], 10);
                    const split: [2]u8 = @bitCast(i);
                    @memcpy(resp[28..30], &split);
                    self.sock.send(self.io, &inc_msg.from, &resp) catch break;
                },
                else => {}
            }
        }
        try self.io.sleep(Io.Duration{ .nanoseconds = self.listen_delay }, .awake);
    } 
    if (self.debug) {
        std.log.defaultLog(.debug, .Testing, "TEST_SERVER: Shutting down.\n", .{});
    }
}

fn start_listen(self: Self) !void {
    go.store(true, .release);
    listen_thread = try std.Thread.spawn(.{}, listen, .{self});
}

pub fn stop_listen(self: Self) void {
    go.store(false, .release);
    listen_thread.join();
    self.sock.close(self.io);
}
