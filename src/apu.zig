const std = @import("std");

const Self = @This();

/// A divider that counts up to a period, then resets.
/// Can be used to divide the frequency of a signal by a factor N.
/// In other words, we multiply the input signal's period by N,
/// where `N = <input period> / desired_period`.
const Counter = struct {
    target: u16,
    current_count: u16 = 0,

    /// Ticks the divider once, then returns `true` if the period
    /// has elapsed, `false` otherwise.
    pub inline fn tick(self: *Counter) bool {
        self.current_count += 1;
        if (self.current_count >= self.target) {
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
        const delta: i32 = in_period >> self.config.shift_count;
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

    pub inline fn reset(self: *Envelope, ctrl: PulseCtrlRegister) void {
        self.is_looping = ctrl.is_looping;
        self.is_volume_constant = ctrl.is_volume_constant;
        self.volume = ctrl.volume;
    }

    pub inline fn tickByFrameCounter(self: *Envelope) void {
        if (!self.divider.tick()) return;

        if (self.decay_counter == 0) {
            if (!self.is_looping) return;
            // Reset volume to 15, and continue.
            self.decay_counter = 0b1111;
        }

        self.output_volume = if (self.is_volume_constant)
            self.volume
        else
            self.decay_counter;

        self.decay_counter -= 1;
    }
};

const Sequencer = struct {};
const LengthCounter = struct {};

/// The Pulse channel: https://www.nesdev.org/wiki/APU_Pulse
const PulseGenerator = struct {
    /// maps a 2-bit value to the bit-map representing the output
    /// amplitudes of the duty-cycle.
    const DutyCycleTable = [4]u8{
        0b0100_0000, // 12.5%
        0b0110_0000, // 25%
        0b0111_1000, // 50%
        0b1001_1111, // 75%
    };

    /// Low 8-bits of the period.
    /// Mapped to register $4002 or $4006
    raw_period_lo: u8 = 0,
    /// High 3-bits of the period.
    /// Only low 3-bits of this register are used
    /// Mapped to register $4003 or $4007
    raw_period_hi: u8 = 0,
    /// The APU envelope unit to control the volume for this pulse channel.
    envelope: Envelope = .{},
    /// Increments (or decrements) the period of the pulse over time.
    sweep: Sweep = .{},
    timer: Counter = .{ .desired_period = 0 },
    /// The % of time for which the pulse is ON in one period.
    /// Set by bits 6-7 of $4000 or $4004.
    duty_cycle: u8 = DutyCycleTable[0],

    /// Write to register $4000/$4004
    pub inline fn writeControlReg(
        self: *PulseGenerator,
        value: PulseCtrlRegister,
    ) void {
        self.envelope.reset(value);
        self.duty_cycle = DutyCycleTable[value.duty_cycle];
    }

    pub fn tickByFrameCounter(self: *PulseGenerator) void {
        self.envelope.tickByFrameCounter();
        self.sweep.tickByFrameCounter();
        self.timer.target = self.sweep.target_period;
    }

    pub inline fn tickByCpuClock(self: *PulseGenerator) void {
        self.timer.tick();
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
    divider: Counter = .{ .target = 240 },
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

// Is flipped every CPU cycle.
// 2 CPU cycles = 1 APU cycle.
is_apu_tick: bool = false,

pulse_1: PulseGenerator = .{},
pulse_2: PulseGenerator = .{},

pub fn tickByCpuClock(self: *Self) void {
    self.pulse_1.tickByCpuClock();
    self.pulse_2.tickByCpuClock();

    if (self.is_apu_tick) {
        // The frame counter is clocked every APU cycle.
        // If the FC itself generates a quarter frame clock,
        // we tick the APU units that are driven by the frame counter.
        if (self.frame_counter.tickByApuClock()) {
            self.pulse_1.tickByFrameCounter();
            self.pulse_2.tickByFrameCounter();
        }
    }

    self.is_apu_tick = !self.is_apu_tick;
}
