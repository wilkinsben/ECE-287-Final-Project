// paddle.v - moves the paddle left/right once per frame and stops at the edges
//
// paddle_x is the LEFT edge of the paddle. The paddle is 64 pixels wide,
// so paddle_x can go from 0 to 576 (640 - 64).
// At 4 pixels per frame x 60 frames/s = 240 pixels/s (about 2.5 s edge to edge).
module paddle(clk, rst, new_frame, left, right, paddle_x);
  input clk;
  input rst;                  // active low
  input new_frame;            // 1 for one clock, 60 times a second
  input left;                 // 1 = move left  (button pressed)
  input right;                // 1 = move right (button pressed)
  output reg [9:0] paddle_x;

  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
      paddle_x <= 10'd288;                        // start in the middle
    else if (new_frame == 1'b1)
    begin
      if (left == 1'b1 && right == 1'b0)
      begin
        if (paddle_x >= 10'd4)
          paddle_x <= paddle_x - 10'd4;
        else
          paddle_x <= 10'd0;                      // stop at left wall
      end
      else if (right == 1'b1 && left == 1'b0)
      begin
        if (paddle_x <= 10'd572)
          paddle_x <= paddle_x + 10'd4;
        else
          paddle_x <= 10'd576;                    // stop at right wall
      end
      // both or neither pressed: stay put
    end
  end
endmodule
