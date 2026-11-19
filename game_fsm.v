// game_fsm.v - main control FSM for Brick Blaster (3 levels)
//
//   INIT        new game: 3 lives, score 0, level = starting level (SW[9:8])
//   LOAD        load the brick layout for the current level
//   SERVE       ball sits on the paddle until the player launches it
//   PLAY        ball in play
//   LOSE_LIFE   ball fell past the paddle: lives - 1
//   CHECK_LIVES out of lives? -> GAME_OVER, otherwise SERVE again
//   LEVEL_CLEAR all breakable bricks gone: park the ball on the paddle, then
//               last level? -> WIN, otherwise NEXT_LEVEL
//   NEXT_LEVEL  level + 1, then LOAD the new layout (lives and score carry over)
//   WIN         beat level 3
//   GAME_OVER   no lives left
//   WAIT_REL    after WIN / GAME_OVER the player presses launch to play again;
//               wait for the button to be released so the new game does not
//               launch the ball right away
//   ERROR       should never happen
module game_fsm(clk, rst, launch, start_level, ball_held, ball_lost, level_clear,
                S, lives, level, new_game, load_level, allow_launch, freeze,
                won, game_over);
  input clk;
  input rst;                  // active low
  input launch;               // 1 = launch button pressed
  input [1:0] start_level;    // from SW[9:8]: 0 = level 1, 1 = level 2, 2 or 3 = level 3
  input ball_held;            // 1 = ball is sitting on the paddle
  input ball_lost;            // 1 = ball just fell past the paddle
  input level_clear;          // 1 = no breakable bricks left
  output reg [3:0] S;         // current state (shown on LEDR for debugging)
  output reg [1:0] lives;     // 0..3
  output reg [1:0] level;     // 0..2 (shown as 1..3)
  output reg new_game;        // 1 = reset the score
  output reg load_level;      // 1 = load the brick layout for "level"
  output reg allow_launch;    // 1 = the ball is allowed to launch
  output reg freeze;          // 1 = hold the ball on the paddle
  output reg won;             // 1 = show the win screen
  output reg game_over;       // 1 = show the game over screen

  reg [3:0] NS;

  parameter INIT        = 4'b0000,
            LOAD        = 4'b0001,
            SERVE       = 4'b0010,
            PLAY        = 4'b0011,
            LOSE_LIFE   = 4'b0100,
            CHECK_LIVES = 4'b0101,
            LEVEL_CLEAR = 4'b0110,
            NEXT_LEVEL  = 4'b0111,
            WIN         = 4'b1000,
            GAME_OVER   = 4'b1001,
            WAIT_REL    = 4'b1010,
            ERROR       = 4'b1111;

  parameter LAST_LEVEL  = 2'd2;      // level 3

  // 1. state register
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
      S <= INIT;
    else
      S <= NS;
  end

  // 2. next-state logic
  always @(*)
  begin
    case (S)
      INIT:        NS = LOAD;
      LOAD:        NS = SERVE;
      SERVE:       if (ball_held == 1'b0) NS = PLAY; else NS = SERVE;    // ball was launched
      PLAY:        begin
                     if (level_clear == 1'b1)
                       NS = LEVEL_CLEAR;
                     else if (ball_lost == 1'b1)
                       NS = LOSE_LIFE;
                     else
                       NS = PLAY;
                   end
      LOSE_LIFE:   NS = CHECK_LIVES;
      CHECK_LIVES: if (lives == 2'd0) NS = GAME_OVER; else NS = SERVE;
      LEVEL_CLEAR: begin
                     if (ball_held == 1'b0)
                       NS = LEVEL_CLEAR;            // wait for the ball to be parked
                     else if (level == LAST_LEVEL)
                       NS = WIN;
                     else
                       NS = NEXT_LEVEL;
                   end
      NEXT_LEVEL:  NS = LOAD;
      WIN:         if (launch == 1'b1) NS = WAIT_REL; else NS = WIN;
      GAME_OVER:   if (launch == 1'b1) NS = WAIT_REL; else NS = GAME_OVER;
      WAIT_REL:    if (launch == 1'b0) NS = INIT; else NS = WAIT_REL;
      default:     NS = ERROR;
    endcase
  end

  // 3. registers each state changes
  always @(posedge clk or negedge rst)
  begin
    if (rst == 1'b0)
    begin
      lives <= 2'd3;
      level <= 2'd0;
    end
    else
    begin
      case (S)
        INIT:       begin
                      lives <= 2'd3;
                      if (start_level == 2'd3)
                        level <= LAST_LEVEL;       // SW = 11 also means level 3
                      else
                        level <= start_level;
                    end
        LOSE_LIFE:  lives <= lives - 1'b1;
        NEXT_LEVEL: level <= level + 1'b1;
        default:    begin lives <= lives; level <= level; end
      endcase
    end
  end

  // 4. outputs for each state
  always @(*)
  begin
    new_game = 1'b0; load_level = 1'b0; allow_launch = 1'b0;
    freeze = 1'b0;   won = 1'b0;        game_over = 1'b0;
    case (S)
      INIT:        begin new_game = 1'b1; freeze = 1'b1; end
      LOAD:        begin load_level = 1'b1; freeze = 1'b1; end
      SERVE:       allow_launch = 1'b1;
      PLAY:        ;
      LOSE_LIFE:   ;
      CHECK_LIVES: ;
      LEVEL_CLEAR: freeze = 1'b1;
      NEXT_LEVEL:  freeze = 1'b1;
      WIN:         begin won = 1'b1; freeze = 1'b1; end
      GAME_OVER:   begin game_over = 1'b1; freeze = 1'b1; end
      WAIT_REL:    freeze = 1'b1;
      default:     freeze = 1'b1;
    endcase
  end
endmodule
