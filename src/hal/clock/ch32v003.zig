const std = @import("std");
const config = @import("config");
const svd = @import("svd");

pub const Clocks = struct {
    sys: u32,
    hb: u32,

    // Default clock configuration after systemInit() routine.
    pub const default: Clocks = .{ .sys = hsi_frequency, .hb = hsi_frequency };
};

pub const hsi_frequency: u32 = 24_000_000;
pub const default_hse_frequency: u32 = 24_000_000;

const HseSource = struct {
    frequency: u32 = default_hse_frequency,
    bypass: bool = false,
    clock_security_system: bool = false,
};

const Source = union(enum) {
    hsi: void,
    hse: HseSource,
};

const SysClk = enum {
    hsi,
    hse,
    pll,
};

const HbPrescaler = enum(u32) {
    div1 = 1,
    div2 = 2,
    div3 = 3,
    div4 = 4,
    div5 = 5,
    div6 = 6,
    div7 = 7,
    div8 = 8,
    div16 = 16,
    // Disabled to prevent bricking, as flashing is not possible at low frequency.
    div32 = 32,
    div64 = 64,
    div128 = 128,
    div256 = 256,

    fn num(self: HbPrescaler) u32 {
        return @intFromEnum(self);
    }

    fn bits(self: HbPrescaler) u4 {
        return switch (self) {
            .div1 => 0b0000,
            .div2 => 0b0001,
            .div3 => 0b0010,
            .div4 => 0b0011,
            .div5 => 0b0100,
            .div6 => 0b0101,
            .div7 => 0b0110,
            .div8 => 0b0111,
            .div16 => 0b1011,
            .div32 => 0b1100,
            .div64 => 0b1101,
            .div128 => 0b1110,
            .div256 => 0b1111,
        };
    }

    fn fromBits(b: u4) ?HbPrescaler {
        return switch (b) {
            0b0000 => .div1,
            0b0001 => .div2,
            0b0010 => .div3,
            0b0011 => .div4,
            0b0100 => .div5,
            0b0101 => .div6,
            0b0110 => .div7,
            0b0111 => .div8,
            0b1011 => .div16,
            0b1100 => .div32,
            0b1101 => .div64,
            0b1110 => .div128,
            0b1111 => .div256,
            else => null,
        };
    }
};

pub const Config = struct {
    source: Source,
    sys_clk: SysClk,
    hb_pre: HbPrescaler,

    pub const default = hsi_8mhz;
    pub const hsi_max = hsi_48mhz;
    pub const hse_max = hse_48mhz;

    pub const hsi_8mhz: Config = .{
        .source = .hsi,
        .sys_clk = .hsi,
        .hb_pre = .div3,
    };
    pub const hsi_24mhz: Config = .{
        .source = .hsi,
        .sys_clk = .hsi,
        .hb_pre = .div1,
    };
    pub const hsi_48mhz: Config = .{
        .source = .hsi,
        .sys_clk = .pll,
        .hb_pre = .div1,
    };
    pub const hse_8mhz: Config = .{
        .source = .{ .hse = .{} },
        .sys_clk = .hse,
        .hb_pre = .div3,
    };
    pub const hse_24mhz: Config = .{
        .source = .{ .hse = .{} },
        .sys_clk = .hse,
        .hb_pre = .div1,
    };
    pub const hse_48mhz: Config = .{
        .source = .{ .hse = .{} },
        .sys_clk = .pll,
        .hb_pre = .div1,
    };
};

pub fn setOrGet(comptime cfg: Config) Clocks {
    const hse_frequency = switch (cfg.source) {
        .hse => |hse| hse.frequency,
        else => default_hse_frequency,
    };
    return set(cfg) catch get(hse_frequency) orelse .default;
}

