const std = @import("std");
const expect = std.testing.expect;

// The idea is to convert incoming data into a representation
// through 64 symbols. To do that, the base64 encoder takes
// the incoming bits 6 at a time (because 2^6 = 64), and
// associates those 6 bits with a symbol from the conversion
// table
//
// The encoder prefers to take 3 bytes at a time, because
// 3 x 8 = 24 and 24 is divisible by 6, meaning 4 conversions
// can happen at once.

pub const Base64 = struct {
    _table: *const [64]u8, // pointer to a length 64 u8 array

    pub fn init() Base64 {
        return Base64{
            ._table = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ++
                "abcdefghijklmnopqrstuvwxyz" ++
                "0123456789" ++
                "+/",
        };
    }

    pub fn encode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        // Three scenarios:
        // 1. 3 byte window
        // 2. 2 byte window
        // 3. 1 byte window
        var buf = [3]u8{ 0, 0, 0 };
        const n_out = try _calc_encode_length(input);
        var output = try allocator.alloc(u8, n_out);
        var count: u8 = 0;
        var out_position: u64 = 0;

        for (input) |byte| {
            buf[count] = byte;
            count += 1;
            if (count == 3) {
                output[out_position] = self._char_at(buf[0] >> 2);
                output[out_position + 1] = self._char_at(((buf[0] & 0x03) << 4) | (buf[1] >> 4));
                output[out_position + 2] = self._char_at(((buf[1] & 0x0f) << 2) | (buf[2] >> 6));
                output[out_position + 3] = self._char_at(buf[2] & 0x3f);

                count = 0;
                out_position += 4;
            }
        }
        if (count == 2) {
            output[out_position] = self._char_at(buf[0] >> 2);
            output[out_position + 1] = self._char_at(((buf[0] & 0x03) << 4) | (buf[1] >> 4));
            output[out_position + 2] = self._char_at(((buf[1] & 0x0f) << 2));
            output[out_position + 3] = '=';
        }
        if (count == 1) {
            output[out_position] = self._char_at(buf[0] >> 2);
            output[out_position + 1] = self._char_at((buf[0] & 0x03) << 4);
            output[out_position + 2] = '=';
            output[out_position + 3] = '=';
        }

        return output;
    }

    pub fn decode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var buf = [4]u8{ 0, 0, 0, 0 };
        const n_out = try _calc_decode_length(input);
        var output = try allocator.alloc(u8, n_out);
        var count: u8 = 0;
        var out_position: u64 = 0;

        // Unlike the encoder, we always have an input be a
        // a multiple of 4, because of the "=" fills
        for (input) |byte| {
            buf[count] = self._char_index(byte);
            count += 1;
            if (count == 4) {
                output[out_position] = (buf[0] << 2) | (buf[1] >> 4);
                if (buf[2] != 64) {
                    output[out_position + 1] = (buf[1] << 4) | (buf[2] >> 2);
                }
                if (buf[3] != 64) {
                    output[out_position + 2] = (buf[2] << 6) | buf[3];
                }
                out_position += 3;
                count = 0;
            }
        }

        return output;
    }

    fn _char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    fn _calc_encode_length(input: []const u8) !usize {
        if (input.len < 3) {
            return 4;
        }
        const n_groups = try std.math.divCeil(usize, input.len, 3);
        return n_groups * 4;
    }

    fn _calc_decode_length(input: []const u8) !usize {
        if (input.len < 4) {
            return 3;
        }

        const n_groups: usize = try std.math.divFloor(usize, input.len, 4);
        var output_groups: usize = n_groups * 3;

        for (input) |byte| {
            // We break here because if we see a '=', that means
            // we reached the end of the data, since '=' can only
            // appear at the very end of the data (as padding).
            if (byte == '=') {
                output_groups -= 1;
                break;
            }
        }

        return output_groups;
    }

    fn _char_index(self: Base64, char: u8) u8 {
        if (char == '=')
            return 64;
        var index: u8 = 0;
        for (0..63) |i| {
            if (self._char_at(i) == char)
                break;
            index += 1;
        }

        return index;
    }
};

test "test encoder" {
    const input = "Base 64 encode decode test";
    const expected_output = "QmFzZSA2NCBlbmNvZGUgZGVjb2RlIHRlc3Q=";
    const base64 = Base64.init();
    const allocator = std.testing.allocator;
    const encoded_text = try base64.encode(allocator, input);
    const decoded_text = try base64.decode(allocator, encoded_text);

    defer allocator.free(encoded_text);
    defer allocator.free(decoded_text);

    try expect(std.mem.eql(u8, encoded_text, expected_output));
    try expect(std.mem.eql(u8, decoded_text, input));
}
