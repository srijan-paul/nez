const std = @import("std");

const Self = @This();

/// The $4010 register that sets the sample rate and loop.
const SampleRegister = packed struct {
    send_irq: bool = false,
    loop: bool = false,
    _unused: u2 = 0,
    rate: u4 = 0,
};

sample: SampleRegister = .{},
sample_rate: u32 = 0, // register $4010
sample_length: u8 = 0,
sample_address: u16 = 0
