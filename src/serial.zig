const arch = @import("./arch.zig");
const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;

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

    fn transmitIsEmpty(self: SerialPort) bool {
        const lsr: LSR = @bitCast(arch.in(u8, @intFromEnum(self.port) + LSR.portOffset));
        return lsr.is_transmitter_holding_register_empty;
    }

    fn putc(self: SerialPort, char: u8) void {
        var retries: u32 = 10000;
        while (!self.transmitIsEmpty() and retries > 0) : (retries -= 1) {
            arch.halt();
        }
        if (retries <= 0) {
            return;
        }

        arch.out(@intFromEnum(self.port), char);
    }

    pub fn write(self: SerialPort, string: [:0]const u8) void {
        for (string) |c| {
            self.putc(c);
        }
    }

    pub fn writeBytes(self: SerialPort, bytes: []const u8) void {
        for (bytes) |c| {
            self.putc(c);
        }
    }

    pub fn writeChar(self: SerialPort, char: u8) void {
        self.putc(char);
    }

    fn writerCallback(self: *SerialPort, string: []const u8) error{}!usize {
        self.writeBytes(string);
        return string.len;
    }

    pub fn writer(self: *SerialPort) Writer(*SerialPort, error{}, writerCallback) {
        return Writer(*SerialPort, error{}, writerCallback){ .context = self };
    }

    pub fn printf(self: *SerialPort, comptime format: []const u8, args: anytype) void {
        fmt.format(self.writer(), format, args) catch unreachable;
    }
};

pub fn init(baud: u32, port: Port) SerialError!SerialPort {
    if (baud > BAUD_MAX) return SerialError.InvalidBaudRate;

    const divisor = 115200 / baud;
    if (divisor == 0) return SerialError.InvalidBaudRate;

    const port_int = @intFromEnum(port);

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
