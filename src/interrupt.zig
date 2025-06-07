const idt = @import("./idt.zig");

pub fn getHandler() idt.InterruptHandler {
    return struct {
        fn func() callconv(.naked) void {
            asm volatile ("iret");
        }
    }.func;
}
