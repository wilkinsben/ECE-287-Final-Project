module three_decimal_vals_w_neg (
    input  [7:0] val,
    output [6:0] seg7_neg_sign,
    output [6:0] seg7_lsb,      // Ones
    output [6:0] seg7_msb,      // Tens
    output [6:0] seg7_hsb       // Hundreds
);

    reg [3:0] result_one_digit;
    reg [3:0] result_ten_digit;
    reg [3:0] result_hundred_digit;
    reg       result_is_negative;
    reg [7:0] twos_comp;

    always @(*) begin
        // Check MSB (bit 7) for negative 2's complement
        if (val[7] == 1'b1) begin
            result_is_negative = 1'b1;
            twos_comp = ~val + 1'b1; // Convert to positive magnitude
        end else begin
            result_is_negative = 1'b0;
            twos_comp = val;
        end

        // Split decimal digits
        result_hundred_digit = twos_comp / 100;
        result_ten_digit     = (twos_comp % 100) / 10;
        result_one_digit     = twos_comp % 10;
    end

    /* Instantiate 7-segment decoders */
    seven_segment hsb (result_hundred_digit, seg7_hsb);
    seven_segment msb (result_ten_digit,     seg7_msb);
    seven_segment lsb (result_one_digit,     seg7_lsb);
    seven_segment_negative neg (result_is_negative, seg7_neg_sign);

endmodule