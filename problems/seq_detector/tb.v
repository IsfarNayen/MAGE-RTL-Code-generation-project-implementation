module tb;
  reg clk, reset, din;
  wire detected;
  reg expected;
  reg [2:0] hist;               // reference model: the last 3 bits seen
  integer i, total, mismatches;

  // Directed test vectors, 64 cycles. Bit 63 is cycle 0, bit 0 is cycle 63.
  reg [63:0] rst_vec;
  reg [63:0] din_vec;

  top_module dut (.clk(clk), .reset(reset), .din(din), .detected(detected));

  // Clock: a rising edge every 10 time units.
  always #5 clk = ~clk;

  // Reference model: what detected SHOULD be after each rising edge.
  always @(posedge clk) begin
    if (reset) begin
      hist     <= 3'b000;
      expected <= 1'b0;
    end else begin
      hist     <= {hist[1:0], din};
      expected <= ({hist, din} == 4'b1011);
    end
  end

  initial begin
    rst_vec = 64'b1000000000000000000000000000000000000000000000010001000000000000;
    din_vec = 64'b0000010110101101101010100101111101110011100101101011101100001011;

    clk = 0; reset = 1; din = 0;
    total = 0; mismatches = 0;

    for (i = 0; i < 100; i = i + 1) begin
      @(negedge clk);
      // Check the result of the previous rising edge.
      total = total + 1;
      if (detected !== expected) begin
        mismatches = mismatches + 1;
        $display("MISMATCH time=%0t reset=%b din=%b detected=%b expected=%b",
                 $time, reset, din, detected, expected);
      end
      // Drive new inputs for the next rising edge.
      if (i + 1 < 64) begin
        reset = rst_vec[63 - (i + 1)];
        din   = din_vec[63 - (i + 1)];
      end else begin
        reset = (($random & 15) == 0);   // occasional reset
        din   = $random & 1;             // random bits
      end
    end

    $display("RESULT total=%0d mismatches=%0d", total, mismatches);
    $finish;
  end
endmodule
