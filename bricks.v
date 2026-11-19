// bricks.v - the brick wall, the 3 level layouts, and brick collisions
//
// The wall is 10 x 5 bricks, each 64 x 16 pixels, starting at y = 32.
// Brick number n = row*10 + col  (row 0 = top row, col 0 = left column).
//   alive[n] = 1 : brick n is there
//   steel[n] = 1 : brick n is UNBREAKABLE (gray). It is "alive" but never cleared.
//
// Finding the brick under a point (x, y) is just a shift (sizes are powers of 2):
//   col = x / 64 = x[9:6]          row = (y - 32) / 16 = (y - 32)[6:4]
//
// COLLISIONS - two points on the ball are checked every frame:
//   V point: middle of the edge moving up/down     -> hit_y = flip up/down
//   H point: middle of the edge moving left/right  -> hit_x = flip left/right
// So the ball bounces correctly off the top/bottom AND the sides of bricks.
// A normal brick that is hit is cleared and scores a point; steel just bounces.
// If both points land in the SAME brick in the same frame (a corner), we work
// out which side the ball came in through: how far it is past the brick's side
// vs. past its top/bottom. The SMALLER one is the side it entered, so only
// that direction is flipped. Because bricks are 64 x 16, those distances are
// just the low bits of the position: x[5:0] and (y - 32)[3:0].
// steel_bounce = 1 when the ball bounces off a steel brick (ball.v uses it to
// change the angle a little, so the ball can't get stuck in a loop above steel).
module bricks(clk, rst, load, level, new_frame, active,
              ball_x, ball_y, dir_x, dir_y,
              alive, steel, hit_x, hit_y, steel_bounce, points, level_clear);
  input clk;
  input rst;                  // active low
  input load;                 // 1 = load the layout for "level"
  input [1:0] level;          // 0, 1, 2  (shown to the player as 1, 2, 3)
  input new_frame;            // 1 for one clock, 60 times a second
  input active;               // 1 = ball is in play (not sitting on the paddle)
  input [9:0] ball_x;         // top-left of the 8x8 ball
  input [9:0] ball_y;
  input dir_x;                // 1 = moving left, 0 = moving right
  input dir_y;                // 1 = moving up,   0 = moving down
  output reg [49:0] alive;
  output reg [49:0] steel;
  output reg hit_x;
  output reg hit_y;
  output reg steel_bounce;     // 1 = this bounce is off a steel brick
  output reg [1:0] points;    // normal bricks broken this frame (0, 1 or 2)
  output reg level_clear;     // 1 = no breakable bricks left

  parameter WALL_TOP    = 10'd32;
  parameter WALL_BOTTOM = 10'd112;    // 32 + 5 rows x 16

  // ------------------------------------------------------------------
  // LEVEL LAYOUTS: {row4, row3, row2, row1, row0}, 10 bits per row.
  // In each row the RIGHTMOST bit is column 0 (left side of the screen).
  // (All layouts are left/right symmetric, so they look the same written here.)
  // ------------------------------------------------------------------
  reg [49:0] start_bricks;    // bricks that are there at the start of the level
  reg [49:0] start_steel;     // which of those are unbreakable

  always @(*)
  begin
    case (level)
      2'd0:    begin   // LEVEL 1: full wall
                 start_bricks = {10'b1111111111, 10'b1111111111, 10'b1111111111,
                                 10'b1111111111, 10'b1111111111};
                 start_steel  = 50'd0;
               end
      2'd1:    begin   // LEVEL 2: pyramid behind a steel row with gaps
                 start_bricks = {10'b1100110011,      // row 4: steel with 2 gaps
                                 10'b0011001100,      // row 3: bricks right above the gaps
                                 10'b0011111100,      // row 2
                                 10'b0001111000,      // row 1
                                 10'b0000110000};     // row 0 (top)
                 start_steel  = {10'b1100110011, 10'b0000000000, 10'b0000000000,
                                 10'b0000000000, 10'b0000000000};
               end
      default: begin   // LEVEL 3: fortress - two steel pillars, open underneath
                 start_bricks = {10'b0010000100,      // row 4: bottom of the steel pillars
                                 10'b0011111100,      // row 3: inside the fortress
                                 10'b1111111111,      // row 2
                                 10'b1111111111,      // row 1
                                 10'b1111111111};     // row 0 (top)
                 start_steel  = {10'b0010000100,      // steel pillars in columns 2 and 7
                                 10'b0010000100,
                                 10'b0010000100,
                                 10'b0010000100,
                                 10'b0000000000};
               end
    endcase
  end

  // ------------------------------------------------------------------
  // COLLISION CHECK (two points on the ball)
  // ------------------------------------------------------------------
  reg [9:0] vx, vy, hx, hy;   // the V point and the H point
  reg [9:0] vrel, hrel;       // y measured from the top of the wall
  reg [5:0] v_idx, h_idx;     // brick number under each point
  reg v_in, h_in;             // point is inside the wall area
  reg v_break, h_break;       // a normal brick gets broken
  reg v_hit, h_hit;           // each point is inside a brick that is there
  reg [5:0] pen_x;            // how far the ball is past the brick's side (0..63)
  reg [5:0] pen_y;            // how far the ball is past the brick's top/bottom (0..15)

  always @(*)
  begin
    // V point: middle of the top edge (going up) or bottom edge (going down)
    vx = ball_x + 10'd4;
    if (dir_y == 1'b1) vy = ball_y; else vy = ball_y + 10'd7;
    // H point: middle of the left edge (going left) or right edge (going right)
    hy = ball_y + 10'd4;
    if (dir_x == 1'b1) hx = ball_x; else hx = ball_x + 10'd7;

    vrel  = vy - WALL_TOP;
    hrel  = hy - WALL_TOP;
    v_idx = {vrel[6:4], 3'b000} + {vrel[6:4], 1'b0} + vx[9:6];   // row*10 + col
    h_idx = {hrel[6:4], 3'b000} + {hrel[6:4], 1'b0} + hx[9:6];

    if (vy >= WALL_TOP && vy < WALL_BOTTOM && vx < 10'd640) v_in = 1'b1; else v_in = 1'b0;
    if (hy >= WALL_TOP && hy < WALL_BOTTOM && hx < 10'd640) h_in = 1'b1; else h_in = 1'b0;

    if (active == 1'b1 && v_in == 1'b1 && alive[v_idx] == 1'b1) v_hit = 1'b1; else v_hit = 1'b0;
    if (active == 1'b1 && h_in == 1'b1 && alive[h_idx] == 1'b1) h_hit = 1'b1; else h_hit = 1'b0;

    // distance past the edge it is crossing
    if (dir_x == 1'b0) pen_x = hx[5:0];               // moving right: past the left side
    else               pen_x = 6'd63 - hx[5:0];       // moving left:  past the right side
    if (dir_y == 1'b0) pen_y = {2'b00, vrel[3:0]};          // moving down: past the top
    else               pen_y = 6'd15 - {2'b00, vrel[3:0]};  // moving up:   past the bottom

    if (v_hit == 1'b1 && h_hit == 1'b1 && v_idx == h_idx)
    begin
      // both points in the same brick: flip only the side it came in through
      if (pen_x < pen_y)
      begin
        hit_x = 1'b1;  hit_y = 1'b0;                 // came in through the side
      end
      else
      begin
        hit_x = 1'b0;  hit_y = 1'b1;                 // came in through the top/bottom
      end
    end
    else
    begin
      hit_x = h_hit;
      hit_y = v_hit;
    end

    if ((hit_y == 1'b1 && steel[v_idx] == 1'b1) || (hit_x == 1'b1 && steel[h_idx] == 1'b1))
      steel_bounce = 1'b1;
    else
      steel_bounce = 1'b0;

    if (hit_y == 1'b1 && steel[v_idx] == 1'b0) v_break = 1'b1; else v_break = 1'b0;
    if (hit_x == 1'b1 && steel[h_idx] == 1'b0)
      h_break = 1'b1;
    else
      h_break = 1'b0;

    points = {1'b0, v_break} + {1'b0, h_break};

    if ((alive & ~steel) == 50'd0) level_clear = 1'b1; else level_clear = 1'b0;
  end

  // ------------------------------------------------------------------
  // BRICK REGISTERS
  // ------------------------------------------------------------------
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
    begin
      alive <= 50'd0;                         // game FSM loads level 1 right after reset
      steel <= 50'd0;
    end
    else if (load == 1'b1)
    begin
      alive <= start_bricks;
      steel <= start_steel;
    end
    else if (new_frame == 1'b1)
    begin
      if (v_break == 1'b1) alive[v_idx] <= 1'b0;
      if (h_break == 1'b1) alive[h_idx] <= 1'b0;
    end
  end
endmodule
