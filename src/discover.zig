const std = @import("std");

const Io = std.Io;
const IpAddress = Io.net.IpAddress;
const posix = std.posix;

pub const DiscoveredGrill = struct {
    serial: [11]u8,
    addr: IpAddress,
};

pub fn discover(
    io: Io,
    allocator: std.mem.Allocator,
    broadcast_addr: []const u8,
    port: u16,
    timeout_ms: u32,
) ![]DiscoveredGrill {
    const src: IpAddress = .{ .ip4 = .unspecified(0) };
    var sock = try src.bind(io, .{ .mode = .dgram, .allow_broadcast = true });
    defer sock.close(io);

    {
        const tv: std.os.linux.timeval = .{
            .sec = @intCast(@divTrunc(timeout_ms, 1000)),
            .usec = @intCast(@mod(timeout_ms, 1000) * 1000),
        };
        _ = std.os.linux.setsockopt(
            sock.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.RCVTIMEO,
            std.mem.asBytes(&tv),
            @sizeOf(std.os.linux.timeval),
        );
    }

    const target = try IpAddress.parseIp4(broadcast_addr, port);
    try sock.send(io, &target, "UL!");

    var list: std.ArrayList(DiscoveredGrill) = .empty;
    errdefer list.deinit(allocator);

    while (true) {
        var buf: [11]u8 = undefined;
        var storage: std.Io.Threaded.PosixAddress = undefined;
        var from_len: posix.socklen_t = @sizeOf(std.Io.Threaded.PosixAddress);

        const rc = std.os.linux.recvfrom(
            sock.handle,
            @ptrCast(&buf),
            buf.len,
            0,
            @ptrCast(&storage.any),
            &from_len,
        );

        const signed_rc: isize = @bitCast(rc);
        if (signed_rc < 0) {
            if (signed_rc == -@as(isize, @intFromEnum(std.os.linux.E.AGAIN))) break;
            return error.UnexpectedError;
        }

        if (rc == 11) {
            try list.append(allocator, .{
                .serial = buf,
                .addr = std.Io.Threaded.addressFromPosix(&storage),
            });
        }
    }

    return list.toOwnedSlice(allocator);
}
