// ball.v - moves the ball once per frame, bounces off walls and the paddle
//
// ball_x, ball_y = TOP-LEFT corner of an 8x8 ball.
// Each axis has a DIRECTION bit and a SPEED (pixels per frame):
//   dir_x: 0 = moving right, 1 = moving left
//   dir_y: 0 = moving down,  1 = moving up
//
// "held" = ball is sitting on the paddle waiting for launch.
// Paddle ZONES (paddle is 64 wide, split into 4 zones of 16 pixels):
//   zone 0 (far left)  -> left,  shallow  (spd_x 3, spd_y 2)
//   zone 1             -> left,  steep    (spd_x 1, spd_y 3)
//   zone 2             -> right, steep    (spd_x 1, spd_y 3)
//   zone 3 (far right) -> right, shallow  (spd_x 3, spd_y 2)
// Missing the paddle: "lost" pulses for one frame and the ball goes back
// onto the paddle (held) until launch is pressed again.
// brick_hit_y / brick_hit_x (from bricks.v): the ball hit a brick on its
// top/bottom (flip dir_y) or on its side (flip dir_x) this frame.
// freeze (from game_fsm.v): keep the ball on the paddle (game over / win).
// steel_bounce (from bricks.v): bounced off a steel brick, so pick a new
// sideways speed (2, 3, 4 or 6) from an LFSR. The same happens when the ball
// bounces off the ceiling. This changes the angle a little so the ball can't
// get stuck in a repeating path (above the steel, or missing the last bricks).
module ball(clk, rst, new_frame, launch, paddle_x, brick_hit_y, brick_hit_x, steel_bounce, freeze,
            ball_x, ball_y, dir_x, dir_y, held, lost);
  input clk;
  input rst;                  // active low
  input new_frame;            // 1 for one clock, 60 times a second
  input launch;               // 1 = launch button pressed
  input [9:0] paddle_x;       // left edge of the paddle
  input brick_hit_y;          // 1 = hit the top/bottom of a brick this frame
  input brick_hit_x;          // 1 = hit the side of a brick this frame
  input steel_bounce;         // 1 = the brick hit was steel
  input freeze;               // 1 = hold the ball on the paddle
  output reg [9:0] ball_x;
  output reg [9:0] ball_y;
  output reg dir_x;
  output reg dir_y;
  output reg held;
  output reg lost;

  reg [2:0] spd_x;
  reg [7:0] lfsr;             // pseudo-random numbers for steel bounces
  reg [2:0] random_spd_x;
  reg [2:0] spd_y;

  parameter MAX_X    = 10'd632;   // 640 - 8 (ball width)
  parameter BOTTOM   = 10'd472;   // 480 - 8: ball is gone past here
  parameter PADDLE_Y = 10'd440;   // top of paddle (must match top module)
  parameter PADDLE_W = 10'd64;

  // ---------- which paddle zone is under the ball's center? ----------
  reg [9:0] center;               // middle of the ball
  reg [9:0] offset;               // center - paddle_x
  reg [1:0] zone;
  reg over_paddle;                // ball overlaps the paddle left/right
  reg crossing;                   // ball's bottom crosses paddle top this frame

  always @(*)
  begin
    center = ball_x + 10'd4;

    if (center <= paddle_x)
      offset = 10'd0;
    else
      offset = center - paddle_x;

    if (offset >= 10'd63)
      zone = 2'd3;
    else
      zone = offset[5:4];         // divide by 16 = shift right by 4

    if (ball_x + 10'd8 > paddle_x && ball_x < paddle_x + PADDLE_W)
      over_paddle = 1'b1;
    else
      over_paddle = 1'b0;

    if (dir_y == 1'b0 && ball_y + 10'd8 <= PADDLE_Y &&
        ball_y + 10'd8 + spd_y >= PADDLE_Y)
      crossing = 1'b1;
    else
      crossing = 1'b0;
  end

  // ---------- LFSR: a new pseudo-random number every clock ----------
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
      lfsr <= 8'b1010_1101;                        // any non-zero seed
    else
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
  end

  always @(*)
  begin
    case (lfsr[1:0])
      2'd0:    random_spd_x = 3'd2;
      2'd1:    random_spd_x = 3'd3;
      2'd2:    random_spd_x = 3'd4;
      default: random_spd_x = 3'd6;
    endcase
  end

  // ---------- move the ball ----------
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
    begin
      held   <= 1'b1;
      lost   <= 1'b0;
      ball_x <= 10'd316;
      ball_y <= PADDLE_Y - 10'd8;
      dir_x  <= 1'b0;
      dir_y  <= 1'b1;
      spd_x  <= 3'd2;
      spd_y  <= 3'd6;
    end
    else if (new_frame == 1'b1)
    begin
      lost <= 1'b0;

      if (freeze == 1'b1)
      begin
        // game over or won: park the ball on the paddle
        held   <= 1'b1;
        ball_x <= paddle_x + 10'd28;
        ball_y <= PADDLE_Y - 10'd8;
      end
      else if (held == 1'b1)
      begin
        // ride on top of the paddle, centered
        ball_x <= paddle_x + 10'd28;
        ball_y <= PADDLE_Y - 10'd8;
        if (launch == 1'b1)
        begin
          held  <= 1'b0;
          dir_x <= 1'b0;           // launch up and to the right, steep
          dir_y <= 1'b1;
          spd_x <= 3'd2;
          spd_y <= 3'd6;
        end
      end
      else
      begin
        // ---------- x: side of a brick, side walls ----------
        if (brick_hit_x == 1'b1)
        begin
          // hit the side of a brick: turn around and move away from it
          dir_x <= ~dir_x;
          if (steel_bounce == 1'b1)
            spd_x <= random_spd_x;                    // steel: new random angle
          if (dir_x == 1'b0)                          // was going right, now left
          begin
            if (ball_x <= spd_x) ball_x <= 10'd0; else ball_x <= ball_x - spd_x;
          end
          else                                        // was going left, now right
          begin
            if (ball_x + spd_x >= MAX_X) ball_x <= MAX_X; else ball_x <= ball_x + spd_x;
          end
        end
        else if (dir_x == 1'b0)
        begin
          if (ball_x + spd_x >= MAX_X)
          begin
            ball_x <= MAX_X;
            dir_x  <= 1'b1;
          end
          else
            ball_x <= ball_x + spd_x;
        end
        else
        begin
          if (ball_x <= spd_x)
          begin
            ball_x <= 10'd0;
            dir_x  <= 1'b0;
          end
          else
            ball_x <= ball_x - spd_x;
        end

        // ---------- y: bricks, top wall, paddle, bottom ----------
        if (brick_hit_y == 1'b1)
        begin
          // hit the top/bottom of a brick: turn around and move away from it
          dir_y <= ~dir_y;
          if (steel_bounce == 1'b1 && brick_hit_x == 1'b0)
            spd_x <= random_spd_x;                    // steel: new random angle
          if (dir_y == 1'b1)
            ball_y <= ball_y + spd_y;                 // was going up, now down
          else if (ball_y <= spd_y)
            ball_y <= 10'd0;
          else
            ball_y <= ball_y - spd_y;                 // was going down, now up
        end
        else if (dir_y == 1'b1)                       // moving up
        begin
          if (ball_y <= spd_y)
          begin
            ball_y <= 10'd0;                          // top wall
            dir_y  <= 1'b0;
            spd_x  <= random_spd_x;                   // ceiling: new random angle
          end
          else
            ball_y <= ball_y - spd_y;
        end
        else if (crossing == 1'b1 && over_paddle == 1'b1)
        begin
          // hit the paddle: sit on top of it and bounce by zone
          ball_y <= PADDLE_Y - 10'd8;
          dir_y  <= 1'b1;
          if (zone == 2'd0)      begin dir_x <= 1'b1; spd_x <= 3'd6; spd_y <= 3'd4; end
          else if (zone == 2'd1) begin dir_x <= 1'b1; spd_x <= 3'd2; spd_y <= 3'd6; end
          else if (zone == 2'd2) begin dir_x <= 1'b0; spd_x <= 3'd2; spd_y <= 3'd6; end
          else                   begin dir_x <= 1'b0; spd_x <= 3'd6; spd_y <= 3'd4; end
        end
        else if (ball_y + spd_y >= BOTTOM)
        begin
          // missed the paddle: lost the ball
          lost <= 1'b1;
          held <= 1'b1;
        end
        else
          ball_y <= ball_y + spd_y;
      end
    end
  end
endmodule
