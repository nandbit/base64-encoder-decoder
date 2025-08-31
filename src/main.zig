const std = @import("std");

// The idea is to convert incoming data into a representation
// through 64 symbols. To do that, the base64 encoder takes
// the incoming bits 6 at a time (because 2^6 = 64), and
// associates those 6 bits with a symbol from the conversion
// table
//
// The encoder prefers to take 3 bytes at a time, because
// 3 x 8 = 24 and 24 is divisible by 6, meaning 4 conversions
// can happen at once.

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const Base64 = struct {
    _table: *const [64]u8, // pointer to a length 64 u8 array

    pub fn init() Base64 {
        return Base64{
            ._table = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ++
                "abcdefghijklmnopqrstuvwxyz" ++
                "0123456789" ++
                "+/",
        };
    }

    fn _char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }
};

pub fn main() !void {
    const base64 = Base64.init();

    try stdout.print("Character at index 27: {c}\n", .{base64._char_at(27)});
    try stdout.flush();
}
