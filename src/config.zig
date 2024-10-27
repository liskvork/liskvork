const std = @import("std");

const logz = @import("logz");
const ini = @import("ini");
const utils = @import("utils.zig");

// Add to this structure to automatically add to the config
pub const Config = struct {
    game_board_size: u32,
    game_timeout_match: u64,
    game_timeout_turn: u64,
    game_max_memory: u64,
    game_player1: []const u8,
    game_player2: []const u8,

    log_level: logz.Level,
    log_board_file: []const u8,
    log_board_color: bool,

    web_enable: bool,
    web_address: []const u8,
    web_port: u16,

    other_auto_start: bool,
    other_auto_close: bool,
};

pub const default_config = @embedFile("default_config.ini");

pub const ConfigError = error{
    UnknownKey,
    MissingKey,
    BadKey,
};

fn make_opt_struct(comptime in: type) type {
    if (@typeInfo(in) != .Struct) @compileError("Type must be a struct type.");
    var fields: [std.meta.fields(in).len]std.builtin.Type.StructField = undefined;
    for (std.meta.fields(in), 0..) |t, i| {
        const fieldType = @Type(.{ .Optional = .{ .child = t.type } });
        const fieldName: [:0]const u8 = t.name[0..];
        fields[i] = .{
            .name = fieldName,
            .type = fieldType,
            .default_value = &@as(fieldType, null),
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

const tmp_config = make_opt_struct(Config);

const ini_field = struct {
    const Self = @This();

    full_name: []const u8,
    value: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(section: ?[]const u8, kv: ini.KeyValue, allocator: std.mem.Allocator) !ini_field {
        const actual_section = section orelse "default";
        const len_total = actual_section.len + kv.key.len + 1; // +1 to account for the underscore in the final name
        const fname = try allocator.alloc(u8, len_total);
        _ = try std.fmt.bufPrint(fname, "{s}_{s}", .{ actual_section, kv.key });
        const fvalue = try allocator.dupe(u8, kv.value);
        return .{
            .allocator = allocator,
            .full_name = fname,
            .value = fvalue,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.full_name);
        self.allocator.free(self.value);
    }
};

fn map_opt_struct_to_struct(opt_stc: type, stc: type, from: *const opt_stc) !stc {
    var to: stc = undefined;
    inline for (std.meta.fields(opt_stc)) |f| {
        if (@typeInfo(f.type) != .Optional)
            @compileError("Field " ++ f.name ++ " from " ++ @typeName(opt_stc) ++ " has type " ++ @typeName(f.type) ++ " that is not optional");
        const target_type = @typeInfo(f.type).Optional.child;
        const current_target_type = @TypeOf(@field(to, f.name));
        if (target_type != current_target_type)
            @compileError("Field " ++ f.name ++ " has mismatched types " ++ @typeName(target_type) ++ " != " ++ @typeName(current_target_type));
        if (@field(from, f.name) == null) {
            logz.fatal().ctx("Missing key-value pair from config!").stringSafe("key", f.name).log();
            return error.MissingKey;
        }
        @field(to, f.name) = @field(from, f.name).?;
    }
    return to;
}

fn map_value(kv: ini_field, conf: *tmp_config, allocator: std.mem.Allocator) !void {
    inline for (std.meta.fields(@TypeOf(conf.*))) |f| {
        if (std.mem.eql(u8, f.name, kv.full_name)) {
            const target_type = @typeInfo(f.type).Optional.child;
            // Handle enums first
            if (@typeInfo(target_type) == .Enum) {
                if (std.meta.stringToEnum(target_type, kv.value)) |h| {
                    @field(conf, f.name) = h;
                    return;
                }
                logz.fatal().ctx("Couldn't map enum in config").string("key", kv.full_name).string("value", kv.value).log();
                return error.BadKey;
            }
            // Handle other types
            @field(conf, f.name) = switch (target_type) {
                u16, u32, u64, i16, i32, i64 => std.fmt.parseInt(target_type, kv.value, 0),
                []const u8 => if (kv.value.len == 0)
                    error.BadKey
                else
                    allocator.dupe(u8, kv.value),
                bool => blk: {
                    if (std.mem.eql(u8, kv.value, "true")) {
                        break :blk true;
                    } else if (std.mem.eql(u8, kv.value, "false")) {
                        break :blk false;
                    } else break :blk error.BadKey;
                },
                else => @compileError("You probably need to implement parsing for " ++ @typeName(target_type) ++ " :3"),
            } catch |e| {
                logz.fatal().ctx("Could not parse value from config!").stringSafe("key", f.name).string("value", kv.value).string("expected_type", @typeName(target_type)).log();
                return e;
            };
            return;
        }
    }
    logz.fatal().ctx("Unknown key in config!").string("key", kv.full_name).log();
    return ConfigError.UnknownKey;
}

pub fn parse(filepath: []const u8) !Config {
    std.fs.cwd().access(filepath, .{}) catch |e| {
        switch (e) {
            error.FileNotFound => {
                logz.warn().ctx("Config file not found! Creating...").string("filepath", filepath).log();
                const tmp = try std.fs.cwd().createFile(
                    filepath,
                    .{},
                );
                defer tmp.close();
                _ = try tmp.writeAll(default_config);
            },
            else => return e,
        }
    };
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    // That currently does read calls of size 1 for the whole parsing
    // Not really good but for now it is good
    // TODO: Patch this
    var parser = ini.parse(utils.allocator, file.reader(), ";#");
    defer parser.deinit();

    var current_section: ?[]const u8 = null;
    defer {
        if (current_section) |sec|
            utils.allocator.free(sec);
    }
    var fields = std.ArrayList(ini_field).init(utils.allocator);
    defer {
        for (fields.items) |f|
            f.deinit();
        fields.deinit();
    }
    var tmp: tmp_config = .{};
    while (try parser.next()) |record| {
        switch (record) {
            .section => |heading| {
                if (current_section) |sec|
                    utils.allocator.free(sec);
                current_section = try utils.allocator.dupe(u8, heading);
            },
            .property => |kv| try fields.append(try ini_field.init(current_section, kv, utils.allocator)),
            .enumeration => |_| @panic("No support for enumerations"),
        }
    }
    for (fields.items) |f|
        try map_value(f, &tmp, utils.allocator);
    return map_opt_struct_to_struct(tmp_config, Config, &tmp);
}

pub fn deinit_config(t: type, conf: *const t) void {
    inline for (std.meta.fields(@TypeOf(conf.*))) |f| {
        switch (f.type) {
            []const u8 => utils.allocator.free(@field(conf, f.name)),
            else => {},
        }
    }
}

test {
    std.testing.refAllDecls(@This());
}
