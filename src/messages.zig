const std = @import("std"); 
const enums = @import("enums.zig");

pub const GrillMessage = struct {
    msg: []const u8,
    response_size: u8,

    const Self = @This();
    
    pub inline fn set_temp(set: u16, register: enums.GrillSPRegister) Self { 
        var msg = [6]u8{ 85, 84, 48, 48, 48, 33 };
        var sp:u16 = undefined;
       
        switch (register) {
            enums.GrillSPRegister.MAIN => {
                sp = if (set < 150) 150 else if (set > 550) 550 else set;
            },
            enums.GrillSPRegister.PROBE1 => {
                sp = if (set < 150) 150 else if (set > 255) 255 else set; 
            }
        }

        msg[1] = register.to_u8();
        msg[2] = @truncate((sp / 100) + 48);
        msg[3] = @truncate(((sp % 100) / 10) + 48);
        msg[4] = @truncate(((sp % 100) % 10) + 48);

        return GrillMessage{
            .msg=&msg,
            .response_size=36
        };
    }
};

pub const MSG_INIT  = GrillMessage{.msg="UN!",    .response_size=14};
pub const MSG_POLL  = GrillMessage{.msg="UR001!", .response_size=36};
pub const MSG_START = GrillMessage{.msg="UK001!", .response_size=2};
pub const MSG_STOP  = GrillMessage{.msg="UK004!", .response_size=2};
pub const MSG_EOT = GrillMessage{.msg="!", .response_size=0};
