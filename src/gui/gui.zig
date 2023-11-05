const rg = @import("raygui");
const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Label = struct {
    bounds: rg.Rectangle,
    text: [:0]const u8,
};

pub const Window = struct {
    const Self = @This();

    bounds: rg.Rectangle,
    title: [:0]const u8,

    allocator: Allocator,
    labels: std.ArrayList(Label),

    _is_visible: bool = true,

    pub fn new(
        allocator: Allocator,
        title: [:0]const u8,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
    ) Window {
        return Self{
            .bounds = .{
                .x = x,
                .y = y,
                .width = w,
                .height = h,
            },
            .title = title,
            .allocator = allocator,
            .labels = std.ArrayList(Label).init(allocator),
        };
    }

    pub fn draw(self: *Self) void {
        if (!self._is_visible) return;
        self._is_visible = rg.GuiWindowBox(self.bounds, self.title) == 0;

        for (self.labels.items) |label| {
            _ = rg.GuiLabel(.{
                .x = self.bounds.x + label.bounds.x,
                .y = self.bounds.y + label.bounds.y,
                .width = label.bounds.width,
                .height = label.bounds.height,
            }, label.text);
        }
    }

    pub fn addLabel(
        self: *Self,
        text: [:0]const u8,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
    ) !void {
        return self.labels.append(Label{
            .bounds = .{
                .x = x,
                .y = y,
                .width = w,
                .height = h,
            },
            .text = text,
        });
    }
};
