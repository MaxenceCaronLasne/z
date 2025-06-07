const idt = @import("./idt.zig");
const serial = @import("./serial.zig");

pub fn getHandler() idt.InterruptHandler {
    return struct {
        fn func() callconv(.naked) void {
            asm volatile (
                \\pusha
                \\push %%ds
                \\push %%es
                \\push %%fs
                \\push %%gs
                \\call interruptHandler
                \\pop %%gs
                \\pop %%fs
                \\pop %%es
                \\pop %%ds
                \\popa
                \\iret
            );
        }
    }.func;
}

export fn interruptHandler() void {
    const sp = serial.attach(serial.Port.COM1);
    sp.print("Interrupt occurred!\r\n", .{});
}
