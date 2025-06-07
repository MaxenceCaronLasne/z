pub const CpuState = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,

    esi: u32,
    edi: u32,
    esp: u32,
    ebp: u32,

    eflags: u32,

    ds: u16,
    es: u16,
    fs: u16,
    gs: u16,
};

pub fn halt() void {
    asm volatile ("hlt");
}

pub fn breakpoint() void {
    asm volatile ("int $3");
}

pub fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        else => @compileError("Invalid data type. Only u8, u16 or u32, found: " ++ @typeName(Type)),
    };
}

pub fn out(port: u16, data: anytype) void {
    switch (@TypeOf(data)) {
        u8 => asm volatile ("outb %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{al}" (data),
        ),
        u16 => asm volatile ("outw %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{ax}" (data),
        ),
        u32 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data),
        ),
        else => @compileError("Invalid data type. Only u8, u16 or u32, found: " ++ @typeName(@TypeOf(data))),
    }
}
