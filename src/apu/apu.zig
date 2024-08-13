const std = @import("std");
const Cpu = @import("../cpu.zig").CPU;

const Self = @This();

/// A divider that counts up to a period, then resets.
/// Can be used to divide the frequency of a signal by a factor N.
/// In other words, we multiply the input signal's period by N,
/// where `N = <input period> / period `.
const Counter = struct {
    period: u16,
    current_count: u16 = 0,

    /// Ticks the divider once, then returns `true` if the period
    /// has elapsed, `false` otherwise.
    pub inline fn tick(self: *Counter) bool {
        self.current_count += 1;
        if (self.current_count >= self.period) {
            self.current_count = 0;
            return true;
        }

        return false;
    }
};

/// The $4001 and $4005 registers that set up the sweep unit for
/// the pulse channels – https://www.nesdev.org/wiki/APU_Sweep
const SweepRegister = packed struct {
    shift_count: u3 = 0,
    negate: bool = false,
    period: u3 = 0,
    is_enabled: bool = false,
    comptime {
        std.debug.assert(@bitSizeOf(SweepRegister) == 8);
    }
};

/// The $4010 register that sets the sample rate and loop.
const SampleRegister = packed struct {
    send_irq: bool = false,
    loop: bool = false,
    _unused: u2 = 0,
    rate: u4 = 0,
    comptime {
        std.debug.assert(@bitSizeOf(SampleRegister) == 8);
    }
};

/// Controls the volume, decay rate, and duty cycle of the pulse channel.
const PulseCtrlRegister = packed struct {
    /// Apparently, the volume and decay rate are the same?
    volume: u4 = 0,
    is_volume_constant: bool = false,
    /// States whether the envelope should loop the volume.
    /// Same as Length counter's halt flag.
    is_looping: bool = false,
    duty_cycle: u2 = 0,

    comptime {
        std.debug.assert(@bitSizeOf(PulseCtrlRegister) == 8);
    }
};

/// Each pulse channel in the APU has its own sweep unit.
/// The sweep unit is used to adjust the period of the pulse channel over time.
const Sweep = struct {
    /// Mapped to $4001 (for pulse channel 1) or $4005 (for pulse channel 2)
    config: SweepRegister = .{},
    /// Divider that clocks the sweep.
    /// Divider itself is clocked by APU frame counter.
    divider: Counter = .{ .period = 0 },
    /// Timer of the pulse unit that this sweep unit is attached to.
    timer: *Counter,

    is_pulse_1: bool = false,

    /// Update the period of the pulse channel's timer unit.
    pub fn tickByFrameCounter(self: *Sweep) void {
        if (!self.divider.tick()) return;
        if (!self.config.is_enabled) return;

        // compute the target period from the timers 11-bit raw period
        const current_period = self.timer.period;
        var delta: i32 = current_period >> self.config.shift_count;
        if (self.config.negate) {
            // TODO: handle different negate behavior for different pulse channels.
            delta = -delta;
            if (self.is_pulse_1) delta -= 1;
        }

        const out: u32 = @abs(current_period + delta);
        self.timer.period = @truncate(out);
    }

    /// Returns `true` if the output from this channel should 0 (muted).
    pub inline fn isMuted(self: *const Sweep) bool {
        return self.timer.period < 8 or self.timer.period > 0x7FF;
    }
};

