// Registers adresses are taken from CH32V003 reference manual.
const RCC_BASE: u32 = 0x40021000;
const GPIOC_BASE: u32 = 0x40011000;
const RCC_APB2PCENR: *volatile u32 = @ptrFromInt(RCC_BASE + 0x18);
const GPIOC_CFGLR: *volatile u32 = @ptrFromInt(GPIOC_BASE + 0x00);
const GPIOC_OUTDR: *volatile u32 = @ptrFromInt(GPIOC_BASE + 0x0C);

// Port bit offset for Port C.
const io_port_bit = 4;
const led_pin_num = 0;

// By default, the CPU frequency is 8MHz.
const cpu_freq: u32 = 8_000_000;
const uart_baud_rate: u32 = 115_200;

const start = @import("start.zig");
const uart = @import("uart.zig");

comptime {
    // Import comptime definitions from start.zig.
    _ = start;
}

// Use hang function from start.zig as panic function.
pub const panic = start.panic_hang;

pub fn main() !void {
    RCC_APB2PCENR.* |= @as(u32, 1) << io_port_bit; // Enable Port clock.
    GPIOC_CFGLR.* &= ~(@as(u32, 0b1111) << led_pin_num * 4); // Clear all bits for pin.
    GPIOC_CFGLR.* |= @as(u32, 0b0011) << led_pin_num * 4; // Set push-pull output for pin.

    uart.USART1.setup(.{
        .cpu_frequency = cpu_freq,
        .baud_rate = uart_baud_rate,
    });

    _ = uart.USART1.writeBlocking("UART initialized\r\n");

    var count: u32 = 0;
    var buffer: [10]u8 = undefined;
    while (true) {
        // Print counter value.
        _ = uart.USART1.writeBlocking(intToStr(&buffer, count));
        _ = uart.USART1.writeBlocking("\r\n");
        count += 1;

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

fn intToStr(buf: []u8, value: u32) []u8 {
    var i: u32 = buf.len;
    var v: u32 = value;
    if (v == 0) {
        buf[0] = '0';
        return buf[0..1];
    }

    while (v > 0) : (v /= 10) {
        i -= 1;
        buf[i] = @as(u8, @truncate(v % 10)) + '0';
    }

    return buf[i..];
}
