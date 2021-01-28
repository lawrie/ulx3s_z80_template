# Description of top-level Verilog module (top.v)

```verilog
`default_nettype none
```

The module starts by specifying no default nettype so that all signals need to be declared.
This prevents errors from mis-typed signal names.

## Parameters

It then declares the top-level parameters:

```verilog
module top #(
  parameter c_vga_out      = 0,  // 0; Just HDMI, 1: VGA and HDMI
  parameter c_acia_serial  = 1,  // 0: disabled, 1: ACIA serial
  parameter c_esp32_serial = 0,  // 0: disabled, 1: ESP32 serial (micropython console)
  parameter c_sdram        = 1,  // SDRAM or BRAM 
  parameter c_keyboard     = 0,  // Include keyboard support
  parameter c_diag         = 1,  // 0: No led diagnostcs, 1: led diagnostics 
  parameter c_speed        = 1,  // CPU speed = 25 / 2 ** (c_speed + 1) MHz
  parameter c_reset        = 15, // Bits (minus 1) in power-up reset counter
  parameter c_lcd_hex      = 1   // SPI LCD HEX decoder
) (
```

These are used to configure the module.

The options are:

* c_vga_out Set this to 1 if you want VGA output from a Digilent VGA Pmod. Otherwise you just get HDMI output.
* c_acia_serial Set this to 1 to use a uart
* c_esp32_serial If you are not using a uart, set this to 1 to get uart passthru to the esp32
* c_sdram Set this to 1 to use SDRAM or 1 for BRAM
* c-Keyboard Set this to 1 to get ps/2 keyboard support
* c_diag Set this to 1 for led diagnostics using 2 Digilent 8 LED Pmods
* c_speed This sets the speed of the CPU. Higher values are lower speed
* c_reset Use this to configure the power-up reset period
* c_lcd_hex Set this to 1 to supporet hex diagnostics on a ST7789 LCD

## Ports

Next comes the module ports using the standard Ulx3s ulx3s_v20.lpf pin definitions:

```verilog
  input         clk_25mhz,
  // Buttons
  input [6:0]   btn,
  // HDMI
  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,
  // Keyboard
  input         usb_fpga_bd_dp,
  input         usb_fpga_bd_dn,
  output        usb_fpga_pu_dp,
  output        usb_fpga_pu_dn,
  // Audio
  output [3:0]  audio_l,
  output [3:0]  audio_r,
  // ESP32 passthru
  input         ftdi_txd,
  output        ftdi_rxd,
  input         wifi_txd,
  output        wifi_rxd,  // SPI from ESP32
  input         wifi_gpio16,
  input         wifi_gpio5,
  output        wifi_gpio0,

  inout  sd_clk, sd_cmd,
  inout   [3:0] sd_d,

  output sdram_csn,       // chip select
  output sdram_clk,       // clock to SDRAM
  output sdram_cke,       // clock enable to SDRAM
  output sdram_rasn,      // SDRAM RAS
  output sdram_casn,      // SDRAM CAS
  output sdram_wen,       // SDRAM write-enable
  output [12:0] sdram_a,  // SDRAM address bus
  output  [1:0] sdram_ba, // SDRAM bank-address
  output  [1:0] sdram_dqm,// byte select
  inout  [15:0] sdram_d,  // data bus to/from SDRAM

  inout  [27:0] gp,gn,
  // SPI display
  output        oled_csn,
  output        oled_clk,
  output        oled_mosi,
  output        oled_dc,
  output        oled_resn,
  // Leds
  output [7:0]  led
);
```
## CPU signals

Then the signals used by the CPU are declared:

```
  // ===============================================================
  // CPU signals
  // ===============================================================
  wire          n_wr;
  wire          n_rd;
  wire          n_int;
  wire          n_mreq;
  wire          n_iorq;
  wire          n_m1;

  // Buses
  wire [15:0]   cpu_address;
  wire [7:0]    cpu_data_out;
  wire [7:0]    cpu_data_in;
  wire [15:0]   pc;

  // Derived signals
  wire n_iowr  = n_wr | n_iorq;
  wire n_memwr = n_wr | n_mreq;
  wire n_iord  = n_rd | n_iorq;
  wire n_memrd = n_rd | n_mreq;

  // Chip selects
  wire          n_rom_cs;
  wire          n_ram_cs;

  wire          tdata_cs;
  wire          tctrl_cs;

  // Miscellaneous signals
  wire [7:0]    acia_dout;
  reg [6:0]     r_btn_joy;
  reg [7:0]     r_cpu_control;
  wire          spi_load = r_cpu_control[1];
```

The derived signals are for convenience to test for memory or I/O port reads or writes.

The chip select signals are used to select memory and peripheral chips (such as the ACIA uart).

## System clock generation

Next comes the system clock generation, using emard's ecp5pll module:

```verilog
  // ===============================================================
  // System Clock generation
  // ===============================================================
  wire clk_sdram_locked;
  wire [3:0] clocks;
  ecp5pll
  #(
      .in_hz( 25*1000000),
    .out0_hz(125*1000000),
    .out1_hz( 25*1000000),
    .out2_hz(100*1000000),                // SDRAM core
    .out3_hz(100*1000000), .out3_deg(180) // SDRAM chip 45-330:ok 0-30:not
  )
  ecp5pll_inst
  (
    .clk_i(clk_25mhz),
    .clk_o(clocks),
    .locked(clk_sdram_locked)
  );
  wire clk_hdmi  = clocks[0];
  wire clk_vga   = clocks[1];
  wire clk_cpu  = clocks[1];
  wire clk_sdram = clocks[2];
  wire sdram_clk = clocks[3]; // phase shifted for chip
```

Clocks are defined for the cpu, vga and hdmi output, and for the SDRAM (if used).

## CPU clock generation

The speed of the cpu clock is then set, using a clock enable signal.

```verilog
  // ===============================================================
  // CPU clock generation
  // ===============================================================
  reg [c_speed:0] cpu_clk_count;

  always @(posedge clk_cpu) begin
    cpu_clk_count <= cpu_clk_count + 1;
  end

  wire cpu_clk_enable = cpu_clk_count[c_speed];

```

## Reset generation


