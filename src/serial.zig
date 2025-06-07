const arch = @import("./arch.zig");

pub const SerialError = error{
    InvalidBaudRate,
};

pub const Port = enum(u16) {
    COM1 = 0x3F8,
    COM2 = 0x2F8,
    COM3 = 0x3E8,
    COM4 = 0x2E8,
};

const BAUD_MAX = 115200;

const LCR = packed struct(u8) {
    word_length: WordLength = .EightBits,
    stop_bits: StopBits = .OneStopBit,
    parity_select: Parity = .None,
    is_break_enabled: bool = false,
    is_divisor_latch_access: bool = false,

    const portOffset: u16 = 3;

    const WordLength = enum(u2) {
        FiveBits = 0b00,
        SixBits = 0b01,
        SevenBits = 0b10,
        EightBits = 0b11,
    };

    const StopBits = enum(u1) {
        OneStopBit = 0b0,
        TwoStopBits = 0b1,
    };

    const Parity = enum(u3) {
        None = 0b000,
        Odd = 0b001,
        Even = 0b011,
        Mark = 0b101,
        Space = 0b111,
    };
};

const LSR = packed struct(u8) {
    is_data_ready: bool,
    is_overrun_error: bool,
    is_parity_error: bool,
    is_framing_error: bool,
    is_break_interrupt: bool,
    is_transmitter_holding_register_empty: bool,
    is_data_holding_registers_empty: bool,
    is_error_in_received_fifo: bool,

    const portOffset: u16 = 5;
};

