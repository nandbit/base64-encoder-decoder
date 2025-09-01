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
        if (input.len == 0) {
            return "";
        }
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
        if (input.len == 0) {
            return "";
        }
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
            if (byte == '=') {
                output_groups -= 1;
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

// RFC 4648 tests (https://datatracker.ietf.org/doc/html/rfc4648)
test "test encoder decoder" {
    const base64 = Base64.init();
    const allocator = std.testing.allocator;

    const enc1 = try base64.encode(allocator, "");
    const dec1 = try base64.decode(allocator, "");

    const enc2 = try base64.encode(allocator, "f");
    const dec2 = try base64.decode(allocator, "Zg==");

    const enc3 = try base64.encode(allocator, "fo");
    const dec3 = try base64.decode(allocator, "Zm8=");

    const enc4 = try base64.encode(allocator, "foo");
    const dec4 = try base64.decode(allocator, "Zm9v");

    const enc5 = try base64.encode(allocator, "foob");
    const dec5 = try base64.decode(allocator, "Zm9vYg==");

    const enc6 = try base64.encode(allocator, "fooba");
    const dec6 = try base64.decode(allocator, "Zm9vYmE=");

    const enc7 = try base64.encode(allocator, "foobar");
    const dec7 = try base64.decode(allocator, "Zm9vYmFy");

    const enc8 = try base64.encode(allocator, "foobarfoobarfoo");
    const dec8 = try base64.decode(allocator, "Zm9vYmFyZm9vYmFyZm9v");

    const enc9 = try base64.encode(allocator, "foobarfoobarfoob");
    const dec9 = try base64.decode(allocator, "Zm9vYmFyZm9vYmFyZm9vYg==");

    const enc10 = try base64.encode(allocator, "foobarfoobarfooba");
    const dec10 = try base64.decode(allocator, "Zm9vYmFyZm9vYmFyZm9vYmE=");

    const enc11 = try base64.encode(allocator, "foobarfoobarfoobar");
    const dec11 = try base64.decode(allocator, "Zm9vYmFyZm9vYmFyZm9vYmFy");

    defer allocator.free(enc1);
    defer allocator.free(enc2);
    defer allocator.free(enc3);
    defer allocator.free(enc4);
    defer allocator.free(enc5);
    defer allocator.free(enc6);
    defer allocator.free(enc7);
    defer allocator.free(enc8);
    defer allocator.free(enc9);
    defer allocator.free(enc10);
    defer allocator.free(enc11);

    defer allocator.free(dec1);
    defer allocator.free(dec2);
    defer allocator.free(dec3);
    defer allocator.free(dec4);
    defer allocator.free(dec5);
    defer allocator.free(dec6);
    defer allocator.free(dec7);
    defer allocator.free(dec8);
    defer allocator.free(dec9);
    defer allocator.free(dec10);
    defer allocator.free(dec11);

    try expect(std.mem.eql(u8, enc1, ""));
    try expect(std.mem.eql(u8, enc2, "Zg=="));
    try expect(std.mem.eql(u8, enc3, "Zm8="));
    try expect(std.mem.eql(u8, enc4, "Zm9v"));
    try expect(std.mem.eql(u8, enc5, "Zm9vYg=="));
    try expect(std.mem.eql(u8, enc6, "Zm9vYmE="));
    try expect(std.mem.eql(u8, enc7, "Zm9vYmFy"));
    try expect(std.mem.eql(u8, enc8, "Zm9vYmFyZm9vYmFyZm9v"));
    try expect(std.mem.eql(u8, enc9, "Zm9vYmFyZm9vYmFyZm9vYg=="));
    try expect(std.mem.eql(u8, enc10, "Zm9vYmFyZm9vYmFyZm9vYmE="));
    try expect(std.mem.eql(u8, enc11, "Zm9vYmFyZm9vYmFyZm9vYmFy"));

    try expect(std.mem.eql(u8, dec1, ""));
    try expect(std.mem.eql(u8, dec2, "f"));
    try expect(std.mem.eql(u8, dec3, "fo"));
    try expect(std.mem.eql(u8, dec4, "foo"));
    try expect(std.mem.eql(u8, dec5, "foob"));
    try expect(std.mem.eql(u8, dec6, "fooba"));
    try expect(std.mem.eql(u8, dec7, "foobar"));
    try expect(std.mem.eql(u8, dec8, "foobarfoobarfoo"));
    try expect(std.mem.eql(u8, dec9, "foobarfoobarfoob"));
    try expect(std.mem.eql(u8, dec10, "foobarfoobarfooba"));
    try expect(std.mem.eql(u8, dec11, "foobarfoobarfoobar"));
}
