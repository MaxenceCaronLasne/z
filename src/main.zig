const arch = @import("./arch.zig");
const console = @import("./console.zig");
const serial = @import("./serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const interrupt = @import("./interrupt.zig");

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const MultibootHeader = packed struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,
    padding: u32 = 0,
};

export var multiboot: MultibootHeader align(4) linksection(".multiboot") = .{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ call %[kmain:P]
        :
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [kmain] "X" (&kmain),
    );
}

fn kmain() callconv(.C) void {
    console.initialize();
    console.puts("Hello Zig Kernel!");

    const sp = serial.init(38400, serial.Port.COM1) catch |err| {
        console.puts("Failed to initialize serial port: ");
        console.puts(@errorName(err));
        return;
    };

    sp.write("hello world!\r\n");

    gdt.init();
    var idt_manager = idt.init();

    idt_manager.addInterruptGate(3, interrupt.getHandler()) catch |err| {
        sp.write("Failed to open interrupt gate: ");
        sp.write(@errorName(err));
        sp.write("\r\n");
    };

    sp.write("hello from protected!\r\n");

    arch.breakpoint();
    sp.write("hello from after the breakpoint!\r\n");

    while (true) {
        arch.halt();
    }
}