/// The APU Envelope unit generates a volume level for the channel.
/// Clocked by the APU Frame counter (a.k.a ticked 4 or 5 times a frame).
const Envelope = struct {
    /// Divider clocked by frame counter,
    /// and the period is set by $4000 (or $4004) bits 0-3
    divider: Counter = .{ .period = 0 },
    /// 4-bit decay counter. Clocked by the divider.
    decay_counter: u8 = 0,
    /// If `true`, the decay counter loops when it reaches 0.
    /// Otherwise, the output volume stays at 0.
    is_looping: bool = false,
    /// If set, the volume is constant and sent directly
    /// to the DAC.
    is_volume_constant: bool = false,
    /// output volume of the envelope unit
    output_volume: u8 = 0,
    /// Volume set by bits 0-3 of $4000 (or $4004).
    volume: u8 = 0,
    /// The start flag.
    should_start: bool = false,

    pub inline fn reset(self: *Envelope, ctrl: PulseCtrlRegister) void {
        self.is_looping = ctrl.is_looping;
        self.is_volume_constant = ctrl.is_volume_constant;
        self.volume = ctrl.volume;
        self.should_start = true;
    }

    pub inline fn tickByFrameCounter(self: *Envelope) void {
        if (self.should_start) {
            self.should_start = false;
            self.decay_counter = 0b1111;
            self.divider.period = self.volume;
            return;
        }

        // If start flag is clear (meaning the envelope is already running),
        // We clock the divider as usual.
        if (!self.divider.tick()) return;

        if (self.decay_counter == 0) {
            if (self.is_looping) // if the loop flag is set, reload.
                self.decay_counter = 15;
        } else {
            self.decay_counter -= 1;
        }

        self.output_volume = if (self.is_volume_constant)
            self.volume
        else
            self.decay_counter;
    }
};

/// maps a 2-bit value to the bit-map representing the output
/// amplitudes of the duty-cycle.
const DutyCycleTable = [4][8]u8{
    .{ 0, 1, 0, 0, 0, 0, 0, 0 }, // 12.5%
    .{ 0, 1, 1, 0, 0, 0, 0, 0 }, // 25%
    .{ 0, 1, 1, 1, 1, 0, 0, 0 }, // 50%
    .{ 1, 0, 0, 1, 1, 1, 1, 1 }, // 75%
};

/// The sequencer for the pulse channel.
/// This loops over a series of values (the duty cycle).
const Sequencer = struct {
    /// A duty cycle is the % of time for which the pulse is ON in one period.
    /// Set by bits 6-7 of $4000 or $4004.
    /// This sequence of 8 1-bit values represents the duty period.
    /// For a 25% period, only one of the 8 bits is set.
    /// For a 50% period, 4 bits are set, and so on...
    duty_sequence: *const [8]u8 = &DutyCycleTable[0],
    /// Current step in the duty sequence.
    i: u8 = 0,
    /// The Sequencer is clocked by the Sweep unit's 11-bit timer.
    pub fn tickByTimer(self: *Sequencer) void {
        self.i += 1;
        if (self.i == 8) self.i = 0;
    }
};

/// Used by the waveform channels.
/// Counts down to a value, then resets.
/// The value is set by the memory mapped registers.
/// https://www.nesdev.org/wiki/APU_Length_Counter
const LengthCounter = struct {
    const Register = packed struct {
        timer: u3 = 0,
        length: u5 = 0,

        comptime {
            // verify the structure of the register
            std.debug.assert(@bitSizeOf(Register) == 8);
            const register = Register{ .timer = 0, .length = 0b11111 };
            std.debug.assert(@as(u8, @bitCast(register)) == 0b11111_000);
        }
    };

    /// `LengthCounter.Register.length` is used to look-up
    /// the actual note-length in this table.
    const LengthTable = [32]u8{
        10,  254, 20, 2,  40, 4,  80, 6,
        160, 8,   60, 10, 14, 12, 26, 14,
        12,  16,  24, 18, 48, 20, 96, 22,
        192, 24,  72, 26, 16, 28, 32, 30,
    };

    control: Register = .{},
    current_value: u8 = 0,
    is_halted: bool = false,

    pub fn tickByFrameCounter(self: *LengthCounter) void {
        if (self.is_halted) return;

        if (self.current_value == 0) {
            self.current_value = LengthTable[self.control.length] - 1;
            return;
        }

        self.current_value -= 1;
    }
};

