const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utils.zig");

const CellState = enum {
    const Self = @This();

    Empty,
    Player1,
    Player2,

    pub fn to_slice(self: Self) []const u8 {
        return switch (self) {
            .Empty => "-",
            .Player1 => "O",
            .Player2 => "X",
        };
    }
};

pub const MoveType = enum {
    const Self = @This();

    Player1,
    Player2,

    pub inline fn to_cell(self: Self) CellState {
        return switch (self) {
            .Player1 => .Player1,
            .Player2 => .Player2,
        };
    }

    pub inline fn from_idx(player_idx: usize) Self {
        return switch (player_idx) {
            0 => .Player1,
            1 => .Player2,
            else => unreachable,
        };
    }
};

pub const Position = @Vector(2, usize);

pub const Error = error{
    OutOfBound,
    AlreadyTaken,
};

pub const Game = struct {
    const Self = @This();

    size: u32,
    board: []CellState,

    pub fn init(size: u32) Allocator.Error!Game {
        const b = try utils.allocator.alloc(CellState, size * size);
        @memset(b, .Empty);
        return .{
            .size = size,
            .board = b,
        };
    }

    inline fn get_idx_from_pos(self: *const Self, pos: Position) usize {
        const idx = pos[0] + pos[1] * self.size;
        std.debug.assert(idx < self.board.len);
        return idx;
    }

    inline fn is_pos_inbound(self: *const Self, pos: Position) bool {
        const s = self.size;
        return pos[0] < s and pos[1] < s;
    }

    inline fn at(self: *const Self, pos: Position) CellState {
        return self.board[self.get_idx_from_pos(pos)];
    }

    // TODO: Optimize and rewrite this function, it is ultra ugly
    fn is_move_winning(self: *const Self, pos: Position) bool {
        // Absolutely horrendous function, but it's fast enough so idrc
        // Taken from https://stackoverflow.com/a/38211417 cause I couldn't be bothered :)
        const played = self.at(pos);

        // horizontalCheck
        for (0..self.size - 4) |j| {
            for (0..self.size) |i| {
                if (self.at(.{ i, j }) == played and self.at(.{ i, j + 1 }) == played and self.at(.{ i, j + 2 }) == played and self.at(.{ i, j + 3 }) == played and self.at(.{ i, j + 4 }) == played) {
                    return true;
                }
            }
        }
        // verticalCheck
        for (0..self.size - 4) |i| {
            for (0..self.size) |j| {
                if (self.at(.{ i, j }) == played and self.at(.{ i + 1, j }) == played and self.at(.{ i + 2, j }) == played and self.at(.{ i + 3, j }) == played and self.at(.{ i + 4, j }) == played) {
                    return true;
                }
            }
        }
        // ascendingDiagonalCheck
        for (4..self.size) |i| {
            for (0..self.size - 4) |j| {
                if (self.at(.{ i, j }) == played and self.at(.{ i - 1, j + 1 }) == played and self.at(.{ i - 2, j + 2 }) == played and self.at(.{ i - 3, j + 3 }) == played and self.at(.{ i - 4, j + 4 }) == played) {
                    return true;
                }
            }
        }
        // descendingDiagonalCheck
        for (4..self.size) |i| {
            for (4..self.size) |j| {
                if (self.at(.{ i, j }) == played and self.at(.{ i - 1, j - 1 }) == played and self.at(.{ i - 2, j - 2 }) == played and self.at(.{ i - 3, j - 3 }) == played and self.at(.{ i - 4, j - 4 }) == played) {
                    return true;
                }
            }
        }
        return false;
    }

    // Returns true if this was a winning move
    // false if the game continues
    pub fn place(self: *Self, pos: Position, move_type: MoveType) Error!bool {
        if (!is_pos_inbound(self, pos))
            return Error.OutOfBound;
        const idx = get_idx_from_pos(self, pos);
        if (self.board[idx] != .Empty)
            return Error.AlreadyTaken;
        self.board[idx] = move_type.to_cell();
        return self.is_move_winning(pos);
    }

    pub fn dump(self: *const Self, output_file: std.fs.File) !void {
        for (0..self.size) |x| {
            for (0..self.size) |y| {
                try output_file.writeAll(self.at(.{ x, y }).to_slice());
            }
            try output_file.writeAll("\n");
        }
    }

    pub fn deinit(self: *const Self) void {
        utils.allocator.free(self.board);
    }
};

test {
    std.testing.refAllDecls(@This());
}
