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

    pub fn encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        // Three scenarios:
        // 1. 3 byte window
        // 2. 2 byte window
        // 3. 1 byte window
        var count: u8 = 0;
        var buf = [3]u8{ 0, 0, 0 };
        const n_out = try _calc_encode_length(input);
        var output = try allocator.alloc(u8, n_out);
        // defer allocator.free(output);

        for (input, 0..) |byte, i| {
            buf[i % 3] = byte;
            count += 1;
            if (count == 3) {
                output[i - 2] = buf[0] >> 2;
                output[i - 1] = ((buf[0] & 0x03) << 4) | ((0xf0 & buf[1]) >> 4);
                output[i] = ((buf[1] & 0x0f) << 2) | ((0xA0 & buf[2]) >> 6);
                output[i + 1] = buf[2] & 0x3f;
                count = 0;
            }
            if (count == 2) {
                output[i - 1] = buf[0] >> 2;
                output[i] = ((buf[0] & 0x03) << 4) | ((0xf0 & buf[1]) >> 4);
                output[i + 1] = ((buf[1] & 0x0f) << 2);
                output[i + 2] = '=';
            }
            if (count == 1) {
                output[i] = buf[0] >> 2;
                output[i + 1] = (buf[0] & 0x03) << 4;
                output[i + 2] = '=';
                output[i + 3] = '=';
            }
        }
        return output;
    }

    fn _char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    // How many bytes the encoder will produce
    fn _calc_encode_length(input: []const u8) !usize {
        if (input.len < 3) {
            return 4;
        }
        const n_groups = try std.math.divCeil(usize, input.len, 3);
        return n_groups * 4;
    }

    // How many bytes the decoder will produce
    fn _calc_decode_length(input: []const u8) !usize {
        if (input.len < 4) {
            return 3;
        }

        const n_groups = try std.math.divFloor(usize, input, 4);
        const output_groups = n_groups * 3;

        for (input) |byte| {
            if (byte == '=') {
                output_groups -= 1;
            }
        }

        return output_groups;
    }
};

pub fn main() !void {
    const base64 = Base64.init();

    var memory_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&memory_buffer);
    const allocator = fba.allocator();
    const encoded_bytes: []u8 = try Base64.encode(allocator, "H");

    for (encoded_bytes) |byte| {
        // try stdout.print("{d}", .{byte});
        // try stdout.flush();
        if (byte == '=') {
            try stdout.print("=", .{});
            try stdout.flush();
            continue;
        }

        try stdout.print("{c}", .{base64._char_at(byte)});
        try stdout.flush();
    }
    try stdout.print("\n", .{});
    try stdout.flush();
}
