const arch = @import("./arch.zig");

const GDT: [3]SegmentDescriptor = .{
    // Null descriptor - must be all zeros
    SegmentDescriptor{
        .limit_low = 0,
        .base_address_low = 0,
        .segment_type = SegmentDescriptor.SegmentType.ReadOnly,
        .descriptor_type = SegmentDescriptor.DescriptorType.System,
        .privilege_level = 0,
        .is_present = false,
        .limit_high = 0,
        .reserved_zero = 0,
        .default_operation_size = SegmentDescriptor.OperationSize.Seg16Bits,
        .granularity = 0,
        .base_address_high = 0,
    },
    SegmentDescriptor.build(
        0,
        0xFFFFF,
        SegmentDescriptor.SegmentType.ExecuteRead,
        0,
    ),
    SegmentDescriptor.build(
        0,
        0xFFFFF,
        SegmentDescriptor.SegmentType.ReadWrite,
        0,
    ),
};

const SegmentDescriptor = packed struct(u64) {
    limit_low: u16,
    base_address_low: u24,
    segment_type: SegmentType,
    descriptor_type: DescriptorType = DescriptorType.CodeOrData,
    privilege_level: u2,
    is_present: bool = true,
    limit_high: u4,
    reserved_zero: u1 = 0,
    default_operation_size: OperationSize = OperationSize.Seg32Bits,
    granularity: u1 = 1,
    base_address_high: u8,

    fn build(
        base: u32,
        limit: u20,
        segment_type: SegmentType,
        privilege_level: u2,
    ) SegmentDescriptor {
        return SegmentDescriptor{
            .limit_low = @truncate(limit),
            .limit_high = @truncate(limit >> 16),
            .base_address_low = @truncate(base),
            .base_address_high = @truncate(base >> 24),
            .segment_type = segment_type,
            .privilege_level = privilege_level,
        };
    }

    const SegmentType = enum(u4) {
        ReadOnly = 0,
        ReadOnlyAccessed,
        ReadWrite,
        ReadWriteAccessed,
        ReadOnlyExpandDown,
        ReadOnlyExpandDownAccessed,
        ReadWriteExpandDown,
        ReadWriteExpandDownAccessed,
        ExecuteOnly,
        ExecuteOnlyAccessed,
        ExecuteRead,
        ExecuteReadAccessed,
        ExecuteOnlyConforming,
        ExecuteOnlyConformingAccessed,
        ExecuteReadConforming,
        ExecuteReadConformingAccessed,
    };

    const DescriptorType = enum(u1) {
        System,
        CodeOrData,
    };

    const OperationSize = enum(u2) {
        Seg16Bits = 0b00,
        Seg32Bits = 0b10,
        Seg64Bits = 0b01,
    };
};

const GdtPtr = packed struct {
    limit: u16,
    base: u32,
};

const SegmentSelector = packed struct(u16) {
    privilege_level: u2 = 0,
    table: Table = Table.GDT,
    index: u13,

    const Table = enum(u1) { GDT, LDT };
};

pub fn init() void {
    var gdt_ptr: GdtPtr = GdtPtr{
        .limit = GDT.len * @sizeOf(SegmentDescriptor) - 1,
        .base = @intFromPtr(&GDT),
    };

    asm volatile ("lgdt (%[gdt_ptr])"
        :
        : [gdt_ptr] "r" (&gdt_ptr),
        : "memory"
    );

    const code_selector: u16 = comptime @bitCast(SegmentSelector{ .index = 1 }); // Index 1 = code segment
    const data_selector: u16 = comptime @bitCast(SegmentSelector{ .index = 2 }); // Index 2 = data segment

    asm volatile (
        \\movw %[data_sel], %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        \\movw %%ax, %%ss
        :
        : [data_sel] "r" (data_selector),
        : "ax", "memory"
    );

    asm volatile (
        \\ljmp %[code_sel], $reload_cs
        \\reload_cs:
        :
        : [code_sel] "n" (code_selector),
        : "memory"
    );
}
