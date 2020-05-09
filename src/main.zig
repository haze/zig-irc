const std = @import("std");
const mem = std.mem;
const io = std.io;
const net = std.net;
const event = std.event;
const testing = std.testing;

// TODO(haze): Annotate error types

const CommandImpl = struct {
    name: []const u8,
    parse_function: fn ([]const u8, []const u8) Command.Error!Command,
};

const implemented_commands = generateImplementedCommands();
const max_user_len = 10;

fn generateImplementedCommands() []CommandImpl {
    const ty = @typeInfo(Command).Union;
    const fields = ty.fields;
    var commands: [fields.len]CommandImpl = undefined;

    inline for (fields) |field, i| {
        // @compileLog(field.name, field.field_type, field.enum_field.?.name, field.enum_field.?.value, i);
        commands[i] = CommandImpl{
            .name = field.name,
            .parse_function = blk: {
                inline for (comptime std.meta.declarations(Command)) |decl, di| {
                    // @compileLog(decl.name, decl.data);
                    if (comptime std.ascii.eqlIgnoreCase(decl.name, field.name)) {
                        // const command_struct = Vg
                        break :blk @field(@field(Command, @typeName(field.field_type)), "parse");
                    }
                }
                @compileError("'" ++ @typeName(Command) ++ "' has no declaration '" ++ field.name ++ "'");
            },
        };
    }
    return &commands;
}

// TODO(haze): implement the rest of these commands:

pub const CommandType = enum {
    NUM,
    NICK,
    USER,
    NOTICE,
    PING,
    PONG,
    JOIN,
    PRIVMSG,
};

pub const Command = union(CommandType) {
    pub const Error = error{InvalidCommand};
    pub const Notice = struct {
        target: []const u8,
        text: []const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            if (mem.indexOfScalar(u8, args, ' ')) |split| {
                return Command{
                    .NOTICE = .{
                        .target = mem.trim(u8, args[0..split], " "),
                        .text = mem.trim(u8, args[split..], " "),
                    },
                };
            }
            return error.InvalidCommand;
        }
    };

    pub const Num = struct {
        // generic command, can't parse into anything more concise
        args: []const u8,
        number: u10,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            return Command{
                .NUM = .{
                    .args = args,
                    .number = std.fmt.parseInt(u10, cmd, 10) catch return error.InvalidCommand,
                },
            };
        }
    };

    pub const User = struct {
        userName: []const u8,
        realName: []const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            return error.InvalidCommand;
        }
    };

    // NICK <nickname>
    pub const Nick = struct {
        nick: []const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            return Command{
                .NICK = .{ .nick = args },
            };
        }
    };

    // PING :3672912195
    // PONG :3672912195

    pub const Ping = struct {
        server: []const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            return Command{
                .PING = .{ .server = args },
            };
        }
    };

    pub const Pong = struct {
        server: []const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            return Command{
                .PONG = .{ .server = args },
            };
        }
    };

    pub const Join = struct {
        channels: []const u8,
        keys: ?[]const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            return Command{
                .JOIN = .{
                    .channels = args,
                    .keys = if (mem.indexOfScalar(u8, args, ' ')) |sep_idx| args[sep_idx..] else null,
                },
            };
        }
    };

    pub const PrivMsg = struct {
        target: []const u8,
        text: []const u8,

        fn parse(cmd: []const u8, args: []const u8) Command.Error!Command {
            if (mem.indexOfScalar(u8, args, ':')) |sep_idx| {
                return Command{
                    .PRIVMSG = .{
                        .target = mem.trim(u8, args[0..sep_idx], " "),
                        .text = args[sep_idx+1..],
                    },
                };
            } else return error.InvalidCommand;
        }
    };

    // NOTE: Num must always be the FIRST union tag.
    NUM: Num,
    NICK: Nick,
    USER: User,
    NOTICE: Notice,
    PING: Ping,
    PONG: Pong,
    JOIN: Join,
    PRIVMSG: PrivMsg,

    fn parse(line: []const u8) !Command {
        const sender: ?[]const u8 = Command.parseSender(line);
        // skip : if sender is found
        const command_start = if (sender) |s| s.len + 1 else 0;
        const command_str = mem.trimLeft(u8, line[command_start..], " ");
        const command: CommandImpl = Command.parseCommand(command_str) orelse return error.CommandNotFound;
        const args = line[command_start + command.name.len + 1 ..];
        return @call(.{}, command.parse_function, .{ command_str[0..command.name.len], args });
    }

    fn parseSender(line: []const u8) ?[]const u8 {
        // check if a message has a sender
        if (line[0] == ':') {
            if (mem.indexOfScalar(u8, line, ' ')) |split| {
                return line[1..split];
            }
        }
        return null;
    }

    fn parseCommand(line: []const u8) ?CommandImpl {
        inline for (implemented_commands) |command| {
            if (mem.startsWith(u8, line, command.name)) {
                return command;
            }
        }
        // might be numeric, let's check
        const first_is_numeric = std.ascii.isDigit(line[0]);
        const second_is_numeric = std.ascii.isDigit(line[1]);
        const third_is_numeric = std.ascii.isDigit(line[2]);
        if (first_is_numeric and second_is_numeric and third_is_numeric) {
            return implemented_commands[0];
        }
        std.debug.warn("missing command: {}\n", .{ line });
        return null;
    }

    pub fn format(
        self: Command,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: var,
    ) !void {
        switch (self) {
            .NICK => |nick| try std.fmt.format(out_stream, "NICK {}", .{nick.nick}),
            .USER => |user| try std.fmt.format(out_stream, "USER {} 0 * {}", .{ user.userName, user.realName }),
            .PING => |ping| try std.fmt.format(out_stream, "PING {}", .{ping.server}),
            .PONG => |pong| try std.fmt.format(out_stream, "PONG {}", .{pong.server}),
            .JOIN => |join| {
                try std.fmt.format(out_stream, "JOIN {}", .{join.channels});
                if (join.keys) |keys| {
                    try std.fmt.format(out_stream, "{}", .{keys});
                }
            },
            .NOTICE => |not| try std.fmt.format(out_stream, "NOTICE {} :{}", .{ not.target, not.text }),
            .PRIVMSG => |msg| try std.fmt.format(out_stream, "PRIVMSG {} :{}", .{ msg.target, msg.text }),
            else => {},
        }
    }
};

