const std = @import("std");
const posix = std.posix;

addr: std.net.Address,
port: u16,
listen_delay: u64,
debug: bool,

var go: bool = true;
var listen_thread: std.Thread = undefined;
var sock: posix.socket_t = undefined;
const default = [_]u8{ 85, 82, 78, 0, 81, 0, 150, 0, 1, 11, 20, 50, 25, 25, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 };

const Self = @This();

pub fn init(address: []const u8, prt: u16, listen_dly: u8, auto: bool, dbg: bool) !Self {
    var new = Self {
        .addr = try std.net.Address.parseIp4(address, prt),
        .port = prt,
        .listen_delay = std.time.ns_per_s * @as(u64, listen_dly),
        .debug=dbg
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
    
    self.start_listen() catch |err| {
        std.debug.print("{}", .{err});
    };
}

fn sock_init(self: Self) !void {
    sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.shutdown(sock, std.posix.ShutdownHow.both) catch |err| {
        std.debug.print("{!}\n", .{err});
    };

    try posix.bind(sock, &self.addr.any, self.addr.getOsSockLen());
    if (self.debug) {
        std.debug.print("TEST_SERVER: Socket connected.\n", .{});
    }
}

fn listen(self: Self) !void {
    var resp: [36]u8 = undefined;
    @memcpy(&resp, &default);
    
    var client_addr: posix.sockaddr = undefined;
    var addr_len: posix.socklen_t = @sizeOf(std.posix.sockaddr);

    var buf: [6]u8 = undefined;
    var n_bytes: u64 = 0;

    while(go) {
        n_bytes = try posix.recvfrom(
            sock, buf[0..], 0, &client_addr, &addr_len
        );
        
        if (self.debug) {
            std.debug.print(
                "TEST_SERVER: {} bytes received: {s}\n", 
                .{n_bytes, buf[0..n_bytes]}
            );
        }

        switch (n_bytes) {
            3 => {
                _ = try posix.sendto(sock, "UNDB02SUF0_1.1", 0, &client_addr, addr_len);
            },
            1 => {
                if (self.debug) {
                    std.debug.print("TEST_SERVER: Received EOT signal.\n", .{});
                    _ = try posix.sendto(sock, "!", 0, &client_addr, addr_len);
                    break;
                }
            },
            else => switch (buf[1]) {
                75 => switch (buf[4]) {
                    49 => {
                        resp[30] = 1;
                        _ = try posix.sendto(sock, "OK", 0, &client_addr, addr_len);
                    },
                    52 => {
                        resp[30] = 0;
                        _ = try posix.sendto(sock, "OK", 0, &client_addr, addr_len);
                    },
                    else => {}
                },
                82 => {
                    _ = try posix.sendto(sock, &resp, 0, &client_addr, addr_len); 
                },
                84 => { 
                    const i: u16 = try std.fmt.parseInt(u16, buf[2..5], 10);
                    const split: [2]u8 = @bitCast(i);
                    @memcpy(resp[6..8], &split); 
                    _ = try posix.sendto(sock, &resp, 0, &client_addr, addr_len);

                },
                70 => { 
                    const i: u16 = try std.fmt.parseInt(u16, buf[2..5], 10);
                    const split: [2]u8 = @bitCast(i);
                    @memcpy(resp[28..30], &split);
                    _ = try posix.sendto(sock, &resp, 0, &client_addr, addr_len);
                },
                else => {}
            }
        }
        std.time.sleep(self.listen_delay);
    } 
    if (self.debug) {
        std.debug.print("TEST_SERVER: Shutting down.\n", .{});
    }
}

fn start_listen(self: Self) !void {
    go = true;
    listen_thread = try std.Thread.spawn(.{}, listen, .{self});
}

pub fn stop_listen(self: Self) void {
    _ = self;
    go = false;
    listen_thread.join();
}