/// The Pulse channel: https://www.nesdev.org/wiki/APU_Pulse
const PulseGenerator = struct {
    /// The APU envelope unit to control the volume for this pulse channel.
    envelope: Envelope = .{},
    /// Increments (or decrements) the period of the pulse over time.
    timer: *Counter,
    /// Updates the period of the timer.
    sweep: Sweep,
    /// Length counter determines the note length for the pulse channel
    length_counter: LengthCounter = .{},
    sequencer: Sequencer = .{},

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, is_pulse_one: bool) !PulseGenerator {
        const timer = try allocator.create(Counter);
        timer.* = .{ .period = 0 };
        return PulseGenerator{
            .timer = timer,
            .allocator = allocator,
            .sweep = .{ .timer = timer, .is_pulse_1 = is_pulse_one },
        };
    }

    pub fn deinit(self: *PulseGenerator) void {
        self.allocator.destroy(self.timer);
    }

    /// Write to register $4000 (for pulse 1) or $4004 (for pulse 2)
    pub inline fn writeControlReg(
        self: *PulseGenerator,
        value: PulseCtrlRegister,
    ) void {
        self.envelope.reset(value);
        self.sequencer.duty_sequence = &DutyCycleTable[value.duty_cycle];
        self.length_counter.is_halted = value.is_looping;
    }

    /// Write to register $4002 (for pulse 1) or $4006 (for pulse 2)
    /// This will set the low byte of the 11-bit timer to `value`.
    pub inline fn writeTimerLo(
        self: *PulseGenerator,
        value: u8,
    ) void {
        self.timer.period = (self.timer.period & 0xFF00) | @as(u16, value);
    }

    /// Write to register $4003 (for pulse 1) or $4007 (for pulse 2)
    /// This will set the high byte of the 11-bit timer to the low 3-bits of `value`,
    /// and the length counter's length to the high 5-bits of `value`.
    pub inline fn writeTimerHi(
        self: *PulseGenerator,
        value: u8,
    ) void {
        self.length_counter.control.length = @truncate(value >> 3);
        const value_low3: u16 = value & 0b0000_0111;
        self.timer.period = (self.timer.period & 0x00FF) | (value_low3 << 8);
    }

    /// compute the output of the pulse generator,
    /// and update the timer.
    pub fn tickByFrameCounter(self: *PulseGenerator) i16 {
        const out = self.sequencer.duty_sequence[self.sequencer.i];
        if (out == 0) return out; // sequencer is muted.

        const sequencer_muted = out == 0;
        const lc_muted = self.length_counter.current_value == 0;
        const sweep_muted = self.sweep.isMuted();

        // Are any of the sub-components muting the output?
        if (lc_muted or sweep_muted or sequencer_muted) return 0;
        // std.debug.print("pulse out: {}\n", .{self.envelope.output_volume});
        return self.envelope.output_volume;
    }

    pub inline fn tickByApuClock(self: *PulseGenerator) void {
        if (!self.timer.tick()) return;
        self.sequencer.tickByTimer();
    }
};

/// Mapped to $4017 in CPU address space.
const FrameCounterCtrl = packed struct {
    __unused: u6 = undefined,
    interrupt_inhibit: bool = false,
    is_5_step_sequence: bool = false,

    comptime {
        std.debug.assert(@bitSizeOf(FrameCounterCtrl) == 8);
    }
};

/// A divider that generates a clock pulse every quarter frame
/// (4 times per PPU frame).
/// The divider itself is clocked by the APU clock (== 0.5 * CPU clock-speed).
/// It drives several other units in the APU.
/// https://www.nesdev.org/wiki/APU_Frame_Counter
const FrameCounter = struct {
    pub const Mode = enum { four_step, five_step };

    divider: Counter = .{ .period = 240 },
    current_step: u8 = 0,

    inhibit_interrupt: bool = false,

    max_step: u8 = 4,
    mode: Mode = .four_step,
    pub inline fn setMode(self: *Self, mode: Mode) void {
        self.mode = mode;
        self.max_step = mode == if (.four_step) 4 else 5;
    }

    pub fn tickByApuClock(self: *FrameCounter) bool {
        if (!self.divider.tick()) return false;

        self.current_step += 1;
        if (self.current_step >= self.max_step) {
            self.current_step = 0;
        }

        return true;
    }
};

frame_counter: FrameCounter = .{},

// Is flipped every CPU cycle. 2 CPU cycles = 1 APU cycle.
is_apu_tick: bool = false,

