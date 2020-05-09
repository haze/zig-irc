const std = @import("std");
const irc = @import("irc");

// un comment for infinite error trace
// pub const io_mode = .evented;

fn on_privmsg(client: *irc.Client, msg: irc.Command.PrivMsg) void {
    if (std.ascii.eqlIgnoreCase(msg.text, "'ping")) {
        client.send_privmsg(msg.target, "ヽ(^o^)ρ ┳┻┳° σ(^o^)/") catch |err| {
            std.debug.warn("Failed sending pong message: {}\n", .{ err });
        };
    }
}

pub fn main() anyerror!void {
    var allocator = &std.heap.ArenaAllocator.init(std.heap.page_allocator).allocator;
    var client = try irc.Client.initHost(allocator, "irc.rizon.io", 6667, .{
        .user = .{
            .userName = "ping_bot",
            .realName = "ping_bot",
        },
        .nick = "hazebot",
        .auto_join_channels = &[_]irc.Client.AutoJoinChannelInfo{
            .{ .name = "#homescreen" },
            .{ .name = "#based" },
        },
    });
    defer client.deinit();

    try client.register(.PRIVMSG, on_privmsg);

    // this call is blocking
    try client.connect();
}
