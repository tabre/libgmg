pub const GrillState = enum {
    Off,
    Warmup,
    On,
    Cool,
    
    const Self = @This();

    pub fn from_int(i: u8) Self {
        return @enumFromInt(i);
    }
};

pub const GrillSPRegister = enum {
    Main,
    Probe1,

    const Self = @This();

    pub fn to_u8(self: Self) u8 {
        switch (self) {
            Self.Main => return 84,
            Self.Probe1 => return 70,
        }
    }
};
