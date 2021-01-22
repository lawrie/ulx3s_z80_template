`default_nettype none
module spectrum
#(
  parameter c_vga_out     = 0, // 0; Just HDMI, 1: VGA and HDMI
  parameter c_acia_serial = 1, // 0: disabled, 1: ACIA serial
  parameter c_esp32_serial= 0, // 0: disabled, 1: ESP32 serial (micropython console)
  parameter c_lcd_hex     = 1  // SPI LCD HEX decoder
)
(
  input         clk_25mhz,
  // Buttons
  input [6:0]   btn,
  // HDMI
  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,
  // Keyboard
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

  // ===============================================================
  // CPU registers
  // ===============================================================
  wire          n_WR;
  wire          n_RD;
  wire          n_INT;
  wire [15:0]   cpu_address;
  wire [7:0]    cpu_data_out;
  wire [7:0]    cpu_data_in;
  wire          n_memWR;
  wire          n_memRD;
  wire          n_ioWR;
  wire          n_ioRD;
  wire          n_MREQ;
  wire          n_IORQ;
  wire          n_M1;
  wire          n_romCS;
  wire          n_ramCS;
  wire          n_kbdCS;
  wire          n_joyCS;
  wire [15:0]   pc;
  wire [7:0]    acia_dout;
  wire          tctrl_cs = cpu_address[7:0] == 8'h80 && n_IORQ == 1'b0;
  wire          tdata_cs = cpu_address[7:0] == 8'h81 && n_IORQ == 1'b0;
  
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

  // ===============================================================
  // CPU clock generation
  // ===============================================================
  reg [2:0]     cpu_clk_count;
  wire          cpu_clk_enable;
  
  always @(posedge clk_cpu) begin
    cpu_clk_count <= cpu_clk_count + 1;
  end

  assign cpu_clk_enable = cpu_clk_count[2]; // 3.5Mhz

  // ===============================================================
  // Reset generation
  // ===============================================================
  reg [15:0] pwr_up_reset_counter = 0;
  wire       pwr_up_reset_n = &pwr_up_reset_counter;
  reg [7:0]  r_cpu_control;
  wire       spi_load = r_cpu_control[1];
  wire       n_hard_reset = pwr_up_reset_n & btn[0] & ~r_cpu_control[0];
  wire       reset = !n_hard_reset;

  always @(posedge clk_cpu) begin
     if (!pwr_up_reset_n)
       pwr_up_reset_counter <= pwr_up_reset_counter + 1;
  end

  // ===============================================================
  // CPU
  // ===============================================================
  tv80n cpu1 (
    .reset_n(n_hard_reset),
    .clk(cpu_clk_enable),
    .wait_n(~spi_load),
    .int_n(n_INT),
    .nmi_n(1'b1),
    .busrq_n(1'b1),
    .mreq_n(n_MREQ),
    .m1_n(n_M1),
    .iorq_n(n_IORQ),
    .wr_n(n_WR),
    .A(cpu_address),
    .di(cpu_data_in),
    .do(cpu_data_out),
    .pc(pc)
  );

  // ===============================================================
  // Joystick for OSD control and games
  // ===============================================================
  reg [6:0] r_btn_joy;
  always @(posedge clk_cpu)
    r_btn_joy <= btn;

  // ===============================================================
  // SPI Slave
  // ===============================================================
  wire spi_ram_wr, spi_ram_rd;
  wire [31:0] spi_ram_addr;
  wire [7:0] spi_ram_di;
  wire [7:0] ram_out;
  wire [7:0] spi_ram_do = ram_out;

  assign sd_d[3] = 1'bz; // FPGA pin pullup sets SD card inactive at SPI bus

  wire irq;
  spi_ram_btn
  #(
    .c_sclk_capable_pin(1'b0),
    .c_addr_bits(32)
  )
  spi_ram_btn_inst
  (
    .clk(clk_cpu),
    .csn(~wifi_gpio5),
    .sclk(wifi_gpio16),
    .mosi(sd_d[1]), // wifi_gpio4
    .miso(sd_d[2]), // wifi_gpio12
    .btn(r_btn_joy),
    .irq(irq),
    .wr(spi_ram_wr),
    .rd(spi_ram_rd),
    .addr(spi_ram_addr),
    .data_in(spi_ram_do),
    .data_out(spi_ram_di)
  );
  assign wifi_gpio0 = ~irq;

  always @(posedge clk_cpu) begin
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hFF) begin
      r_cpu_control <= spi_ram_di;
    end
  end

  // ===============================================================
  // RAM
  // ===============================================================
  wire [7:0] vid_out;
  wire [12:0] vga_addr;
  wire [7:0] attrOut;
  wire [12:0] attr_addr;

  dpram ram48 (
    .clk_a(clk_cpu),
    .we_a(spi_load ? spi_ram_wr  && spi_ram_addr[31:24] == 8'h00 : !n_ramCS & !n_memWR),
    .addr_a(spi_load ? spi_ram_addr[15:0] : cpu_address),
    .din_a(spi_load ? spi_ram_di : cpu_data_out),
    .dout_a(ram_out),
    .clk_b(clk_vga),
    .addr_b({3'b010, vga_addr}),
    .dout_b(vid_out)
  );

  // ===============================================================
  // Video
  // ===============================================================
  
  // VGA (should be assigned to some gp/gn outputs
  wire   [7:0]  red;
  wire   [7:0]  green;
  wire   [7:0]  blue;
  wire          hsync;
  wire          vsync;
  wire          vga_de;
  
  generate
    genvar i;
    if (c_vga_out) begin
      for(i = 0; i < 4; i = i+1) begin
        assign gp[10-i] = blue[4+i];
        assign gn[3-i] = green[4+i];
        assign gn[10-i] = red[4+i];
      end
      assign gp[2] = vsync;
      assign gp[3] = hsync;
    end
  endgenerate

  video vga (
    .clk(clk_vga),
    .vga_r(red),
    .vga_g(green),
    .vga_b(blue),
    .vga_de(vga_de),
    .vga_hs(hsync),
    .vga_vs(vsync),
    .vga_addr(vga_addr),
    .vga_data(vid_out),
    .n_int(n_INT)
  );

  // OSD
  wire [7:0] osd_vga_r, osd_vga_g, osd_vga_b;
  wire osd_vga_hsync, osd_vga_vsync, osd_vga_blank;
  spi_osd
  #(
    .c_start_x(62), .c_start_y(80),
    .c_chars_x(64), .c_chars_y(20),
    .c_init_on(0),
    .c_char_file("osd.mem"),
    .c_font_file("font_bizcat8x16.mem")
  )
  spi_osd_inst
  (
    .clk_pixel(clk_vga), .clk_pixel_ena(1),
    .i_r(red),
    .i_g(green),
    .i_b(blue),
    .i_hsync(~hsync), .i_vsync(~vsync), .i_blank(~vga_de),
    .i_csn(~wifi_gpio5), .i_sclk(wifi_gpio16), .i_mosi(sd_d[1]), // .o_miso(),
    .o_r(osd_vga_r), .o_g(osd_vga_g), .o_b(osd_vga_b),
    .o_hsync(osd_vga_hsync), .o_vsync(osd_vga_vsync), .o_blank(osd_vga_blank)
  );

  // Convert VGA to HDMI
  HDMI_out vga2dvid (
    .pixclk(clk_vga),
    .pixclk_x5(clk_hdmi),
    .red(osd_vga_r),
    .green(osd_vga_g),
    .blue(osd_vga_b),
    .vde(~osd_vga_blank),
    .hSync(osd_vga_hsync),
    .vSync(osd_vga_vsync),
    .gpdi_dp(gpdi_dp),
    .gpdi_dn(gpdi_dn)
  );

  // ===============================================================
  // ACIA
  // ===============================================================
  wire acia_txd, acia_rxd;
  generate
    if(c_acia_serial)
    begin
      assign acia_rxd = ftdi_txd;
      assign ftdi_rxd = acia_txd;
    end
    else
    begin
      assign acia_rxd = 0;
    end
    if(c_esp32_serial)
    begin
      assign wifi_rxd = ftdi_txd;
      assign ftdi_rxd = wifi_txd;
    end
  endgenerate

  // ===============================================================
  // Audio
  // ===============================================================
  assign audio_l = 0;
  assign audio_r = audio_l;

  // ===============================================================
  // 6850 ACIA (uart)
  // ===============================================================

  reg baudclk; // 16 * 9600 = 153600 = 25Mhz/162
  reg [7:0] baudctr = 0;

  generate
    if(c_acia_serial) begin
      always @(posedge clk_cpu) begin
        baudctr <= baudctr + 1;
        baudclk <= (baudctr > 80);
        if(baudctr > 161) baudctr <= 0;
      end

      // 9600 8N1
      ACIA acia(
        .clk(clk_cpu),
        .reset(reset),
        .cs(tctrl_cs | tdata_cs),
        .e_clk(1'b1),
        .rw_n(n_ioWR),
        .rs(tdata_cs),
        .data_in(tctrl_cs ? 8'h01 : cpu_data_out[15:8]), // Set output when anything is written to tctrl
        .data_out(acia_dout),
        .txclk(baudclk),
        .rxclk(baudclk),
        .txdata(acia_txd),
        .rxdata(acia_rxd),
        .cts_n(1'b0),
        .dcd_n(1'b0)
      );
    end
  endgenerate

// ===============================================================
  // MEMORY READ/WRITE LOGIC
  // ===============================================================
  assign n_ioWR = n_WR | n_IORQ;
  assign n_memWR = n_WR | n_MREQ;
  assign n_ioRD = n_RD | n_IORQ;
  assign n_memRD = n_RD | n_MREQ;

  // ===============================================================
  // Chip selects
  // ===============================================================
  assign n_romCS = cpu_address[15:14] != 0;
  assign n_ramCS = !n_romCS;

  // ===============================================================
  // Memory decoding
  // ===============================================================
  assign cpu_data_in =  ram_out;

  // ===============================================================
  // LCD diagnostics
  // ===============================================================
  generate
  if(c_lcd_hex)
  begin
  // SPI DISPLAY
  reg [127:0] r_display;
  // HEX decoder does printf("%16X\n%16X\n", r_display[63:0], r_display[127:64]);
  always @(posedge clk_cpu)
    r_display = {pc};

  parameter c_color_bits = 16;
  wire [7:0] x;
  wire [7:0] y;
  wire [c_color_bits-1:0] color;
  hex_decoder_v
  #(
    .c_data_len(128),
    .c_row_bits(4),
    .c_grid_6x8(1), // NOTE: TRELLIS needs -abc9 option to compile
    .c_font_file("hex_font.mem"),
    .c_color_bits(c_color_bits)
  )
  hex_decoder_v_inst
  (
    .clk(clk_hdmi),
    .data(r_display),
    .x(x[7:1]),
    .y(y[7:1]),
    .color(color)
  );

  // allow large combinatorial logic
  // to calculate color(x,y)
  wire next_pixel;
  reg [c_color_bits-1:0] r_color;
  always @(posedge clk_hdmi)
    if(next_pixel)
      r_color <= color;

  wire w_oled_csn;
  lcd_video
  #(
    .c_clk_mhz(125),
    .c_init_file("st7789_linit_xflip.mem"),
    .c_clk_phase(0),
    .c_clk_polarity(1),
    .c_init_size(38)
  )
  lcd_video_inst
  (
    .clk(clk_hdmi),
    .reset(r_btn_joy[5]),
    .x(x),
    .y(y),
    .next_pixel(next_pixel),
    .color(r_color),
    .spi_clk(oled_clk),
    .spi_mosi(oled_mosi),
    .spi_dc(oled_dc),
    .spi_resn(oled_resn),
    .spi_csn(w_oled_csn)
  );
  //assign oled_csn = w_oled_csn; // 8-pin ST7789: oled_csn is connected to CSn
  assign oled_csn = 1; // 7-pin ST7789: oled_csn is connected to BLK (backlight enable pin)
  end
  endgenerate

  // ===============================================================
  // Leds
  // ===============================================================
  assign led = {irq, !n_hard_reset, spi_ram_rd, spi_ram_wr};
  
endmodule
