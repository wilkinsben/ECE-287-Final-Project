// vga_driver.v - 640x480 @ 60 Hz VGA timing for the DE1-SoC
//
// Everything runs on CLOCK_50. pix_en goes high every other clock,
// so the x/y counters step at 25 MHz (the pixel clock).
//
// One line  = 800 pixels: 640 visible + 16 front porch + 96 hsync + 48 back porch
// One frame = 525 lines : 480 visible + 10 front porch +  2 vsync + 33 back porch
// 800 x 525 x 60 frames/s = about 25 MHz
module vga_driver(clk, rst, vga_clk, hsync, vsync, blank_n, x, y, visible, new_frame);
  input clk;                 // CLOCK_50
  input rst;                 // active low
  output reg vga_clk;        // 25 MHz clock out to the VGA chip
  output reg hsync;          // active low
  output reg vsync;          // active low
  output reg blank_n;        // 0 = draw black (outside the visible area)
  output reg [9:0] x;        // 0..799, pixel being drawn
  output reg [9:0] y;        // 0..524, line being drawn
  output reg visible;        // 1 when (x, y) is on the 640x480 screen
  output reg new_frame;      // 1 for one clock at the start of each frame's blank time

  reg pix_en;

  // 25 MHz enable: toggles every 50 MHz clock
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
      pix_en <= 1'b0;
    else
      pix_en <= ~pix_en;
  end

  // x / y counters
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
    begin
      x <= 10'd0;
      y <= 10'd0;
    end
    else if (pix_en == 1'b1)
    begin
      if (x == 10'd799)
      begin
        x <= 10'd0;
        if (y == 10'd524)
          y <= 10'd0;
        else
          y <= y + 1'b1;
      end
      else
        x <= x + 1'b1;
    end
  end

  // sync, blank, and frame signals
  always @(*)
  begin
    vga_clk = pix_en;

    if (x >= 10'd656 && x < 10'd752)   // 640 + 16 = 656, 656 + 96 = 752
      hsync = 1'b0;
    else
      hsync = 1'b1;

    if (y >= 10'd490 && y < 10'd492)   // 480 + 10 = 490, 490 + 2 = 492
      vsync = 1'b0;
    else
      vsync = 1'b1;

    if (x < 10'd640 && y < 10'd480)
      visible = 1'b1;
    else
      visible = 1'b0;

    blank_n = visible;

    // safe time to move the ball/paddle: the screen just finished drawing
    if (x == 10'd0 && y == 10'd480 && pix_en == 1'b1)
      new_frame = 1'b1;
    else
      new_frame = 1'b0;
  end
endmodule
