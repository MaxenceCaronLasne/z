const idt = @import("./idt.zig");
const serial = @import("./serial.zig");

pub fn getHandler(comptime handler: fn () void) idt.InterruptHandler {
    const wrapper = struct {
        export fn interruptWrapper() callconv(.C) void {
            handler();
        }

        fn func() callconv(.naked) void {
            asm volatile (
                \\pusha
                \\push %%ds
                \\push %%es
                \\push %%fs
                \\push %%gs
                \\call interruptWrapper
                \\pop %%gs
                \\pop %%fs
                \\pop %%es
                \\pop %%ds
                \\popa
                \\iret
            );
        }
    };
    return wrapper.func;
}

pub fn breakpointHandler() void {
    var sp = serial.attach(serial.Port.COM1);
    sp.printf("Interrupt occurred!\r\n", .{});
}
