const std = @import("std");
const Allocator = std.mem.Allocator;

// COLORS
const color_red: []const u8 = "\x1b[31m";
const color_blue: []const u8 = "\x1b[34m";
const color_green: []const u8 = "\x1b[32m";
const color_reset: []const u8 = "\x1b[m";

const player1_highlight = color_green ++ "O" ++ color_reset;
const player1_color = color_blue ++ "O" ++ color_reset;
const player2_highlight = color_green ++ "X" ++ color_reset;
const player2_color = color_red ++ "X" ++ color_reset;
// \COLORS

const CellState = enum {
    const Self = @This();

    Empty,
    Player1,
    Player2,

    pub fn to_slice(self: Self, colors: bool, highlight: bool) []const u8 {
        return switch (self) {
            .Empty => "-",
            .Player1 => if (!colors) "O" else if (highlight) player1_highlight else player1_color,
            .Player2 => if (!colors) "X" else if (highlight) player2_highlight else player2_color,
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
    const cells_to_align = 5;

    size: u32,
    internal_board: []CellState,
    allocator: std.mem.Allocator,

    pub fn init(size: u32, allocator: std.mem.Allocator) Allocator.Error!Game {
        const b = try allocator.alloc(CellState, size * size);
        @memset(b, .Empty);
        return .{
            .size = size,
            .internal_board = b,
            .allocator = allocator,
        };
    }

    inline fn reset(self: *Self) void {
        @memset(self.internal_board, .Empty);
    }

    inline fn get_idx_from_pos(self: *const Self, pos: Position) usize {
        const idx = pos[0] + pos[1] * self.size;
        std.debug.assert(idx < self.internal_board.len);
        return idx;
    }

    inline fn is_pos_inbound(self: *const Self, pos: Position) bool {
        const s = self.size;
        return pos[0] < s and pos[1] < s;
    }

    inline fn is_ipos_inbound(self: *const Self, pos: @Vector(2, isize)) bool {
        const s: isize = @intCast(self.size);
        return pos[0] >= 0 and pos[1] >= 0 and pos[0] < s and pos[1] < s;
    }

    inline fn at(self: *const Self, pos: Position) CellState {
        return self.internal_board[self.get_idx_from_pos(pos)];
    }

    fn count_in_line(self: *const Self, start_pos: Position, comptime direction: @Vector(2, isize)) u32 {
        const state = self.at(start_pos);
        std.debug.assert(state != .Empty);
        var current_pos: @Vector(2, isize) = @intCast(start_pos);

        inline for (0..cells_to_align) |i| {
            if (!self.is_ipos_inbound(current_pos)) return i;

            const pos = @as(Position, @intCast(current_pos));
            if (self.at(pos) != state) return i;

            current_pos = current_pos + direction;
        }
        return cells_to_align;
    }

    fn is_move_winning(self: *const Self, pos: Position) bool {
        const played_cell = self.at(pos);
        std.debug.assert(played_cell != .Empty);
        const directions = [_]@Vector(2, isize){
            .{ 1, 0 }, // Horizontal (-)
            .{ 0, 1 }, // Vertical (|)
            .{ 1, -1 }, // Main diagonal (\)
            .{ 1, 1 }, // Anti-diagonal (/)
        };

        inline for (directions) |dir| {
            const count = self.count_in_line(pos, dir) +
                self.count_in_line(pos, -dir) - 1;
            if (count >= cells_to_align) return true;
        }
        return false;
    }

    // Returns true if this was a winning move
    // false if the game continues
    pub fn place(self: *Self, pos: Position, move_type: MoveType) Error!bool {
        if (!is_pos_inbound(self, pos))
            return Error.OutOfBound;
        const idx = get_idx_from_pos(self, pos);
        if (self.internal_board[idx] != .Empty)
            return Error.AlreadyTaken;
        self.internal_board[idx] = move_type.to_cell();
        return self.is_move_winning(pos);
    }

    pub fn dump(self: *const Self, io: std.Io, output_file: std.Io.File, colors: bool, pos_to_highlight: Position) !void {
        for (0..self.size) |x| {
            for (0..self.size) |y| {
                try output_file.writeStreamingAll(io, self.at(.{ x, y }).to_slice(
                    colors,
                    pos_to_highlight[0] == x and pos_to_highlight[1] == y,
                ));
            }
            try output_file.writeStreamingAll(io, "\n");
        }
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.internal_board);
    }
};

test "get_idx_from_pos calculates correct index" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    try std.testing.expectEqual(0, game.get_idx_from_pos(.{ 0, 0 }));
    try std.testing.expectEqual(5, game.get_idx_from_pos(.{ 5, 0 }));
    try std.testing.expectEqual(10, game.get_idx_from_pos(.{ 0, 1 }));
    try std.testing.expectEqual(55, game.get_idx_from_pos(.{ 5, 5 }));
    try std.testing.expectEqual(99, game.get_idx_from_pos(.{ 9, 9 }));
}

