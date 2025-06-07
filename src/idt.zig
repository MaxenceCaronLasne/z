const InterruptError = error{
    AlreadyPresent,
    OutOfRange,
};

const InterruptGate = packed struct(u64) {
    offset_low: u16,
    segment_selector: u16,
    reserved_zero: u8 = 0,
    tag: u3 = 0b110,
    size: Size = Size.Size32,
    privilege_level: u2 = 0,
    is_present: bool = true,
    offset_high: u16,

    const Size = enum(u2) {
        Size16 = 0b00,
        Size32 = 0b01,
    };

    pub fn Zero() InterruptGate {
        return @as(InterruptGate, @bitCast(@as(u64, 0x0)));
    }

    pub fn Make(
        offset: u32,
        comptime segment_selector: u16,
        comptime privilege_level: u2,
    ) InterruptGate {
        return InterruptGate{
            .offset_low = @truncate(offset),
            .segment_selector = segment_selector,
            .privilege_level = privilege_level,
            .offset_high = @truncate(offset >> 16),
        };
    }
};

const numberOfEntries = 256;
var IDT: [numberOfEntries]InterruptGate = [_]InterruptGate{
    InterruptGate.Zero(),
} ** numberOfEntries;

const IdtPtr = packed struct {
    limit: u16,
    base: u32,
};

var idtPtr = IdtPtr{
    .limit = @sizeOf(InterruptGate) * numberOfEntries - 1,
    .base = undefined,
};

pub const InterruptHandler = fn () callconv(.naked) void;

pub const Interrupt = struct {
    pub fn addInterruptGate(_: *@This(), index: usize, handler: InterruptHandler) InterruptError!void {
        if (index >= numberOfEntries) {
            return InterruptError.OutOfRange;
        }

        if (IDT[index].is_present) {
            return InterruptError.AlreadyPresent;
        }

        const segment_selector = 1 * 8;

        IDT[index] = InterruptGate.Make(
            @intFromPtr(&handler),
            segment_selector,
            0,
        );
    }

    pub fn removeInterruptGate(index: usize) void {
        IDT[index] = InterruptGate.Zero();
    }
};

pub fn init() Interrupt {
    idtPtr.base = @intFromPtr(&IDT);

    asm volatile ("lidt (%[idt_ptr])"
        :
        : [idt_ptr] "r" (&idtPtr),
        : "memory"
    );

    return Interrupt{};
}
