const idt = @import("./idt.zig");
const serial = @import("./serial.zig");

pub fn getHandler(comptime handler: fn () void) idt.InterruptHandler {
    const wrapper = struct {
        fn interruptWrapper() callconv(.C) void {
            handler();
        }

        fn func() callconv(.naked) void {
            asm volatile (
                \\pusha
                \\push %%ds
                \\push %%es
                \\push %%fs
                \\push %%gs
                \\call *%[wrapper]
                \\pop %%gs
                \\pop %%fs
                \\pop %%es
                \\pop %%ds
                \\popa
                \\iret
                :
                : [wrapper] "r" (&interruptWrapper),
            );
        }
    };
    return wrapper.func;
}

pub fn breakpointHandler() void {
    var sp = serial.attach(serial.Port.COM1);
    sp.printf("Interrupt occurred!\r\n", .{});
}

pub fn syscallHandler() void {
    var sp = serial.attach(serial.Port.COM1);
    sp.printf("Syscall occurred!\r\n", .{});
}
