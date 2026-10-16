`timescale 1ns/1ps
module tb;
  // ---------------- DUT I/O ----------------
  reg         clk, reset, start, cfg_we, cfg_lock, kick_valid, clr_err;
  reg  [15:0] cfg_timeout, cfg_window;
  reg  [1:0]  cfg_prescale;
  reg  [7:0]  kick_data;

  wire [15:0] count;
  wire        running, bark, bite, locked, kick_err, warn;
  wire [2:0]  bite_count;

  top_module dut (
    .clk(clk), .reset(reset), .start(start),
    .cfg_we(cfg_we), .cfg_timeout(cfg_timeout), .cfg_window(cfg_window),
    .cfg_prescale(cfg_prescale), .cfg_lock(cfg_lock),
    .kick_valid(kick_valid), .kick_data(kick_data), .clr_err(clr_err),
    .count(count), .running(running), .bark(bark), .bite(bite),
    .locked(locked), .kick_err(kick_err), .bite_count(bite_count), .warn(warn)
  );

  // Clock: a rising edge every 10 time units.
  always #5 clk = ~clk;

  // ---------------- Reference model ----------------
  reg [15:0] m_timeout, m_window, m_count;
  reg [1:0]  m_prescale, m_bite_cnt;
  reg [7:0]  m_tick;
  reg        m_armed, m_running, m_bark, m_bite, m_locked, m_kick_err, m_fire;
  reg [2:0]  m_bite_count;
  wire       m_warn = m_running & ~m_bark & (m_count < (m_timeout >> 2));

  // Coverage counters
  integer cov_bark, cov_bite_timeout, cov_bite_early, cov_service, cov_arm,
          cov_bad, cov_start, cov_start_ign, cov_kick_idle, cov_cfg, cov_cfg_blk,
          cov_lock, cov_clr, cov_set_clr, cov_warn, cov_sat, cov_svc_bark,
          cov_svc_edge, cov_presc0, cov_presc1, cov_presc2, cov_presc3, cov_reset_run;

  function [7:0] dm1;   // D-1 for a prescale select
    input [1:0] p;
    case (p)
      2'd0: dm1 = 8'd0;
      2'd1: dm1 = 8'd3;
      2'd2: dm1 = 8'd15;
      default: dm1 = 8'd63;
    endcase
  endfunction

  task m_enter_bite;
    begin
      m_bite <= 1'b1; m_bite_cnt <= 2'd0; m_running <= 1'b0; m_count <= 16'd0;
      m_bark <= 1'b0; m_armed <= 1'b0; m_tick <= 8'd0;
      if (m_bite_count != 3'd7) m_bite_count <= m_bite_count + 3'd1;
      else cov_sat = cov_sat + 1;
    end
  endtask

  always @(posedge clk) begin
    if (reset) begin
      if (m_running === 1'b1) cov_reset_run = cov_reset_run + 1;
      m_timeout <= 16'd30; m_window <= 16'hFFFF; m_prescale <= 2'd0;
      m_tick <= 8'd0; m_armed <= 1'b0; m_bite_cnt <= 2'd0;
      m_count <= 16'd0; m_running <= 1'b0; m_bark <= 1'b0; m_bite <= 1'b0;
      m_locked <= 1'b0; m_kick_err <= 1'b0; m_bite_count <= 3'd0;
    end else begin
      // Rule A
      if (cfg_we) begin
        if (!m_locked) begin
          m_timeout <= cfg_timeout; m_window <= cfg_window; m_prescale <= cfg_prescale;
          cov_cfg = cov_cfg + 1;
        end else cov_cfg_blk = cov_cfg_blk + 1;
      end
      // Rule B
      if (cfg_lock) begin m_locked <= 1'b1; cov_lock = cov_lock + 1; end
      // Rule C
      if (clr_err) begin m_kick_err <= 1'b0; cov_clr = cov_clr + 1; end
      // Rule D
      if (m_bite) begin
        if (start) cov_start_ign = cov_start_ign + 1;
        if (m_bite_cnt == 2'd3) begin m_bite <= 1'b0; m_bite_cnt <= 2'd0; end
        else m_bite_cnt <= m_bite_cnt + 2'd1;
      end else if (!m_running) begin
        if (kick_valid) cov_kick_idle = cov_kick_idle + 1;
        if (start) begin
          m_running <= 1'b1; m_count <= m_timeout; m_tick <= 8'd0;
          m_bark <= 1'b0; m_armed <= 1'b0;
          cov_start = cov_start + 1;
        end
      end else begin
        if (start) cov_start_ign = cov_start_ign + 1;
        case (m_prescale)
          2'd0: cov_presc0 = cov_presc0 + 1;
          2'd1: cov_presc1 = cov_presc1 + 1;
          2'd2: cov_presc2 = cov_presc2 + 1;
          default: cov_presc3 = cov_presc3 + 1;
        endcase
        m_fire = 1'b0;
        if (kick_valid) begin
          if (kick_data == 8'hA5) begin
            m_armed <= 1'b1; cov_arm = cov_arm + 1;
          end else if (kick_data == 8'h5A && m_armed) begin
            m_fire = 1'b1; m_armed <= 1'b0;
            if (m_count > m_window) begin
              m_kick_err <= 1'b1; m_enter_bite;
              cov_bite_early = cov_bite_early + 1;
              if (clr_err) cov_set_clr = cov_set_clr + 1;
            end else begin
              m_count <= m_timeout; m_tick <= 8'd0; m_bark <= 1'b0;
              cov_service = cov_service + 1;
              if (m_bark) cov_svc_bark = cov_svc_bark + 1;
              if (m_count == m_window) cov_svc_edge = cov_svc_edge + 1;
            end
          end else begin
            m_armed <= 1'b0; m_kick_err <= 1'b1; cov_bad = cov_bad + 1;
            if (clr_err) cov_set_clr = cov_set_clr + 1;
          end
        end
        if (!m_fire) begin
          if (m_tick >= dm1(m_prescale)) begin
            m_tick <= 8'd0;
            if (m_count != 16'd0) m_count <= m_count - 16'd1;
            else if (!m_bark) begin
              m_bark <= 1'b1; m_count <= m_timeout; cov_bark = cov_bark + 1;
            end else begin
              m_enter_bite; cov_bite_timeout = cov_bite_timeout + 1;
            end
          end else m_tick <= m_tick + 8'd1;
        end
      end
    end
  end

  // ---------------- Checker (on falling edge) ----------------
  integer total, mismatches;
  always @(negedge clk) begin
    total = total + 1;
    if (m_warn === 1'b1) cov_warn = cov_warn + 1;
    if ({count, running, bark, bite, locked, kick_err, bite_count, warn} !==
        {m_count, m_running, m_bark, m_bite, m_locked, m_kick_err, m_bite_count, m_warn}) begin
      mismatches = mismatches + 1;
      if (mismatches <= 25)
        $display("MISMATCH time=%0t | DUT cnt=%0d run=%b bark=%b bite=%b lock=%b err=%b bcnt=%0d warn=%b | EXP cnt=%0d run=%b bark=%b bite=%b lock=%b err=%b bcnt=%0d warn=%b",
                 $time, count, running, bark, bite, locked, kick_err, bite_count, warn,
                 m_count, m_running, m_bark, m_bite, m_locked, m_kick_err, m_bite_count, m_warn);
    end
  end

  // ---------------- Stimulus helpers ----------------
  // Every helper waits for a falling edge, clears all pulse inputs, then drives
  // its own inputs for the next rising edge. cfg_* data values are kept.
  task clear_inputs;
    begin
      reset = 0; start = 0; cfg_we = 0; cfg_lock = 0;
      kick_valid = 0; kick_data = 8'h00; clr_err = 0;
    end
  endtask

  task idle(input integer n);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) begin @(negedge clk); clear_inputs; end
    end
  endtask

  task do_reset;
    begin @(negedge clk); clear_inputs; reset = 1; @(negedge clk); clear_inputs; reset = 1; end
  endtask

  task configure(input [15:0] t, input [15:0] w, input [1:0] p);
    begin
      @(negedge clk); clear_inputs;
      cfg_we = 1; cfg_timeout = t; cfg_window = w; cfg_prescale = p;
    end
  endtask

  task pulse_start; begin @(negedge clk); clear_inputs; start = 1; end endtask
  task pulse_lock;  begin @(negedge clk); clear_inputs; cfg_lock = 1; end endtask
  task pulse_clr;   begin @(negedge clk); clear_inputs; clr_err = 1; end endtask

  task send_key(input [7:0] k);
    begin @(negedge clk); clear_inputs; kick_valid = 1; kick_data = k; end
  endtask

  task kick; begin send_key(8'hA5); send_key(8'h5A); end endtask

  // Wait (using the golden model, so a broken DUT can't hang the TB).
  task wait_count_eq(input [15:0] v);
    integer g;
    begin
      g = 0;
      @(negedge clk); clear_inputs;
      while (!(m_running && m_count == v) && g < 5000) begin
        @(negedge clk); clear_inputs; g = g + 1;
      end
    end
  endtask

  task wait_bark;
    integer g;
    begin
      g = 0;
      @(negedge clk); clear_inputs;
      while (!m_bark && g < 5000) begin @(negedge clk); clear_inputs; g = g + 1; end
    end
  endtask

  task wait_idle;   // until bite pulse is over and the timer is stopped
    integer g;
    begin
      g = 0;
      @(negedge clk); clear_inputs;
      while ((m_bite || m_running) && g < 20000) begin @(negedge clk); clear_inputs; g = g + 1; end
    end
  endtask

  // ---------------- Test sequence ----------------
  integer i, p, seed, rcycles, r;

  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 20261008;
    if (!$value$plusargs("cycles=%d", rcycles)) rcycles = 30000;

    clk = 0; clear_inputs; reset = 1;
    cfg_timeout = 0; cfg_window = 0; cfg_prescale = 0;
    total = 0; mismatches = 0;
    cov_bark = 0; cov_bite_timeout = 0; cov_bite_early = 0; cov_service = 0;
    cov_arm = 0; cov_bad = 0; cov_start = 0; cov_start_ign = 0; cov_kick_idle = 0;
    cov_cfg = 0; cov_cfg_blk = 0; cov_lock = 0; cov_clr = 0; cov_set_clr = 0;
    cov_warn = 0; cov_sat = 0; cov_svc_bark = 0; cov_svc_edge = 0;
    cov_presc0 = 0; cov_presc1 = 0; cov_presc2 = 0; cov_presc3 = 0; cov_reset_run = 0;

    // T1: reset defaults, kicks while idle are ignored
    do_reset; idle(3);
    send_key(8'h33); send_key(8'hA5); send_key(8'h5A); idle(2);

    // T2: default timeout (30) runs out -> bark -> bite, no kicks
    pulse_start; wait_idle; idle(3);

    // T3: start pressed during bite and while running (both ignored)
    configure(16'd2, 16'hFFFF, 2'd0); pulse_start; idle(6);
    pulse_start; pulse_start; pulse_start; wait_idle;

    // T4: periodic valid kicks keep it alive; split key with a gap
    configure(16'd20, 16'hFFFF, 2'd0); pulse_start;
    for (i = 0; i < 12; i = i + 1) begin idle(8); kick; end
    send_key(8'hA5); idle(3); send_key(8'hA5); idle(2); send_key(8'h5A);
    pulse_start; idle(5);

    // T5: bad keys, kick_err sticky, clear, and set-beats-clear
    send_key(8'h33); idle(2); pulse_clr; idle(1);
    send_key(8'h5A);                           // 5A without A5 -> bad
    pulse_clr;
    @(negedge clk); clear_inputs; clr_err = 1; kick_valid = 1; kick_data = 8'h77;
    send_key(8'hA5); send_key(8'h12); send_key(8'h5A);   // arm, disarm, bad
    pulse_clr; kick;
    wait_idle;

    // T6: window -- early kick bites; boundary count == window is OK
    configure(16'd20, 16'd5, 2'd0); pulse_start; idle(2); kick; wait_idle;
    pulse_start; wait_count_eq(16'd6); kick;                 // FIRE sees 5 -> service
    wait_count_eq(16'd7); kick;                              // FIRE sees 6 -> early
    wait_idle;
    pulse_start; wait_count_eq(16'd3); kick; wait_count_eq(16'd0); kick; wait_idle;

    // T7: kick during bark clears it; then let it bite
    configure(16'd5, 16'hFFFF, 2'd0); pulse_start; wait_bark; idle(2); kick;
    wait_idle;

    // T8: every prescaler, with a kick mid-prescale to reset tick_cnt
    for (p = 1; p < 4; p = p + 1) begin
      configure(16'd3, 16'hFFFF, p[1:0]); pulse_start; idle(7); kick; wait_idle;
    end

    // T9: reconfigure while running (new timeout used at next reload),
    //     and drop prescale 3 -> 0 mid-count (tick_cnt >= D-1 case)
    configure(16'd40, 16'hFFFF, 2'd3); pulse_start; idle(150);
    configure(16'd9, 16'hFFFF, 2'd0); idle(5); kick; wait_idle;

    // T10: lock blocks config; write+lock same cycle is accepted
    do_reset;
    configure(16'd8, 16'hFFFF, 2'd0); pulse_lock;
    configure(16'd100, 16'd1, 2'd2);              // ignored
    pulse_start; wait_idle;
    do_reset;
    @(negedge clk); clear_inputs; cfg_we = 1; cfg_lock = 1;
      cfg_timeout = 16'd12; cfg_window = 16'hFFFF; cfg_prescale = 2'd0;
    configure(16'd3, 16'hFFFF, 2'd0);             // ignored
    pulse_start; wait_idle;

    // T11: bite_count saturation with timeout = 0
    do_reset; configure(16'd0, 16'hFFFF, 2'd0);
    for (i = 0; i < 10; i = i + 1) begin pulse_start; wait_idle; end

    // T12: reset in the middle of a run and in the middle of a bite
    configure(16'd30, 16'hFFFF, 2'd0); pulse_start; idle(10); do_reset;
    configure(16'd1, 16'hFFFF, 2'd0); pulse_start; idle(5); do_reset; idle(3);

    // T13: constrained-random soak
    for (i = 0; i < rcycles; i = i + 1) begin
      @(negedge clk); clear_inputs;
      reset   = ({$random(seed)} % 3000) == 0;
      start   = ({$random(seed)} % 15) == 0;
      clr_err = ({$random(seed)} % 40) == 0;
      cfg_lock = ({$random(seed)} % 2500) == 0;
      if (({$random(seed)} % 120) == 0) begin
        cfg_we = 1;
        r = {$random(seed)} % 10;
        cfg_timeout  = (r == 0) ? 16'd0 : (r == 1) ? ({$random(seed)} % 300) : ({$random(seed)} % 40);
        cfg_window   = (({$random(seed)} % 2) == 0) ? 16'hFFFF : ({$random(seed)} % (cfg_timeout + 2));
        r = {$random(seed)} % 10;
        cfg_prescale = (r < 5) ? 2'd0 : (r < 8) ? 2'd1 : (r < 9) ? 2'd2 : 2'd3;
      end
      if (({$random(seed)} % 5) == 0) begin
        kick_valid = 1;
        r = {$random(seed)} % 20;
        kick_data = (r < 9) ? 8'hA5 : (r < 18) ? 8'h5A : $random(seed);
      end
    end
    idle(5);

    // ---------------- Report ----------------
    $display("COVERAGE start=%0d start_ignored=%0d kick_while_idle=%0d arm=%0d service=%0d service_in_bark=%0d service_at_window_edge=%0d",
             cov_start, cov_start_ign, cov_kick_idle, cov_arm, cov_service, cov_svc_bark, cov_svc_edge);
    $display("COVERAGE bad_key=%0d err_set_and_clr_same_cycle=%0d clr_err=%0d bark=%0d bite_timeout=%0d bite_early=%0d bite_count_saturated=%0d",
             cov_bad, cov_set_clr, cov_clr, cov_bark, cov_bite_timeout, cov_bite_early, cov_sat);
    $display("COVERAGE cfg_write=%0d cfg_blocked_by_lock=%0d lock=%0d warn_cycles=%0d reset_while_running=%0d run_cycles_per_prescale=%0d/%0d/%0d/%0d",
             cov_cfg, cov_cfg_blk, cov_lock, cov_warn, cov_reset_run, cov_presc0, cov_presc1, cov_presc2, cov_presc3);
    if (cov_bark == 0 || cov_bite_timeout == 0 || cov_bite_early == 0 || cov_service == 0 ||
        cov_bad == 0 || cov_set_clr == 0 || cov_cfg_blk == 0 || cov_sat == 0 || cov_svc_bark == 0 ||
        cov_svc_edge == 0 || cov_presc3 == 0 || cov_warn == 0 || cov_start_ign == 0)
      $display("WARNING: coverage hole detected (see COVERAGE lines)");

    $display("RESULT total=%0d mismatches=%0d", total, mismatches);
    $finish;
  end
endmodule