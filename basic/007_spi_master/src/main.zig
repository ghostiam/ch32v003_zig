// Registers adresses are taken from CH32V003 reference manual.
const RCC_BASE: u32 = 0x40021000;
const GPIOC_BASE: u32 = 0x40011000;
const RCC_APB2PCENR: *volatile u32 = @ptrFromInt(RCC_BASE + 0x18);
const GPIOC_CFGLR: *volatile u32 = @ptrFromInt(GPIOC_BASE + 0x00);
const GPIOC_OUTDR: *volatile u32 = @ptrFromInt(GPIOC_BASE + 0x0C);

// Port bit offset for Port C.
const io_port_bit = 4;
const led_pin_num = 0;

const start = @import("start.zig");
const spi = @import("spi.zig");

comptime {
    // Import comptime definitions from start.zig.
    _ = start;
}

pub const panic = start.panic_hang;

pub fn main() !void {
    RCC_APB2PCENR.* |= @as(u32, 1) << io_port_bit; // Enable Port clock.
    GPIOC_CFGLR.* &= ~(@as(u32, 0b1111) << led_pin_num * 4); // Clear all bits for pin.
    GPIOC_CFGLR.* |= @as(u32, 0b0011) << led_pin_num * 4; // Set push-pull output for pin.

    spi.SPI1.configure(.{ .mode = .master });

    while (true) {
        _ = spi.SPI1.writeBlocking("Test");

        // Toggle pin.
        GPIOC_OUTDR.* ^= @as(u16, 1 << led_pin_num);

        // Simple delay.
        var i: u32 = 0;
        while (i < 1_000_000) : (i += 1) {
            // ZIG please don't optimize this loop away.
            asm volatile ("" ::: "memory");
        }
    }
}
