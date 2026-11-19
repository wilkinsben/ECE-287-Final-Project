module seven_segment_negative(i,o);

input i;
output reg [6:0]o; // a, b, c, d, e, f, g

always @(*)
	begin 
	
	if (i) begin 
		o = 7'b0111111;
    end 
	 
	 else begin
      o = 7'b1111111;
	 end
end

endmodule