pulse_1: PulseGenerator,
pulse_2: PulseGenerator,

cpu: *Cpu,

out_volume: i16 = 0,

pub fn init(allocator: std.mem.Allocator, cpu: *Cpu) !Self {
    return Self{
        .cpu = cpu,
        .pulse_1 = try PulseGenerator.init(allocator, true),
        .pulse_2 = try PulseGenerator.init(allocator, false),
    };
}

pub fn deinit(self: *Self) void {
    self.pulse_1.deinit();
    self.pulse_2.deinit();
}

/// Write to the frame-counter control register at $4017.
pub fn writeFrameCounter(self: *Self, value: u8) void {
    const fcctrl: FrameCounterCtrl = @bitCast(value);
    self.frame_counter.mode = if (fcctrl.is_5_step_sequence)
        FrameCounter.Mode.five_step
    else
        FrameCounter.Mode.four_step;
    self.frame_counter.inhibit_interrupt = fcctrl.interrupt_inhibit;
}

/// Clock the frame counter.
/// If it ticks, we also clock the APU units that are driven by the frame counter.
fn tickFrameCounter(self: *Self) void {
    const ticked = self.frame_counter.tickByApuClock();
    if (!ticked) return;

    if (self.frame_counter.mode == .four_step) {
        switch (self.frame_counter.current_step) {
            0 => {
                self.tickEnvelopes();
            },
            1 => {
                self.tickLengthCounters();
                self.tickSweepUnits();
            },
            // TODO: frame interrupt flag.
            2 => {},
            3 => {
                self.tickLengthCounters();
                self.tickSweepUnits();
                self.tickEnvelopes();
            },
            else => std.debug.panic("Invalid step count for 4 step mode", .{}),
        }
        return;
    }

    switch (self.frame_counter.current_step) {
        0 => {
            self.tickEnvelopes();
        },
        1 => {
            self.tickEnvelopes();
            self.tickLengthCounters();
            self.tickSweepUnits();
        },
        2 => {
            self.tickEnvelopes();
        },
        3 => {},
        4 => {
            self.tickEnvelopes();
            self.tickLengthCounters();
            self.tickSweepUnits();
        },
        else => std.debug.panic("Invalid step count for 4 step mode", .{}),
    }
}

fn tickLengthCounters(self: *Self) void {
    self.pulse_1.length_counter.tickByFrameCounter();
    self.pulse_2.length_counter.tickByFrameCounter();
}

fn tickSweepUnits(self: *Self) void {
    self.pulse_1.sweep.tickByFrameCounter();
    self.pulse_2.sweep.tickByFrameCounter();
}

fn tickEnvelopes(self: *Self) void {
    self.pulse_1.envelope.tickByFrameCounter();
    self.pulse_2.envelope.tickByFrameCounter();
}

pub fn tickByCpuClock(self: *Self) void {
    if (self.is_apu_tick) {
        self.pulse_1.tickByApuClock();
        self.pulse_2.tickByApuClock();
        // The frame counter is clocked every APU cycle.
        // If the FC itself generates a quarter frame clock,
        // we tick the APU units that are driven by the frame counter.
        self.tickFrameCounter();
        const pulse1: f32 = @floatFromInt(self.pulse_1.tickByFrameCounter());
        const pulse2: f32 = @floatFromInt(self.pulse_2.tickByFrameCounter());
        self.out_volume = mixVolume(pulse1, pulse2);
    }

    self.is_apu_tick = !self.is_apu_tick;
}

/// TODO: finish and document this function.
fn mixVolume(pulse1: f32, pulse2: f32) i16 {
    var pulse_out = (pulse1 + pulse2);
    if (pulse_out == 0) return 0;
    pulse_out *= 0.00752;

    // TODO: change this when ohen other channels are emulated.
    const tnd_out: f32 = 0;
    const mixer_out: f32 = pulse_out + tnd_out; // between 0.0 to 1.0

    // scale to 16-bit
    const amplitude = (mixer_out - 0.5) * 0x2fff;
    return @intFromFloat(amplitude);
}