pub fn set(comptime cfg: Config) !Clocks {
    const RCC = svd.peripherals.RCC;
    const AFIO = svd.peripherals.AFIO;
    const FLASH = svd.peripherals.FLASH;

    if (cfg.sys_clk == .hse and cfg.source != .hse) {
        @compileError("Source must be HSE when system clock is HSE");
    }

    // Configure HSE.
    if (cfg.source == .hse) {
        // PA0-PA1 are used for HSE.
        RCC.APB2PCENR.modify(.{ .AFIOEN = 1 });
        AFIO.PCFR1.modify(.{ .PA12_RM = 1 });
        RCC.CTLR.modify(.{
            // Enable HSE.
            .HSEON = 1,
            // HSE bypass.
            .HSEBYP = boolToU1(cfg.source.hse.bypass),
            .CSSON = boolToU1(cfg.source.hse.clock_security_system),
        });

        // Wait for HSE to be ready or timeout.
        var timeout: u32 = 10_000;
        while (timeout > 0) : (timeout -= 1) {
            if (RCC.CTLR.read().HSERDY != 0) {
                break;
            }
        }
        if (RCC.CTLR.read().HSERDY == 0) {
            return error.WaitHseTimeout;
        }
    }

    const sys_clk_freq: u32 = switch (cfg.sys_clk) {
        .hsi => hsi_frequency,
        .hse => cfg.source.hse.frequency,
        .pll => switch (cfg.source) {
            // PLL for ch32v003 only supports multiplier 2.
            .hsi => hsi_frequency * 2,
            .hse => |v| v.frequency * 2,
        },
    };

    const hbclk_freq: u32 = sys_clk_freq / cfg.hb_pre.num();

    // Flash wait states.
    // If freq <= 24MHz, set 0 wait state.
    // If freq > 24MHz, set 1 wait state.
    FLASH.ACTLR.modify(.{ .LATENCY = if (hbclk_freq > 24_000_000) 1 else 0 });

    // Set HB prescaler.
    RCC.CFGR0.modify(.{ .HPRE = cfg.hb_pre.bits() });

    if (cfg.sys_clk == .pll) {
        // Configure PLL source.
        RCC.CFGR0.modify(.{ .PLLSRC = boolToU1(cfg.source == .hse) });
        // Enable PLL.
        RCC.CTLR.modify(.{ .PLLON = 1 });
        // Wait for PLL to be ready or timeout.
        var timeout: u32 = 10_000;
        while (timeout > 0) : (timeout -= 1) {
            if (RCC.CTLR.read().PLLRDY != 0) {
                break;
            }
        }
        if (RCC.CTLR.read().PLLRDY == 0) {
            return error.WaitPllTimeout;
        }
    }

    // Set system clock source.
    const sw: u2 = switch (cfg.sys_clk) {
        .hsi => 0b00,
        .hse => 0b01,
        .pll => 0b10,
    };
    RCC.CFGR0.modify(.{ .SW = sw });
    // Wait for system clock to be ready or timeout.
    var timeout: u32 = 10_000;
    while (timeout > 0) : (timeout -= 1) {
        if (RCC.CFGR0.read().SWS == sw) {
            break;
        }
    }
    if (RCC.CFGR0.read().SWS != sw) {
        return error.WaitSysClkTimeout;
    }

    return .{
        .sys = sys_clk_freq,
        .hb = hbclk_freq,
    };
}

pub fn get(hse_frequency: u32) ?Clocks {
    const RCC = svd.peripherals.RCC;
    const CFGR0 = RCC.CFGR0.read();
    const sys_clk_freq: u32 = switch (CFGR0.SWS) {
        0b00 => hsi_frequency,
        0b01 => hse_frequency,
        0b10 => hsi_frequency * 2,
        else => return null,
    };

    const hpre = HbPrescaler.fromBits(CFGR0.HPRE) orelse return null;
    const hbclk_freq: u32 = sys_clk_freq / hpre.num();
    return .{
        .sys = sys_clk_freq,
        .hb = hbclk_freq,
    };
}

// Adjusts the Internal High Speed oscillator (HSI) calibration value.
// value must be a number between 0 and 31(0x1F).
pub fn adjustHsiCalibrationValue(value: u5) void {
    const RCC = svd.peripherals.RCC;
    RCC.CTLR.modify(.{ .HSITRIM = value });
}

inline fn boolToU1(b: bool) u1 {
    return if (b) 1 else 0;
}
