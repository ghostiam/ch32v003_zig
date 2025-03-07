const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");
const panic = @import("panic.zig");

comptime {
    if (!builtin.is_test) {
        asm (
            \\.section .init
            \\j _start
        );

        @export(&_start, .{ .name = "_start" });
    }
}

fn _start() callconv(.C) noreturn {
    // Set global pointer.
    asm volatile (
        \\.option push
        \\.option norelax
        \\la gp, __global_pointer$
        \\.option pop
    );

    // Set stack pointer.
    asm volatile (
        \\la sp, __end_of_stack
    );

    // Clear whole RAM. Good for debugging.
    asm volatile (
        \\    li a0, 0
        \\    la a1, __start_of_ram
        \\    la a2, __end_of_stack
        \\    beq a1, a2, clear_ram_done
        \\clear_ram_loop:
        \\    sw a0, 0(a1)
        \\    addi a1, a1, 4
        \\    blt a1, a2, clear_ram_loop
        \\clear_ram_done:
    );

    // // Clear .bss section.
    // asm volatile (
    //     \\    li a0, 0
    //     \\    la a1, __bss_start
    //     \\    la a2, __bss_end
    //     \\    beq a1, a2, clear_bss_done
    //     \\clear_bss_loop:
    //     \\    sw a0, 0(a1)
    //     \\    addi a1, a1, 4
    //     \\    blt a1, a2, clear_bss_loop
    //     \\clear_bss_done:
    // );

    // Copy .data from flash to RAM.
    asm volatile (
        \\    la a0, __data_load_start
        \\    la a1, __data_start
        \\    la a2, __data_end
        \\copy_data_loop:
        \\    beq a1, a2, copy_done
        \\    lw a3, 0(a0)
        \\    sw a3, 0(a1)
        \\    addi a0, a0, 4
        \\    addi a1, a1, 4
        \\    bne a1, a2, copy_data_loop
        \\copy_done:
    );

    // 3.2 Interrupt-related CSR Registers
    // INTSYSCR: enable EABI, nesting and HPE.
    asm volatile ("csrsi 0x804, 0b111");
    // Enable interrupts.
    // MPIE and MIE.
    asm volatile (
        \\li a0, 0b10001000
        \\csrw mstatus, a0
    );
    // mtvec: set the base address of the interrupt vector table
    // and set the mode0 and mode1.
    asm volatile (
        \\la a0, _start
        \\ori a0, a0, 0b11
        \\csrw mtvec, a0
    );

    callMain();
}

inline fn callMain() noreturn {
    const main_invalid_msg = "main must be either \"pub fn main() void\" or \"pub fn main() !void\".";

    const main_type = @typeInfo(@TypeOf(root.main));
    if (main_type != .@"fn" or main_type.@"fn".params.len > 0) {
        @compileError(main_invalid_msg);
    }

    const return_type = @typeInfo(main_type.@"fn".return_type.?);
    if (return_type != .void and return_type != .noreturn and return_type != .error_union) {
        @compileError(main_invalid_msg);
    }

    if (return_type == .error_union) {
        root.main() catch |err| {
            var buf: [32]u8 = undefined;
            const msg = concat(&buf, "main(): ", @errorName(err));
            @panic(msg);
        };
    } else {
        root.main();
    }

    panic.hang();
}

fn concat(buf: []u8, a: []const u8, b: []const u8) []u8 {
    var i: usize = 0;
    while (i < a.len and i < buf.len) : (i += 1) {
        buf[i] = a[i];
    }

    var j: usize = 0;
    while (j < b.len and i + j < buf.len) : (j += 1) {
        buf[i + j] = b[j];
    }

    return buf[0 .. i + j];
}

test "concat" {
    const a = "Hello, ";
    const b = "World!";
    var buf: [20]u8 = undefined;
    const result = concat(&buf, a, b);
    const expected = "Hello, World!";
    try std.testing.expectEqualStrings(expected, result);
}

test "concat small buffer" {
    const a = "Hello, ";
    const b = "World!";
    var buf: [8]u8 = undefined;
    const result = concat(&buf, a, b);
    const expected = "Hello, W";
    try std.testing.expectEqualStrings(expected, result);
}

test "concat very small buffer" {
    const a = "Hello, ";
    const b = "World!";
    var buf: [4]u8 = undefined;
    const result = concat(&buf, a, b);
    const expected = "Hell";
    try std.testing.expectEqualStrings(expected, result);
}
