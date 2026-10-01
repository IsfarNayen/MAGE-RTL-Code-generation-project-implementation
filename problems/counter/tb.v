module tb;
  reg clk, reset, enable;
  wire [3:0] q;
  reg [3:0] expected;
  integer i, total, mismatches;

  top_module dut (.clk(clk), .reset(reset), .enable(enable), .q(q));

  // Clock: a rising edge every 10 time units.
  always #5 clk = ~clk;

  // Reference model: what q SHOULD be after each rising edge.
  always @(posedge clk) begin
    if (reset) expected <= 4'd0;
    else if (enable) expected <= expected + 4'd1;
  end

  initial begin
    clk = 0; reset = 1; enable = 0;
    total = 0; mismatches = 0;

    for (i = 0; i < 60; i = i + 1) begin
      @(negedge clk);
      // Check the result of the previous rising edge.
      total = total + 1;
      if (q !== expected) begin
        mismatches = mismatches + 1;
        $display("MISMATCH time=%0t reset=%b enable=%b q=%0d expected=%0d",
                 $time, reset, enable, q, expected);
      end
      // Drive new inputs for the next rising edge.
      reset  = (i == 0) ? 1'b1 : (i == 35);
      enable = ($random & 3) != 0;   // enabled about 75% of the time
    end

    $display("RESULT total=%0d mismatches=%0d", total, mismatches);
    $finish;
  end
endmodule