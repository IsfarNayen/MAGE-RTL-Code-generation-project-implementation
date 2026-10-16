module top_module(input clk, input reset, input din, output reg detected);
    reg [2:0] hist;
    always @(posedge clk) begin
        if (reset) begin
            hist <= 3'b000;
            detected <= 1'b0;
        end else begin
            hist <= {hist[1:0], din};
            detected <= ({hist, din} == 4'b1011);
        end
    end
endmodule
