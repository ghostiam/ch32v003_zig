const std = @import("std");
const config = @import("config");

pub const Interrups = switch (config.chip.series) {
    .ch32v003 => @import("interrups/ch32v003.zig").Interrups,
    .ch32v30x => @import("interrups/ch32v30x.zig").Interrups,
    // TODO: implement other chips
    else => @compileError("Unsupported chip series"),
};

pub inline fn enable() void {
    asm volatile ("csrsi mstatus, 0b1000");
}

pub inline fn disable() void {
    asm volatile ("csrci mstatus, 0b1000");
}

pub inline fn isEnabled() bool {
    const mstatus = asm ("csrr %[out], mstatus"
        : [out] "=r" (-> u32),
    );
    return (mstatus & 0b1000) != 0;
}
