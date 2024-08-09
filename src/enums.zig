const std = @import("std");

pub const GrillState = enum {
    OFF,
    WARMUP,
    ON,
    COOL,
    
    const Self = @This();

    pub fn from_int(i: u8) Self {
        return @enumFromInt(i);
    }
};

pub const GrillSPRegister = enum {
    MAIN,
    PROBE1,

    const Self = @This();

    pub fn to_u8(self: Self) u8 {
        switch (self) {
            Self.MAIN => return 84,
            Self.PROBE1 => return 70,
        }
    }
};
