// brick_blaster.v - TOP MODULE, week 5: 3 levels + unbreakable bricks
//   KEY[0] = reset (active low)
//   KEY[3] = move left, KEY[2] = move right   (KEY[3] is the leftmost button)
//   KEY[1] = launch the ball / start a new game after WIN or GAME OVER
//   SW[9:8] = starting level for the NEXT new game (00 = 1, 01 = 2, 10 or 11 = 3)
//   SW[0]  = 1 shows color stripes (VGA test pattern)
//   HEX5 HEX4 = "L" and lives left (3 to 0)
//   HEX3      = level (1 to 3)
//   HEX2 HEX1 HEX0 = score (hundreds digit stays blank until 100)
//   on screen: lives = yellow squares top-left, level = white squares top-right
//   background turns GREEN after beating level 3, RED on game over
//   LEDR[3:0] = game FSM state (debug),  LEDR[9] = level cleared,  LEDR[8] = ball held
module brick_blaster(CLOCK_50, KEY, SW, LEDR,
                   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
                   VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS,
                   VGA_CLK, VGA_BLANK_N, VGA_SYNC_N);
  input CLOCK_50;
  input [3:0] KEY;
  input [9:0] SW;
  output reg [9:0] LEDR;
  output [6:0] HEX0, HEX1, HEX3, HEX4;
  output reg [6:0] HEX2, HEX5;
  output reg [7:0] VGA_R, VGA_G, VGA_B;
  output VGA_HS, VGA_VS, VGA_CLK, VGA_BLANK_N;
  output reg VGA_SYNC_N;

  wire [9:0] x, y;
  wire visible, new_frame;
  wire [9:0] paddle_x;
  wire [9:0] ball_x, ball_y;
  wire ball_dir_x, ball_dir_y;
  wire ball_held, ball_lost;
  wire [49:0] brick_alive, brick_steel;
  wire hit_x, hit_y, steel_bounce, level_clear;
  wire [1:0] points;
  wire [3:0] game_state;
  wire [1:0] lives, level;
  wire new_game, load_level, allow_launch, freeze, won, game_over;
  reg  [3:0] score_ones, score_tens, score_hund;   // score kept as decimal digits
  wire [6:0] hund_seg;

  // screen sizes (change these in one place)
  parameter PADDLE_Y = 10'd440;   // top of paddle
  parameter PADDLE_W = 10'd64;
  parameter PADDLE_H = 10'd8;
  parameter BALL_S   = 10'd8;     // ball is 8x8
  parameter WALL_TOP = 10'd32;    // bricks: 10 x 5, each 64 x 16
  parameter WALL_BOT = 10'd112;

  vga_driver my_vga(CLOCK_50, KEY[0], VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_N,
                    x, y, visible, new_frame);

  // KEYs are active low (0 when pressed), so flip them
  paddle my_paddle(CLOCK_50, KEY[0], new_frame, ~KEY[3], ~KEY[2], paddle_x);

  game_fsm my_game(CLOCK_50, KEY[0], ~KEY[1], SW[9:8], ball_held, ball_lost, level_clear,
                   game_state, lives, level, new_game, load_level, allow_launch, freeze,
                   won, game_over);

  // the ball can only launch when the game FSM is in SERVE
  ball my_ball(CLOCK_50, KEY[0], new_frame, ~KEY[1] & allow_launch, paddle_x, hit_y, hit_x, steel_bounce, freeze,
               ball_x, ball_y, ball_dir_x, ball_dir_y, ball_held, ball_lost);

  bricks my_bricks(CLOCK_50, KEY[0], load_level, level, new_frame, ~ball_held,
                   ball_x, ball_y, ball_dir_x, ball_dir_y,
                   brick_alive, brick_steel, hit_x, hit_y, steel_bounce, points, level_clear);

  // score: +1 for every brick broken (can be 2 in one frame), kept in decimal
  always @(posedge CLOCK_50 or negedge KEY[0])
  begin
    if (KEY[0] == 1'b0)
    begin
      score_ones <= 4'd0;
      score_tens <= 4'd0;
      score_hund <= 4'd0;
    end
    else if (new_game == 1'b1)
    begin
      score_ones <= 4'd0;
      score_tens <= 4'd0;
      score_hund <= 4'd0;
    end
    else if (new_frame == 1'b1 && points != 2'd0)
    begin
      if (score_ones + points >= 4'd10)
      begin
        score_ones <= score_ones + points - 4'd10;      // carry into the tens
        if (score_tens == 4'd9)
        begin
          score_tens <= 4'd0;
          score_hund <= score_hund + 1'b1;
        end
        else
          score_tens <= score_tens + 1'b1;
      end
      else
        score_ones <= score_ones + points;
    end
  end

  seven_segment hex_ones(score_ones, HEX0);
  seven_segment hex_tens(score_tens, HEX1);
  seven_segment hex_hund(score_hund, hund_seg);
  seven_segment hex_level({2'b00, level} + 4'd1, HEX3);   // show level 1..3
  seven_segment hex_lives({2'b00, lives}, HEX4);

  // which brick is the pixel being drawn in?
  reg [9:0] wall_y;
  reg [5:0] pix_brick;
  reg       draw_brick;
  reg       draw_lives, draw_level;

  always @(*)
  begin
    wall_y    = y - WALL_TOP;
    pix_brick = {wall_y[6:4], 3'b000} + {wall_y[6:4], 1'b0} + x[9:6];   // row*10 + col

    // inside the wall, brick there, and not on the 1-pixel edge (makes a gap)
    if (y >= WALL_TOP && y < WALL_BOT && x < 10'd640 &&
        brick_alive[pix_brick] == 1'b1 &&
        x[5:0] != 6'd0 && x[5:0] != 6'd63 &&
        wall_y[3:0] != 4'd0 && wall_y[3:0] != 4'd15)
      draw_brick = 1'b1;
    else
      draw_brick = 1'b0;

    // small squares in the strip above the bricks (y = 10..21)
    // lives: yellow squares on the left,  level: white squares on the right
    if (y >= 10'd10 && y < 10'd22 &&
        ((lives >= 2'd1 && x >= 10'd8  && x < 10'd20) ||
         (lives >= 2'd2 && x >= 10'd28 && x < 10'd40) ||
         (lives >= 2'd3 && x >= 10'd48 && x < 10'd60)))
      draw_lives = 1'b1;
    else
      draw_lives = 1'b0;

    if (y >= 10'd10 && y < 10'd22 &&
        ((                 x >= 10'd620 && x < 10'd632) ||
         (level >= 2'd1 && x >= 10'd600 && x < 10'd612) ||
         (level >= 2'd2 && x >= 10'd580 && x < 10'd592)))
      draw_level = 1'b1;
    else
      draw_level = 1'b0;
  end

  // pick a color for every pixel
  always @(*)
  begin
    VGA_SYNC_N = 1'b0;            // not used on the DE1-SoC, tie low
    if (score_hund == 4'd0)
      HEX2 = 7'b1111111;          // hide the hundreds digit until the score reaches 100
    else
      HEX2 = hund_seg;
    HEX5 = 7'b1000111;            // the letter "L" (for lives)
    LEDR = {level_clear, ball_held, 4'b0000, game_state};   // debug lights

    if (visible == 1'b0)
    begin
      VGA_R = 8'd0;   VGA_G = 8'd0;   VGA_B = 8'd0;       // black during blanking
    end
    else if (SW[0] == 1'b1)
    begin
      VGA_R = {8{x[7]}};  VGA_G = {8{x[8]}};  VGA_B = {8{x[6]}};   // color stripes
    end
    else if (x >= ball_x && x < ball_x + BALL_S &&
             y >= ball_y && y < ball_y + BALL_S)
    begin
      VGA_R = 8'd255; VGA_G = 8'd220; VGA_B = 8'd0;       // yellow ball
    end
    else if (x >= paddle_x && x < paddle_x + PADDLE_W &&
             y >= PADDLE_Y && y < PADDLE_Y + PADDLE_H)
    begin
      VGA_R = 8'd255; VGA_G = 8'd255; VGA_B = 8'd255;     // white paddle
    end
    else if (draw_brick == 1'b1 && brick_steel[pix_brick] == 1'b1)
    begin
      VGA_R = 8'd150; VGA_G = 8'd150; VGA_B = 8'd165;     // gray steel brick (unbreakable)
    end
    else if (draw_brick == 1'b1)
    begin
      case (wall_y[6:4])                                  // a color for each row
        3'd0:    begin VGA_R = 8'd220; VGA_G = 8'd40;  VGA_B = 8'd40;  end   // red
        3'd1:    begin VGA_R = 8'd240; VGA_G = 8'd130; VGA_B = 8'd20;  end   // orange
        3'd2:    begin VGA_R = 8'd60;  VGA_G = 8'd200; VGA_B = 8'd80;  end   // green
        3'd3:    begin VGA_R = 8'd40;  VGA_G = 8'd180; VGA_B = 8'd230; end   // light blue
        default: begin VGA_R = 8'd170; VGA_G = 8'd80;  VGA_B = 8'd220; end   // purple
      endcase
    end
    else if (draw_lives == 1'b1)
    begin
      VGA_R = 8'd255; VGA_G = 8'd220; VGA_B = 8'd0;       // lives (yellow)
    end
    else if (draw_level == 1'b1)
    begin
      VGA_R = 8'd255; VGA_G = 8'd255; VGA_B = 8'd255;     // level (white)
    end
    else if (won == 1'b1)
    begin
      VGA_R = 8'd0;   VGA_G = 8'd110; VGA_B = 8'd40;      // green background: you win
    end
    else if (game_over == 1'b1)
    begin
      VGA_R = 8'd130; VGA_G = 8'd0;   VGA_B = 8'd0;       // red background: game over
    end
    else
    begin
      VGA_R = 8'd0;   VGA_G = 8'd0;   VGA_B = 8'd120;     // dark blue background
    end
  end
endmodule