pub const Client = struct {
    const Self = @This();
    const SendQueue = event.Channel(Command);

    pub const AutoJoinChannelInfo = struct {
        name: []const u8,
        key: ?[]const u8 = null,
    };

    pub const InitOptions = struct {
        auto_join_channels: []const AutoJoinChannelInfo = &[_]AutoJoinChannelInfo{},
        user: Command.User,
        nick: []const u8,
    };

    allocator: *mem.Allocator,
    server: net.Address,

    send_queue: SendQueue,
    send_thread_handle: ?*std.Thread = null,

    out_stream: ?io.OutStream(std.fs.File, std.os.WriteError, std.fs.File.write) = null,
    init_options: InitOptions,
    event_map: std.ArrayList(CommandType),

    // Event Handlers
    privmsg_handlers: std.ArrayList(fn (*Self, Command.PrivMsg) void),

    pub fn init(allocator: *mem.Allocator, server: net.Address, options: InitOptions) Self {
        var send_queue_chan: SendQueue = undefined;
        send_queue_chan.init(&[0]Command{});
        const inst = Self{
            .allocator = allocator,
            .server = server,
            .send_queue = send_queue_chan,
            .init_options = options,
            .event_map = std.ArrayList(CommandType).init(allocator),

            // Event Handlers
            .privmsg_handlers = std.ArrayList(fn (*Self, Command.PrivMsg) void).init(allocator),
        };
        return inst;
    }

    pub fn initHost(allocator: *mem.Allocator, server: []const u8, port: u16, options: InitOptions) !Self {
        const list = try net.getAddressList(allocator, server, port);
        defer list.deinit();

        if (list.addrs.len == 0) return error.UnknownHostName;
        return Self.init(allocator, list.addrs[0], options);
    }

    fn send(self: *Self, command: Command) !void {
        if (self.out_stream) |stream| {
            try stream.print("{}\r\n", .{ command });
        } else {
            std.debug.warn("Tried to send a command without a valid out stream!", .{});
        }
    }

    pub fn connect(self: *Self) !void {
        const socket = try net.tcpConnectToAddress(self.server);
        const socket_in_stream = io.bufferedInStream(socket.inStream()).inStream();
        const socket_out_stream = socket.outStream();
        self.out_stream = socket_out_stream;
        // Send auth
        try self.send(.{ .USER = self.init_options.user });
        try self.send(.{ .NICK = .{ .nick = self.init_options.nick } });
        while (true) {
            const line = mem.trimRight(u8, socket_in_stream.readUntilDelimiterAlloc(self.allocator, '\n', 4096) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            }, "\r\n");
            if (Command.parse(line)) |cmd| {
                try self.handleInternalCommand(cmd);
                self.dispatchCommandToHandlers(cmd);
            } else |err| switch (err) {
                else => std.debug.warn("cmd parse err: {}\n", .{err}),
            }
        }
    }

    fn dispatchCommandToHandlers(self: *Self, command: Command) void {
        switch (command)  {
            .PRIVMSG => |privmsg| for (self.privmsg_handlers.items) |handler| handler(self, privmsg),
            else => {},
        }
    }

    fn handleInternalCommand(self: *Self, command: Command) !void {
        switch (command) {
            .PING => |ping| try self.send(.{ .PONG = .{ .server = ping.server } }),
            .NUM => |numeric| {
                if (numeric.number == 001) {
                    for (self.init_options.auto_join_channels) |channel| {
                        try self.send(Command{
                            .JOIN = .{
                                .channels = channel.name,
                                .keys = channel.key,
                            },
                        });
                    }
                }
            },
            else => {},
        }
    }

    pub fn deinit(self: Self) void {
        self.event_map.deinit();
        self.privmsg_handlers.deinit();
    }

    // HELPER METHODS
    pub fn send_privmsg(self: *Self, target: []const u8, text: []const u8) !void {
        std.debug.warn("Trying to send text: [{}] to {}\n", .{ text, target });
        try self.send(Command{ .PRIVMSG = .{ .target = target, .text = text }});
        std.debug.warn("Finished sending\n", .{});
    }

    pub fn register(self: *Self, commandType: CommandType, handler: fn (*Self, Command.PrivMsg) void) !void {
        try switch (commandType) {
            .PRIVMSG => self.privmsg_handlers.append(handler),
            else => return error.UnsupportedRegister,
        };
    }
};