pub const SerialPort = struct {
    port: Port,

    fn transmitIsEmpty(self: *const SerialPort) bool {
        const lsr: LSR = @bitCast(arch.in(u8, @intFromEnum(self.port) + LSR.portOffset));
        return lsr.is_transmitter_holding_register_empty;
    }

    fn putc(self: *const SerialPort, char: u8) void {
        while (!self.transmitIsEmpty()) {
            arch.halt();
        }
        arch.out(@intFromEnum(self.port), char);
    }

    pub fn write(self: *const SerialPort, string: [:0]const u8) void {
        for (string) |c| {
            self.putc(c);
        }
    }

    // Write a slice of bytes (without null termination requirement)
    pub fn writeBytes(self: *const SerialPort, bytes: []const u8) void {
        for (bytes) |c| {
            self.putc(c);
        }
    }

    // Write a single character
    pub fn writeChar(self: *const SerialPort, char: u8) void {
        self.putc(char);
    }

    // Format and write an unsigned integer
    fn writeUint(self: *const SerialPort, value: u64, base: u8) void {
        if (value == 0) {
            self.putc('0');
            return;
        }

        var buffer: [64]u8 = undefined;
        var len: usize = 0;
        var val = value;

        const digits = "0123456789abcdef";
        while (val > 0) {
            buffer[len] = digits[@as(usize, @intCast(val % base))];
            val /= base;
            len += 1;
        }

        // Reverse the buffer and write
        var i: usize = len;
        while (i > 0) {
            i -= 1;
            self.putc(buffer[i]);
        }
    }

    // Format and write a signed integer
    fn writeInt(self: *const SerialPort, value: i64, base: u8) void {
        if (value < 0) {
            self.putc('-');
            self.writeUint(@as(u64, @intCast(-value)), base);
        } else {
            self.writeUint(@as(u64, @intCast(value)), base);
        }
    }

    // Format and write a pointer
    fn writePointer(self: *const SerialPort, ptr: anytype) void {
        const addr = @intFromPtr(ptr);
        self.writeBytes("0x");
        self.writeUint(addr, 16);
    }

    // Format and write a boolean
    fn writeBool(self: *const SerialPort, value: bool) void {
        if (value) {
            self.writeBytes("true");
        } else {
            self.writeBytes("false");
        }
    }

    // Helper function to format a single argument
    fn formatArg(self: *const SerialPort, arg: anytype, format_type: enum { default, hex, decimal }) void {
        const T = @TypeOf(arg);
        switch (@typeInfo(T)) {
            .int => |int_info| {
                switch (format_type) {
                    .hex => self.writeUint(@as(u64, @intCast(arg)), 16),
                    else => {
                        if (int_info.signedness == .signed) {
                            self.writeInt(@as(i64, arg), 10);
                        } else {
                            self.writeUint(@as(u64, arg), 10);
                        }
                    },
                }
            },
            .bool => self.writeBool(arg),
            .pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .slice => {
                        if (ptr_info.child == u8) {
                            self.writeBytes(arg);
                        } else {
                            self.writePointer(arg.ptr);
                        }
                    },
                    .many, .one => {
                        if (ptr_info.child == u8 and ptr_info.sentinel != null) {
                            // Null-terminated string
                            var i: usize = 0;
                            while (arg[i] != 0) : (i += 1) {
                                self.putc(arg[i]);
                            }
                        } else {
                            self.writePointer(arg);
                        }
                    },
                    else => self.writePointer(arg),
                }
            },
            .array => |array_info| {
                if (array_info.child == u8) {
                    self.writeBytes(&arg);
                } else {
                    self.writePointer(&arg);
                }
            },
            .optional => {
                if (arg) |value| {
                    self.formatArg(value, format_type);
                } else {
                    self.writeBytes("null");
                }
            },
            .comptime_int => {
                switch (format_type) {
                    .hex => self.writeUint(@as(u64, @intCast(arg)), 16),
                    else => self.writeUint(@as(u64, @intCast(arg)), 10),
                }
            },
            .@"enum" => {
                // For enums, try to print their integer value
                self.writeUint(@as(u64, @intCast(@intFromEnum(arg))), 10);
            },
            else => self.writeBytes("(unknown)"),
        }
    }

    /// Print formatted output to the serial port, similar to std.debug.print
    /// but designed for kernel environments without standard library dependencies.
    ///
    /// Supported format specifiers:
    /// - `{}` - Default format for the argument type
    /// - `{d}` - Decimal format (for integers)
    /// - `{x}` - Hexadecimal format (for integers)
    ///
    /// Supported argument types:
    /// - Integers (signed/unsigned, any size) - printed in decimal by default
    /// - Booleans - printed as "true" or "false"
    /// - Strings (null-terminated or slices) - printed as-is
    /// - Pointers - printed as hexadecimal addresses with 0x prefix
    /// - Arrays of u8 - printed as strings
    /// - Optionals - unwrapped and printed, or "null" if none
    /// - Enums - printed as their integer value
    ///
    /// Example usage:
    /// ```zig
    /// sp.print("Hello, {}!\r\n", .{"world"});
    /// sp.print("Value: {}, Hex: 0x{x}\r\n", .{42, 42});
    /// sp.print("Address: 0x{x}\r\n", .{@intFromPtr(&some_var)});
    /// ```
    pub fn print(self: *const SerialPort, comptime fmt: []const u8, args: anytype) void {
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);

        if (args_type_info != .@"struct") {
            @compileError("Expected tuple or struct argument");
        }

        const fields_info = args_type_info.@"struct".fields;

        comptime var arg_index: usize = 0;
        comptime var i: usize = 0;

        inline while (i < fmt.len) {
            if (fmt[i] == '{' and i + 1 < fmt.len) {
                if (fmt[i + 1] == '}') {
                    // Simple {} placeholder
                    if (arg_index < fields_info.len) {
                        const arg_value = @field(args, fields_info[arg_index].name);
                        self.formatArg(arg_value, .default);
                        arg_index += 1;
                    }
                    i += 2;
                } else if (fmt[i + 1] == 'x' and i + 2 < fmt.len and fmt[i + 2] == '}') {
                    // Hexadecimal format {x}
                    if (arg_index < fields_info.len) {
                        const arg_value = @field(args, fields_info[arg_index].name);
                        self.formatArg(arg_value, .hex);
                        arg_index += 1;
                    }
                    i += 3;
                } else if (fmt[i + 1] == 'd' and i + 2 < fmt.len and fmt[i + 2] == '}') {
                    // Decimal format {d}
                    if (arg_index < fields_info.len) {
                        const arg_value = @field(args, fields_info[arg_index].name);
                        self.formatArg(arg_value, .decimal);
                        arg_index += 1;
                    }
                    i += 3;
                } else {
                    // Not a recognized format, just output the character
                    self.putc(fmt[i]);
                    i += 1;
                }
            } else {
                self.putc(fmt[i]);
                i += 1;
            }
        }
    }
};

pub fn init(baud: u32, port: Port) SerialError!SerialPort {
    if (baud > BAUD_MAX) return SerialError.InvalidBaudRate;

    const divisor = 115200 / baud;
    if (divisor == 0) return SerialError.InvalidBaudRate;

    const port_int = @intFromEnum(port);

    // Set baud divisor
    arch.out(
        port_int + LCR.portOffset,
        @as(u8, @bitCast(LCR{
            .is_divisor_latch_access = true,
        })),
    );
    arch.out(port_int, @as(u8, @truncate(divisor)));
    arch.out(port_int + 1, @as(u8, @truncate(divisor >> 8)));

    // Configure LCR
    arch.out(port_int + LCR.portOffset, @as(u8, @bitCast(LCR{})));
    arch.out(port_int + 1, @as(u8, 0x0));

    return SerialPort{ .port = port };
}

pub fn attach(port: Port) SerialPort {
    return SerialPort{ .port = port };
}
