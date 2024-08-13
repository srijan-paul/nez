pub const NESError = error{
    NotImplemented,
    InvalidROM,
    UnsupportedMapper,
};

const std = @import("std");

/// A simple thread safe queue implementation
pub fn Queue(T: type) type {
    return struct {
        const Self = @This();
        const QueueError = error{
            popping_from_empty,
        };

        data: []T,
        front: usize,
        back: usize,
        allocator: std.mem.Allocator,
        lock: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Queue(T){
                .data = try allocator.alloc(T, 64),
                .front = 0,
                .back = 0,
                .allocator = allocator,
                .lock = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.data);
        }

        pub inline fn isFull(self: *const Self) bool {
            return (self.back + 1) % self.data.len == self.front;
        }

        pub fn len(self: *const Self) usize {
            if (self.front <= self.back) {
                return self.back - self.front;
            } else {
                return self.data.len - self.front + self.back;
            }
        }

        pub inline fn push(self: *Self, value: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            if (self.isFull()) {
                const new_data = try self.allocator.alloc(T, self.data.len * 2);
                const num_items = self.len();

                if (self.front < self.back) {
                    for (0..self.data.len) |i| {
                        new_data[i] = self.data[i];
                    }
                } else {
                    for (0..num_items) |i| {
                        new_data[i] = self.data[(self.front + i) % self.data.len];
                    }
                }

                self.allocator.free(self.data);
                self.data = new_data;
                self.back = num_items;
                self.front = 0;
            }

            self.data[self.back] = value;
            self.back = (self.back + 1) % self.data.len;
        }

        pub inline fn pop(self: *Self) QueueError!T {
            self.lock.lock();
            defer self.lock.unlock();

            if (self.front == self.back) {
                return QueueError.popping_from_empty;
            }

            const value = self.data[self.front];
            self.front = (self.front + 1) % self.data.len;
            return value;
        }

        pub inline fn isEmpty(self: *Self) bool {
            return self.front == self.back;
        }
    };
}

test "Queue – basics" {
    var q = try Queue(u32).init(std.testing.allocator);
    defer q.deinit();

    try q.push(1);
    try q.push(2);
    try q.push(3);

    try std.testing.expectEqual(1, try q.pop());
    try std.testing.expectEqual(2, try q.pop());
    try std.testing.expectEqual(3, try q.pop());

    try std.testing.expect(q.isEmpty());
}

test "Queue – resizing" {
    var nums: [50_000]usize = undefined;
    for (0..nums.len) |i| {
        nums[i] = i;
    }

    var q = try Queue(usize).init(std.testing.allocator);
    defer q.deinit();

    for (0..nums.len) |i| {
        try q.push(nums[i]);
    }

    for (0..nums.len) |i| {
        try std.testing.expectEqual(nums[i], try q.pop());
    }

    for (0..nums.len / 2) |i| {
        try q.push(nums[i]);
    }

    for (0..nums.len / 4) |i| {
        try std.testing.expectEqual(nums[i], try q.pop());
    }

    for (nums.len / 2..nums.len) |i| {
        try q.push(nums[i]);
    }

    for (nums.len / 4..nums.len) |i| {
        try std.testing.expectEqual(nums[i], try q.pop());
    }
}
