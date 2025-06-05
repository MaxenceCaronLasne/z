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
