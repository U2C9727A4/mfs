const std = @import("std");

const mfs_msg = struct {
    psize: u32 = 0,
    dsize: u32 = 0,
    op: u8 = 0,

    path: []const u8 = undefined,
    data: []const u8 = undefined,
};

const mfs_file = struct {
    path: []const u8 = undefined,

    write_callback: *const fn (std.mem.Allocator, mfs_msg, std.net.Stream) void,
    read_callback: *const fn (std.mem.Allocator, mfs_msg, std.net.Stream) void,
};


// Reads an MFS message, data and path fields are heap-allocated, must free by caller.
fn readMfsMessage(allocator: std.mem.Allocator, stream: std.net.Stream) !mfs_msg {
    // First read the fixed-size stuff
    var buffer: [9]u8 = undefined;

    if (try stream.read(&buffer) != buffer.len) return error.UnexpectedRead;
    const pathSize = std.mem.readInt(u32, buffer[0..4], .little);
    const dataSize = std.mem.readInt(u32, buffer[4..8], .little);
    const operation = std.mem.readInt(u8, buffer[8..9], .little);


    const path = try allocator.alloc(u8, pathSize);
    const data = try allocator.alloc(u8, dataSize);

    const pathBytes = try stream.read(path);
    const dataBytes = try stream.read(data);

    if (dataBytes != dataSize) return error.wrongDataLen;
    if (pathBytes != pathSize) return error.wrongPathLen;


    return mfs_msg{
        .data = data,
        .dsize = dataSize,

        .path = path,
        .psize = pathSize,

        .op = operation,
    };
}

// sends an MFS message.
fn sendMfsMessage(stream: std.net.Stream, msg: mfs_msg) !void  {
    var buf: [4]u8 = undefined;
    var buf2: [1]u8 = undefined;

    std.mem.writeInt(u32, &buf, msg.psize, .little);
    if (try stream.write(&buf) != buf.len) return error.UnexpectedWrite;

    std.mem.writeInt(u32, &buf, msg.dsize, .little);
    if (try stream.write(&buf) != buf.len) return error.UnexpectedWrite;

    std.mem.writeInt(u8, &buf2, msg.op, .little);
    if (try stream.write(&buf2) != buf2.len) return error.UnexpectedWrite;

    if (try stream.write(msg.path) != msg.psize) return error.UnexpectedWrite;
    if (try stream.write(msg.data) != msg.dsize) return error.UnexpectedWrite;
}

// Sends the counterpart error response of the msg.
fn sendMfsError(stream: std.net.Stream, msg: mfs_msg, error_code: u16 ) !void {
    var buffer: [2]u8 = undefined;
    std.mem.writeInt(u16, buffer[0..], error_code, .little);

    const response = mfs_msg{
        .data = &buffer,
        .dsize = 2,

        .path = msg.path,
        .psize = msg.psize,

        .op = 0b10000101,
    };

    return sendMfsMessage(stream, response);
}

// Adds the file, If the path is not unique to the file, it fails.
fn addFile(file: mfs_file, fileList: std.ArrayList(mfs_file)) !void {
    for (fileList.items) |file2| {
        if (std.mem.eql(u8, file2.path, file.path)) return error.pathNotUnique;
    }
    try fileList.append(file);
}

fn helloWriter(allocator: std.mem.Allocator, msg: mfs_msg, stream: std.net.Stream) void {
    // We get the request to write to file, but we discard the writes, while we say it has success.
    _ = allocator;
    var buf: [4]u8 = .{0, 0, 0, 0};
    std.mem.writeInt(u32, buf[0..], msg.dsize, .little);

    const response = mfs_msg{
      .data = buf[0..],
      .dsize = 4,
      .path = msg.path,
      .psize = msg.psize,

      .op = msg.op | 0x80,
    };
    sendMfsMessage(stream, response) catch |err| {
        std.debug.print("ERROR: {!}\n", .{err});
    };
}


fn helloReader(allocator: std.mem.Allocator, msg: mfs_msg, stream: std.net.Stream) void {
    // We get the request to write to file, but we discard the writes, while we say it has success.
    _ = allocator;
    const buf: [7]u8 = .{'h', 'e', 'l', 'l', 'o', '!', '\n'};

    const response = mfs_msg{
        .data = buf[0..],
        .dsize = 7,
        .path = msg.path,
        .psize = msg.psize,

        .op = msg.op | 0x80,
    };
    sendMfsMessage(stream, response) catch |err| {
        std.debug.print("ERROR: {!}\n", .{err});
    };
}

fn listFiles(stream: std.net.Stream, files: std.ArrayList(mfs_file)) !void {
    var paths = std.ArrayList(u8).init(files.allocator);
    defer paths.deinit();

    for (files.items) |file| {
        try paths.appendSlice(file.path);
        try paths.append('\n');
    }

    const response = mfs_msg{
        .data = paths.items,
        .dsize = @truncate(paths.items.len),

        .path = &[_]u8{},
        .psize = 0,
        .op = 3 | 0x80,
    };

    try sendMfsMessage(stream, response);
}

// Finds file in the files index (by path).
inline fn findFile(files: std.ArrayList(mfs_file), path: []const u8) ?mfs_file {
    for (files.items) |file| {
        if (std.mem.eql(u8, file.path, path)) return file;
    }
    return null;
}


pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var files = std.ArrayList(mfs_file).init(allocator);
    defer files.deinit();

    const helloFile = mfs_file{
        .path = "/hello",

        .write_callback = &helloWriter,
        .read_callback = &helloReader,
    };

    try files.append(helloFile);
    const address = try std.net.Address.parseIp4("0.0.0.0", 1233);
    var server = try address.listen(.{});
    defer server.deinit();

    // Listen for requests, and forward valid files ones and ls.
    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();
        const request = readMfsMessage(allocator, connection.stream) catch |err| {
            std.debug.print("ERROR: {!}\n", .{err});
            var buffer: [2]u8 = undefined;
            const fakePath: [1]u8 = .{'/'};
            std.mem.writeInt(u16, buffer[0..], 100, .little);

            const errorResponse = mfs_msg{
              .data = buffer[0..],
              .dsize = 2,
              .op = 5 | 0x80,

              .path = fakePath[0..],
              .psize = 1,
            };
            try sendMfsMessage(connection.stream, errorResponse);
            continue;
        };
        defer {
            allocator.free(request.path);
            allocator.free(request.data);
        }


        switch (request.op) {
            1 => {
                // Read operation.
                const file = findFile(files, request.path) orelse {
                    try sendMfsError(connection.stream, request, 0);
                    continue;
                };
                @call(.auto, file.read_callback, .{ allocator, request, connection.stream});
            },

            2 => {
                // Write operation
                const file = findFile(files, request.path) orelse {
                    try sendMfsError(connection.stream, request, 0);
                    continue;
                };
                @call(.auto, file.write_callback, .{ allocator, request, connection.stream});
            },

            3 => {
                // ls operation.
                listFiles(connection.stream, files) catch |err| {
                    std.debug.print("ERROR: {!}\n", .{err});
                    try sendMfsError(connection.stream, request, 1);
                };
            },

            0 => {}, // this is a no-op.
            else => {
                std.debug.print("Illegal Operation.\n", .{});
                try sendMfsError(connection.stream, request, 102);
            },
        }
    }
}


