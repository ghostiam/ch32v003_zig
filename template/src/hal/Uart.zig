const std = @import("std");
const config = @import("config");
const svd = @import("svd");

const port = @import("port.zig");

pub const DeadlineFn = fn () bool;

pub const Config = struct {
    brr: ?BaudRate = null,
    mode: Mode = .tx_rx,
    word_bits: WordBits = .eight,
    stop_bits: StopBits = .one,
    parity: Parity = .none,
    flow_control: FlowControl = .none,
    pins: ?Pins = null,
};

pub const BaudRate = struct {
    peripheral_clock: u32,
    baud_rate: u32,

    fn calculate(self: BaudRate) u32 {
        if (self.peripheral_clock == 0 or self.baud_rate == 0) {
            return 0;
        }

        return (self.peripheral_clock + self.baud_rate / 2) / self.baud_rate;
    }
};

pub const Mode = enum {
    tx,
    rx,
    tx_rx,
};

pub const WordBits = enum {
    eight,
    nine,
};

pub const StopBits = enum {
    one,
    half,
    two,
    one_and_a_half,
};

pub const Parity = enum {
    none,
    even,
    odd,
};

pub const FlowControl = enum {
    none,
    cts,
    rts,
    cts_rts,
};

pub const Pins = switch (config.chip_series) {
    .ch32v003 => @import("uart/ch32v003.zig").Pins,
    // TODO: implement other chips
    else => @compileError("Unsupported chip series"),
};

const RccBits = switch (config.chip_series) {
    .ch32v003 => @import("uart/ch32v003.zig").RccBits,
    // TODO: implement other chips
    else => @compileError("Unsupported chip series"),
};

pub const Timeout = error{
    Timeout,
};

pub const ErrorStates = packed struct(u4) {
    overrun_error: bool = false,
    break_error: bool = false,
    parity_error: bool = false,
    framing_error: bool = false,
    noise_error: bool = false,
};

const UART = @This();

uart: *volatile svd.types.USART,

pub fn init(uart: svd.peripherals.USART, comptime cfg: Config) UART {
    const self = UART{ .uart = uart.get() };

    self.reset();
    self.enable();
    self.configurePins(cfg);
    if (cfg.brr) |brr| {
        self.configureBaudRate(brr);
    }
    self.configureCtrl(cfg);

    return self;
}

/// Deinitializes the UART peripheral.
/// Disables and resets registers.
/// Note: GPIO pins will not be deinitialized when this function is called.
pub fn deinit(self: UART) void {
    self.disable();
    self.reset();
}

fn configurePins(self: UART, comptime cfg: Config) void {
    const pins = cfg.pins orelse Pins.get_default(self.uart);

    if (pins.remap.has()) {
        // Alternate function I/O clock enable
        svd.peripherals.RCC.APB2PCENR.modify(.{ .AFIOEN = 1 });
        // Remap the pins.
        svd.peripherals.AFIO.PCFR1.modify(pins.remap.afio_pcfr1);
    }

    if (cfg.mode == .tx or cfg.mode == .tx_rx) {
        port.enable(pins.tx.port);
        pins.tx.asOutput(.{ .speed = .max_10mhz, .mode = .alt_push_pull });
    }

    if (cfg.mode == .rx or cfg.mode == .tx_rx) {
        port.enable(pins.rx.port);
        pins.rx.asInput(.floating);
    }
}

/// Runtime baud rate configuration.
pub fn configureBaudRate(self: UART, cfg: BaudRate) void {
    self.uart.BRR.raw = cfg.calculate();
}

