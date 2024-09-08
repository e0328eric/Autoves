const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const process = std.process;
const time = std.time;

const c = @cImport({
    @cInclude("signal.h");
});

const win = if (builtin.os.tag == .windows) @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", {});
    @cInclude("Windows.h");
}) else {};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Zlap = @import("zlap").Zlap;

const LatexType = enum(u2) {
    Plain,
    PdfLatex,
    XeLatex,
    LuaLatex,
};

pub fn main() !void {
    _ = c.signal(c.SIGINT, &signalHandler);

    const allocator = std.heap.page_allocator;

    var zlap = try Zlap.init(allocator, @embedFile("./command.json"));
    defer zlap.deinit();

    if (zlap.is_help) {
        std.debug.print("{s}\n", .{zlap.help_msg});
        return;
    }

    const filename = zlap.main_args.get("FILE").?.value.string;
    const latex_type = getLatexType(&zlap);

    const stdout = std.io.getStdOut();
    var first_run = true;
    var prev_file_modified = time.nanoTimestamp();

    while (true) {
        const file_stat = fs.cwd().statFile(filename) catch |err| {
            if (builtin.os.tag == .windows) {
                _ = win.MessageBoxA(
                    null,
                    "autoves error occurs. See the console for more information",
                    "autoves error",
                    win.MB_ICONERROR | win.MB_OK,
                );
            }
            return err;
        };
        const file_modified = file_stat.mtime;

        if (first_run or file_modified > prev_file_modified) {
            const argv = try makeVestiArgv(
                allocator,
                filename,
                latex_type,
            );
            defer argv.deinit();

            const result = try process.Child.run(.{
                .allocator = allocator,
                .argv = argv.items,
            });

            if (result.term.Exited != 0) {
                var err_msg = try ArrayList(u8).initCapacity(allocator, 100);
                defer err_msg.deinit();

                try err_msg.writer().print(
                    "vesti compilation failed.\n[stdout]\n{s}\n[stderr]\n{s}\n",
                    .{ result.stdout, result.stderr },
                );

                if (builtin.os.tag == .windows) {
                    const err_msg_z = try allocator.dupeZ(u8, err_msg.items);
                    defer allocator.free(err_msg_z);

                    _ = win.MessageBoxA(
                        null,
                        err_msg_z,
                        "autoves warning",
                        win.MB_ICONWARNING | win.MB_OK,
                    );
                } else {
                    std.debug.print("{s}", .{err_msg.items});
                }
            }

            first_run = false;
            prev_file_modified = file_modified;

            try stdout.writeAll("Press Ctrl+C to exit...\n");
        }

        std.time.sleep(std.time.ns_per_ms * 300);
    }
}

fn signalHandler(signal: c_int) callconv(.C) noreturn {
    _ = signal;

    std.debug.print("exit autoves...\n", .{});
    std.process.exit(0);
}

fn getLatexType(zlap: *const Zlap) LatexType {
    const is_plain = zlap.main_flags.get("latex").?.value.bool;
    const is_pdf = zlap.main_flags.get("pdf").?.value.bool;
    const is_xe = zlap.main_flags.get("xe").?.value.bool;
    const is_lua = zlap.main_flags.get("lua").?.value.bool;

    return if (is_plain)
        LatexType.Plain
    else if (is_pdf)
        LatexType.PdfLatex
    else if (is_xe)
        LatexType.XeLatex
    else if (is_lua)
        LatexType.LuaLatex
    else // TODO: There is a plan to make a configure file to change this constant
        LatexType.PdfLatex;
}

fn makeVestiArgv(
    allocator: Allocator,
    filename: []const u8,
    latex_type: LatexType,
) !ArrayList([]const u8) {
    var output = try ArrayList([]const u8).initCapacity(allocator, 10);
    errdefer output.deinit();

    try output.append("vesti");
    try output.append("compile");

    if (builtin.os.tag == .windows) {
        try output.append("-N");
    }

    switch (latex_type) {
        .Plain => try output.append("-L"),
        .PdfLatex => try output.append("-p"),
        .XeLatex => try output.append("-x"),
        .LuaLatex => try output.append("-l"),
    }

    try output.append(filename);

    return output;
}
