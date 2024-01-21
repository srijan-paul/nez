const std = @import("std");

pub const Button = enum(u3) {
    A,
    B,
    Select,
    Start,
    Up,
    Down,
    Left,
    Right,
};

pub const ButtonState = [8]bool;

/// Reading from $4016/$4017 reports the state of the each button in this format.
/// bit 0: Primary controller status bit; (1 if button pressed, 0 otherwise)
/// bit 1: Secondary controller status bit; (always 0 since I don't support 2 controllers)
/// bit 2: Microphone status bit; (WTF is this even?)
/// bits 3-7: Not used
pub const Output = packed struct {
    primary_controller: bool = 5,
    secondary_controller: bool = 6,
    microphone: bool = 7,
    __unused: u5 = 0,
};

const Self = @This();

/// $4016 writes will write to this register.
/// Represents the strobe bit.
input: u8 = 0,

/// State of the buttons.
buttons: ButtonState = [_]bool{false} ** 8,
output1: u8 = 0, // $4016 read

/// The button for which we have to report the state the next time $4016 is read
next_button: u3 = 0,

/// The status each button is reported over the course of 8 reads from $4016, in the following order:
/// A, B, Select, Start, Up, Down, Left, Right
pub fn read(self: *Self) u8 {
    var strobe = self.input & 0b1 == 1;
    if (strobe) self.next_button = 0;

    var is_pressed = self.buttons[self.next_button];
    self.next_button = @addWithOverflow(self.next_button, 1)[0];

    // std.debug.print("button: {any}\n", .{self.buttons});

    return @intFromBool(is_pressed);
}

/// $4016 write
pub fn write(self: *Self, value: u8) void {
    self.input = value;
}

pub fn setInputs(self: *Self, inputs: ButtonState) void {
    self.buttons = inputs;
}
