const std = @import("std");
const Cpu = @import("../cpu.zig").CPU;

const Self = @This();

/// A divider that counts up to a period, then resets.
/// Can be used to divide the frequency of a signal by a factor N.
/// In other words, we multiply the input signal's period by N,
/// where `N = <input period> / desired_period`.
const Counter = struct {
    desired_period: u16,
    current_count: u16 = 0,

    /// Ticks the divider once, then returns `true` if the period
    /// has elapsed, `false` otherwise.
    pub inline fn tick(self: *Counter) bool {
        self.current_count += 1;
        if (self.current_count >= self.desired_period) {
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
    divider: Counter = .{ .desired_period = 0 },
    /// Current input to the sweep unit. Updated every tick.
    current_period: u16 = 0,
    /// Resulting output period from the sweep unit. Updated every tick.
    target_period: u16 = 0,

    pub fn tickByFrameCounter(self: *Sweep, in_period: u16) void {
        if (!self.divider.tick()) return;
        if (!self.config.is_enabled) return;

        self.current_period = in_period;

        // compute the target period
        var delta: i32 = in_period >> self.config.shift_count;
        if (self.config.negate) {
            // TODO: handle different negation behavior for different pulse channels.
            delta *= -1;
        }

        const out: u32 = @abs(in_period + delta);
        self.target_period = @truncate(out);
    }

    /// Returns `true` if the output from this channel should 0 (muted).
    pub inline fn isMuted(self: *const Sweep) bool {
        return self.current_period < 8 or self.target_period > 0x7FF;
    }
};

/// The APU Envelope unit generates a volume level for the channel.
/// Clocked by the APU Frame counter (a.k.a ticked 4 or 5 times a frame).
const Envelope = struct {
    /// Divider clocked by frame counter,
    /// and the period is set by $4000 (or $4004) bits 0-3
    divider: Counter = .{ .desired_period = 0 },
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
    }

    pub inline fn tickByFrameCounter(self: *Envelope) void {
        if (self.should_start) {
            self.should_start = false;
            self.decay_counter = 0b1111;
            self.divider.desired_period = self.volume;
            return;
        }

        // If start flag is clear (meaning the envelope is already running),
        // We clock the divider as usual.
        if (!self.divider.tick()) return;

        if (self.decay_counter == 0) {
            if (self.is_looping) // if the loop flag is set, reload.
                self.decay_counter = 0b1111;
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
    pub fn tickByTimer(self: *Sequencer) u8 {
        const result = self.duty_sequence[self.i];
        self.i += 1;
        if (self.i == 8) self.i = 0;
        return result;
    }
};

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
    note_length: u8 = 0,
    is_halted: bool = false,
    out: bool = false,

    pub fn tickByFrameCounter(self: *LengthCounter) bool {
        if (self.is_halted) {
            self.out = false;
        } else if (self.note_length == 0) {
            self.note_length = LengthTable[self.control.length] - 1;
            // The length counter mutes the channel if it's clocked while
            // the length is already 0.
            self.out = false;
        } else {
            self.note_length -= 1;
            self.out = true;
        }

        return self.out;
    }
};

/// The Pulse channel: https://www.nesdev.org/wiki/APU_Pulse
const PulseGenerator = struct {
    /// A struct to pack/unpack the raw-period for the 11-bit timer
    /// in the Pulse generator.
    const TimerPeriod = packed struct {
        lo8: u8 = 0, // low 8 bits
        hi3: u3 = 0, // high 3 bits
    };

    /// The APU envelope unit to control the volume for this pulse channel.
    envelope: Envelope = .{},
    /// Increments (or decrements) the period of the pulse over time.
    sweep: Sweep = .{},
    timer: Counter = .{ .desired_period = 0 },
    /// Length counter determines the note length for the pulse channel
    length_counter: LengthCounter = .{},

    sequencer: Sequencer = .{},

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
    /// This will set the low byte of the 11-bit timer.
    pub inline fn writeTimerLo(
        self: *PulseGenerator,
        value: u8,
    ) void {
        const old_period: u11 = @truncate(self.timer.desired_period);
        var new_period: TimerPeriod = @bitCast(old_period);
        new_period.lo8 = value;

        self.timer.desired_period = @as(u11, @bitCast(new_period));
    }

    /// Write to register $4003 (for pulse 1) or $4007 (for pulse 2)
    /// This will set the high byte of the 11-bit timer to the low 3-bits of `value`,
    /// and the length counter's length to the high 5-bits of `value`.
    pub inline fn writeTimerHi(
        self: *PulseGenerator,
        value: u8,
    ) void {
        self.length_counter.control.length = @truncate(value & 0b11111_000 >> 3);

        const old_period: u11 = @truncate(self.timer.desired_period);
        var new_period: TimerPeriod = @bitCast(old_period);
        new_period.hi3 = @truncate(value);

        self.timer.desired_period = @as(u11, @bitCast(new_period));
    }

    /// Clock every component of the pulse generator that is driven by the frame counter.
    pub fn tickByFrameCounter(self: *PulseGenerator) i16 {
        self.envelope.tickByFrameCounter();
        self.sweep.tickByFrameCounter(self.timer.desired_period);
        self.timer.desired_period = self.sweep.target_period;

        const out = self.sequencer.duty_sequence[self.sequencer.i];

        const sequencer_muted = out == 0;
        const lc_muted = !self.length_counter.tickByFrameCounter();
        const sweep_muted = self.sweep.isMuted();

        // Are any of the sub-components muting the output?
        if (lc_muted or sweep_muted or sequencer_muted) return 0;

        return self.envelope.output_volume * out;
    }

    pub inline fn tickByApuClock(self: *PulseGenerator) void {
        if (!self.timer.tick()) return;
        _ = self.sequencer.tickByTimer();
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
    divider: Counter = .{ .desired_period = 240 },
    current_step: u8 = 0,
    max_step: u8 = 4,

    // TODO: implement the 4 and 5 step sequence
    pub fn tickByApuClock(self: *FrameCounter) bool {
        if (!self.divider.tick()) return false;

        self.current_step += 1;
        if (self.current_step == self.max_step) {
            self.current_step = 0;
        }

        return true;
    }
};

frame_counter: FrameCounter = .{},

// Is flipped every CPU cycle. 2 CPU cycles = 1 APU cycle.
is_apu_tick: bool = false,

pulse_1: PulseGenerator = .{},
pulse_2: PulseGenerator = .{},

cpu: *Cpu,

out_volume: i16 = 0.0,

pub fn init(cpu: *Cpu) Self {
    return Self{ .cpu = cpu };
}

pub fn tickByCpuClock(self: *Self) void {
    if (self.is_apu_tick) {
        // The frame counter is clocked every APU cycle.
        // If the FC itself generates a quarter frame clock,
        // we tick the APU units that are driven by the frame counter.
        if (self.frame_counter.tickByApuClock()) {
            const pulse1 = self.pulse_1.tickByFrameCounter();
            const pulse2 = self.pulse_2.tickByFrameCounter();
            self.out_volume = mixVolume(pulse1, pulse2);
        }

        self.pulse_1.tickByApuClock();
        self.pulse_2.tickByApuClock();
    }

    self.is_apu_tick = !self.is_apu_tick;
}

/// Receive
fn mixVolume(pulse1: f32, pulse2: f32) i16 {
    const pulse_out = 0.00752 * (pulse1 + pulse2);
    if (pulse_out == 0) return 0;

    // TODO: change this when ohen other channels are emulating.
    const tnd_out: f32 = 159.79 / 100.0;
    return @intFromFloat(pulse_out + tnd_out);
}