fn configureCtrl(self: UART, comptime cfg: Config) void {
    const parityBit = switch (cfg.parity) {
        .none => @as(u1, 0),
        .even, .odd => @as(u1, 1),
    };
    const paritySelectionBit = switch (cfg.parity) {
        .even => @as(u1, 1),
        .odd, .none => @as(u1, 0),
    };
    const wordLongBit = switch (cfg.word_bits) {
        .eight => @as(u1, 0),
        .nine => @as(u1, 1),
    };
    const stopBits = switch (cfg.stop_bits) {
        .one => @as(u2, 0b00),
        .half => @as(u2, 0b01),
        .two => @as(u2, 0b10),
        .one_and_a_half => @as(u2, 0b11),
    };
    var rts_bit: u1 = 0;
    var cts_bit: u1 = 0;
    switch (cfg.flow_control) {
        .none => {},
        .cts => cts_bit = 1,
        .rts => rts_bit = 1,
        .cts_rts => {
            cts_bit = 1;
            rts_bit = 1;
        },
    }

    self.uart.CTLR1.write(.{
        // Receiver enable
        .RE = 1,
        // Transmitter enable
        .TE = 1,
        // Parity check interrupt enable bit
        .PEIE = parityBit,
        // Parity selection bit
        .PS = paritySelectionBit,
        // Word long bit
        .M = wordLongBit,
    });

    self.uart.CTLR2.write(.{
        // Stop bits.
        .STOP = stopBits,
    });

    self.uart.CTLR3.write(.{
        // RTS enable.
        .RTSE = rts_bit,
        // CTS enable.
        .CTSE = cts_bit,
    });

    // // Enable the interrupt for RX
    // self.uart.CTLR1.modify(.{
    //     // RXNE interrupt enable.
    //     .RXNEIE = 1,
    // });
    // // bit 32 - interrupt enable control.
    // svd.peripherals.PFIC.IENR2.raw = 1;

    // UART enable bit.
    self.uart.CTLR1.modify(.{
        .UE = 1,
    });
}

pub fn enable(self: UART) void {
    const RCC = svd.peripherals.RCC;
    const bits = RccBits.get(self.uart);
    if (bits.apb2) |pos| {
        RCC.APB2PCENR.setBit(pos, 1);
    }
    if (bits.apb1) |pos| {
        RCC.APB1PCENR.setBit(pos, 1);
    }
}

pub fn disable(self: UART) void {
    const RCC = svd.peripherals.RCC;
    const bits = RccBits.get(self.uart);
    if (bits.apb2) |pos| {
        RCC.APB2PCENR.setBit(pos, 0);
    }
    if (bits.apb1) |pos| {
        RCC.APB1PCENR.setBit(pos, 0);
    }
}

fn reset(self: UART) void {
    const RCC = svd.peripherals.RCC;
    const bits = RccBits.get(self.uart);
    if (bits.apb2) |pos| {
        RCC.APB2PRSTR.setBit(pos, 1);
        RCC.APB2PRSTR.setBit(pos, 0);
    }
    if (bits.apb1) |pos| {
        RCC.APB2PRSTR.setBit(pos, 1);
        RCC.APB2PRSTR.setBit(pos, 0);
    }
}

pub fn isReadable(self: UART) bool {
    return self.uart.STATR.read().RXNE == 1;
}

pub fn isWriteable(self: UART) bool {
    return self.uart.STATR.read().TXE == 1;
}

pub fn isWriteComplete(self: UART) bool {
    return self.uart.STATR.read().TC == 1;
}

pub noinline fn writeBlocking(self: UART, payload: []const u8, deadlineFn: ?DeadlineFn) Timeout!usize {
    var offset: usize = 0;
    while (offset < payload.len) {
        self.wait(isWriteable, deadlineFn) catch |err| {
            if (offset > 0) {
                return offset;
            }
            return err;
        };

        self.uart.DATAR.raw = payload[offset];
        offset += 1;

        self.wait(isWriteComplete, deadlineFn) catch {
            return offset;
        };
    }

    return offset;
}

pub fn readBlocking(self: UART, buffer: []u8, deadlineFn: ?DeadlineFn) Timeout!usize {
    for (buffer, 0..) |*byte, count| {
        self.wait(isReadable, deadlineFn) catch |err| {
            if (count > 0) {
                return count;
            }
            return err;
        };

        byte.* = @truncate(self.uart.DATAR.raw & 0xFF);
    }

    return buffer.len;
}

pub fn getErrors(self: UART) ErrorStates {
    const statr = self.uart.STATR.read();
    return .{
        .overrun_error = statr.ORE,
        .break_error = statr.LBD,
        .parity_error = statr.PE,
        .framing_error = statr.FE,
        .noise_error = statr.NE,
    };
}

pub fn clearErrors(self: UART) void {
    self.uart.STATR.modify(.{
        .ORE = 0,
        .LBD = 0,
        .PE = 0,
        .FE = 0,
        .NE = 0,
    });
}

// Wait for a condition to be true.
fn wait(self: UART, conditionFn: fn (self: UART) bool, deadlineFn: ?DeadlineFn) Timeout!void {
    while (!conditionFn(self)) {
        if (deadlineFn) |check| {
            if (check()) {
                return error.Timeout;
            }
        }
        asm volatile ("" ::: "memory");
    }
}