test "is_pos_inbound correctly identifies boundaries" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    // Test positions inside the bounds
    try std.testing.expect(game.is_pos_inbound(.{ 0, 0 }));
    try std.testing.expect(game.is_pos_inbound(.{ 9, 9 }));
    try std.testing.expect(game.is_pos_inbound(.{ 5, 5 }));

    // Test positions outside the bounds
    try std.testing.expect(!game.is_pos_inbound(.{ 10, 0 }));
    try std.testing.expect(!game.is_pos_inbound(.{ 0, 10 }));
    try std.testing.expect(!game.is_pos_inbound(.{ 10, 10 }));
    try std.testing.expect(!game.is_pos_inbound(.{ 100, 100 }));
}

test "is_move_winning detects Horizontal win" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 2, 5 }, .Player1);
    _ = try game.place(.{ 3, 5 }, .Player1);
    _ = try game.place(.{ 4, 5 }, .Player1);
    _ = try game.place(.{ 5, 5 }, .Player1);
    _ = try game.place(.{ 6, 5 }, .Player1);
    try std.testing.expect(game.is_move_winning(.{ 6, 5 }));
    try std.testing.expect(game.is_move_winning(.{ 5, 5 }));
    try std.testing.expect(game.is_move_winning(.{ 4, 5 }));
    try std.testing.expect(game.is_move_winning(.{ 3, 5 }));
    try std.testing.expect(game.is_move_winning(.{ 2, 5 }));
}

test "is_move_winning detects Vertical win" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 5, 2 }, .Player2);
    _ = try game.place(.{ 5, 3 }, .Player2);
    _ = try game.place(.{ 5, 4 }, .Player2);
    _ = try game.place(.{ 5, 5 }, .Player2);
    _ = try game.place(.{ 5, 6 }, .Player2);
    try std.testing.expect(game.is_move_winning(.{ 5, 6 }));
    try std.testing.expect(game.is_move_winning(.{ 5, 2 }));
}

test "is_move_winning detects Main diagonal win" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 1, 1 }, .Player1);
    _ = try game.place(.{ 2, 2 }, .Player1);
    _ = try game.place(.{ 3, 3 }, .Player1);
    _ = try game.place(.{ 4, 4 }, .Player1);
    _ = try game.place(.{ 5, 5 }, .Player1);
    try std.testing.expect(game.is_move_winning(.{ 5, 5 }));
    try std.testing.expect(game.is_move_winning(.{ 1, 1 }));
}

test "is_move_winning detects Anti-diagonal win" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 8, 1 }, .Player2);
    _ = try game.place(.{ 7, 2 }, .Player2);
    _ = try game.place(.{ 6, 3 }, .Player2);
    _ = try game.place(.{ 5, 4 }, .Player2);
    _ = try game.place(.{ 4, 5 }, .Player2);
    try std.testing.expect(game.is_move_winning(.{ 7, 2 }));
}

test "is_move_winning detects No win (incomplete line)" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 2, 5 }, .Player1);
    _ = try game.place(.{ 3, 5 }, .Player1);
    _ = try game.place(.{ 4, 5 }, .Player1);
    _ = try game.place(.{ 5, 5 }, .Player1);
    try std.testing.expect(!game.is_move_winning(.{ 5, 5 }));
}

test "is_move_winning does not crash on near border check" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 0, 1 }, .Player1);
    _ = try game.place(.{ 1, 2 }, .Player1);
    _ = try game.place(.{ 2, 3 }, .Player1);
    _ = try game.place(.{ 3, 4 }, .Player1);
    _ = try game.place(.{ 4, 5 }, .Player1);
    try std.testing.expect(game.is_move_winning(.{ 1, 2 }));
}

