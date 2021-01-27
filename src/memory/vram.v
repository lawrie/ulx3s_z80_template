module vram #(
  parameter MEM_INIT_FILE = "",
  parameter DATA_WIDTH = 8,
  parameter DEPTH = 16384,
  parameter ADDRESS_WIDTH = $clog2(DEPTH)
) (
  input                       clk_a,
  input                       we_a,
  input [ADDRESS_WIDTH-1:0]   addr_a,
  input [DATA_WIDTH-1:0]      din_a,
  output reg [DATA_WIDTH-1:0] dout_a,
  input                       clk_b,
  input [ADDRESS_WIDTH-1:0]   addr_b,
  output reg [DATA_WIDTH-1:0] dout_b
);

  reg [DATA_WIDTH-1:0] ram_ub [0:DEPTH-1];

  always @(posedge clk_a) begin
    if (we_a)
      ram[addr_a] <= din_a;
    dout_a <= ram[addr_a];
  end

  always @(posedge clk_b) begin
    dout_b <= ram[addr_b];
  end

endmodule