test "is_move_winning winning move at negative extremity" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 0, 0 }, .Player1);
    _ = try game.place(.{ 1, 0 }, .Player1);
    _ = try game.place(.{ 2, 0 }, .Player1);
    _ = try game.place(.{ 3, 0 }, .Player1);
    _ = try game.place(.{ 4, 0 }, .Player1);
    try std.testing.expect(game.is_move_winning(.{ 4, 0 }));
}

test "is_move_winning winning move at postive extremity" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 0, 0 }, .Player1);
    _ = try game.place(.{ 1, 0 }, .Player1);
    _ = try game.place(.{ 2, 0 }, .Player1);
    _ = try game.place(.{ 3, 0 }, .Player1);
    _ = try game.place(.{ 4, 0 }, .Player1);
    try std.testing.expect(game.is_move_winning(.{ 0, 0 }));
}

test "is_move_winning line broke with another player piece" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 1, 1 }, .Player1);
    _ = try game.place(.{ 2, 2 }, .Player1);
    _ = try game.place(.{ 3, 3 }, .Player1);
    _ = try game.place(.{ 4, 4 }, .Player2);
    _ = try game.place(.{ 5, 5 }, .Player1);
    _ = try game.place(.{ 6, 6 }, .Player1);
    try std.testing.expect(!game.is_move_winning(.{ 3, 3 }));
}

test "is_move_winning isolated piece within ennemy line" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 0, 1 }, .Player1);
    _ = try game.place(.{ 0, 2 }, .Player1);
    _ = try game.place(.{ 0, 3 }, .Player1);
    _ = try game.place(.{ 0, 4 }, .Player2);
    _ = try game.place(.{ 0, 5 }, .Player1);
    _ = try game.place(.{ 0, 6 }, .Player1);
    try std.testing.expect(!game.is_move_winning(.{ 0, 4 }));
}

test "is_move_winning intersection of 2 winning lines (Player 2 last move)" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 4, 1 }, .Player1);
    _ = try game.place(.{ 4, 2 }, .Player1);
    _ = try game.place(.{ 4, 3 }, .Player1);
    _ = try game.place(.{ 4, 5 }, .Player1);

    _ = try game.place(.{ 1, 4 }, .Player2);
    _ = try game.place(.{ 2, 4 }, .Player2);
    _ = try game.place(.{ 3, 4 }, .Player2);
    _ = try game.place(.{ 4, 4 }, .Player2);
    _ = try game.place(.{ 5, 4 }, .Player2);

    try std.testing.expect(game.is_move_winning(.{ 4, 4 }));
}

test "is_move_winning intersection of 2 winning lines (Player 1 last move)" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 4, 1 }, .Player1);
    _ = try game.place(.{ 4, 2 }, .Player1);
    _ = try game.place(.{ 4, 3 }, .Player1);
    _ = try game.place(.{ 4, 4 }, .Player1);
    _ = try game.place(.{ 4, 5 }, .Player1);

    _ = try game.place(.{ 1, 4 }, .Player2);
    _ = try game.place(.{ 2, 4 }, .Player2);
    _ = try game.place(.{ 3, 4 }, .Player2);
    _ = try game.place(.{ 5, 4 }, .Player2);

    try std.testing.expect(game.is_move_winning(.{ 4, 4 }));
}

test "places a valid move that doesn't win" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    const is_win = try game.place(.{ 5, 5 }, .Player1);
    try std.testing.expectEqual(false, is_win);
    try std.testing.expectEqual(CellState.Player1, game.at(.{ 5, 5 }));
}

test "places on a cell that is already taken" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 5, 5 }, .Player1);
    try std.testing.expectError(Error.AlreadyTaken, game.place(.{ 5, 5 }, .Player2));
}

test "places on a cell out of the game bounds" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    try std.testing.expectError(Error.OutOfBound, game.place(.{ 11, 11 }, .Player2));
}

test "places a move that leads to a win" {
    var game = try Game.init(10, std.testing.allocator);
    defer game.deinit();

    _ = try game.place(.{ 2, 5 }, .Player1);
    _ = try game.place(.{ 3, 5 }, .Player1);
    _ = try game.place(.{ 4, 5 }, .Player1);
    _ = try game.place(.{ 5, 5 }, .Player1);
    try std.testing.expect(try game.place(.{ 6, 5 }, .Player1));
}
