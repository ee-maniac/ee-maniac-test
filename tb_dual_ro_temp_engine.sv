`timescale 1ns/1ps

module tb_dual_ro_temp_engine;

    // -----------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------
    parameter GATE_VAL  = 32768;       // Must match DUT parameter
    parameter GATE_W    = $clog2(GATE_VAL) + 1;
    parameter SETTLE_W  = 8;
    parameter TEMP_CNT_W = 17;
    parameter RATIO_W   = 20;
    parameter FRAC_BITS = 16;

    // Main RO frequency (fixed)
    parameter real F_MAIN_KHZ = 131.072;      // Main RO frequency (kHz)
    parameter real CLK_PERIOD_NS = 1_000_000_000.0 / (F_MAIN_KHZ * 1000.0);   // ~7629 ns

    // Temperature calibration: map temperature to Temp RO frequency
    // Temp RO: at 25°C: 200 kHz, TC = 5000 ppm/°C
    parameter integer NUM_TESTS = 3;
    integer freq_khz_array[0:NUM_TESTS-1] = '{200, 100, 50};   // Example frequencies (kHz)

    // Expected ratio parameters (computed per test)
    integer expected_n_temp;
    integer expected_ratio;
    integer ratio_diff;

    // -----------------------------------------------------------------
    // Signals
    // -----------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg temp_ro_clk;
    reg meas_en;
    reg [GATE_W-1:0] gate_width;
    reg [SETTLE_W-1:0] settle_cycles;

    wire [RATIO_W-1:0] ratio_out;
    wire busy;
    wire valid;
    wire enable_temp_ro;

    // -----------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------
    dual_ro_temp_engine #(
        .GATE_VAL   (GATE_VAL),
        .GATE_W     (GATE_W),
        .SETTLE_W   (SETTLE_W),
        .TEMP_CNT_W (TEMP_CNT_W),
        .RATIO_W    (RATIO_W),
        .FRAC_BITS  (FRAC_BITS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .temp_ro_clk (temp_ro_clk),
        .meas_en     (meas_en),
        .gate_width  (gate_width),
        .settle_cycles(settle_cycles),
        .ratio_out   (ratio_out),
        .busy        (busy),
        .valid       (valid),
        .enable_temp_ro(enable_temp_ro)
    );

    // -----------------------------------------------------------------
    // Clock generation
    // -----------------------------------------------------------------
    initial begin
        clk = 1;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    // -----------------------------------------------------------------
    // Test stimulus
    // -----------------------------------------------------------------
    integer i;
    real tro_period_ns;
    real tro_half_ns;

    // Variables for DRS 7.4 checks
    real start_time_ns;
    real end_time_ns;
    real expected_duration_ns;
    real actual_duration_ns;

        initial begin
        // Display header
        $display("=====================================================");
        $display("Dual-RO Temperature Engine Testbench");
        $display("F_main = %0.3f kHz", F_MAIN_KHZ);
        $display("M = %0d", GATE_VAL);
        $display("Number of test frequencies: %0d", NUM_TESTS);
        $display("CLK_PERIOD_NS = %f", CLK_PERIOD_NS);
        $display("=====================================================");

        // Initialize signals
        rst_n = 0;
        meas_en = 0;
        gate_width = GATE_VAL;
        settle_cycles = 13;    // ~100 µs

        // Apply reset
        repeat (10) @(posedge clk);
        rst_n = 1;
        $display("[%t] Reset released", $time);

        // Wait for a few cycles before starting measurements
        repeat (5) @(posedge clk);

        // Loop through each frequency test
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            // Set temp_ro_clk frequency for this test
            tro_period_ns = 1_000_000.0 / freq_khz_array[i];   // period in ns
            tro_half_ns = tro_period_ns / 2.0;

            // Generate temp_ro_clk in a separate process
            fork
                begin : temp_ro_clock_gen
                    temp_ro_clk = 0;
                    forever #(tro_half_ns) temp_ro_clk = ~temp_ro_clk;
                end
            join_none

            // --- GOLDEN MODEL CALCULATION ---
            expected_n_temp = $rtoi( (gate_width * freq_khz_array[i]) / F_MAIN_KHZ + 0.5 );
            expected_ratio = (expected_n_temp << (FRAC_BITS - $clog2(GATE_VAL)));
            // ---------------------------------

            // Display test info
            $display("[%t] Starting test %0d: f_temp = %0d kHz, expected ratio = %0d (0x%0h)",
                     $time, i, freq_khz_array[i], expected_ratio, expected_ratio);

            // -------------------------------------------------------------
            // Start measurement
            // -------------------------------------------------------------
            @(posedge clk);
            meas_en = 1;
            start_time_ns = $time / 1000.0;
            $display("[%t] meas_en asserted", $time);
            @(posedge clk);
            meas_en = 0;
            $display("[%t] meas_en deasserted", $time);

            // Check that busy goes high after meas_en (should happen immediately)
            @(posedge clk);
            if (!busy) begin
                $display("FAIL: busy did not go high after meas_en (test %0d)", i);
            end else begin
                $display("PASS: busy went high after meas_en (test %0d)", i);
            end

            // Wait for measurement to complete
            @(posedge clk);
            wait (valid == 1);
            end_time_ns = $time / 1000.0;

            // Check that busy is still high when valid is asserted
            if (!busy) begin
                $display("FAIL: busy is low when valid goes high (test %0d)", i);
            end else begin
                $display("PASS: busy is high during valid (test %0d)", i);
            end

            // Sample ratio_out (valid is high, ratio is stable)
            $display("[%t] Test %0d complete: ratio_out = %0d (0x%0h)", $time, i, ratio_out, ratio_out);

            // -------------------------------------------------------------
            // 7.4 Check 1: Measurement duration
            // -------------------------------------------------------------
            expected_duration_ns = (settle_cycles + gate_width) / F_MAIN_KHZ * 1000.0;
            actual_duration_ns = end_time_ns - start_time_ns;
            if (actual_duration_ns <= expected_duration_ns + CLK_PERIOD_NS) begin
                $display("PASS: Measurement duration = %0.3f ns (expected <= %0.3f ns)",
                         actual_duration_ns, expected_duration_ns + CLK_PERIOD_NS);
            end else begin
                $display("FAIL: Measurement duration = %0.3f ns (expected <= %0.3f ns)",
                         actual_duration_ns, expected_duration_ns + CLK_PERIOD_NS);
            end

            // -------------------------------------------------------------
            // 7.4 Check 2: Valid pulse (one cycle only)
            // -------------------------------------------------------------
            @(posedge clk);
            if (valid) begin
                // We are already on the cycle after valid went high.
                // Count this cycle and the next one.
                @(posedge clk);
                if (valid) begin
                    $display("FAIL: valid stayed high for more than 1 cycle (test %0d)", i);
                end else begin
                    $display("PASS: valid is one cycle (test %0d)", i);
                end
            end

            // -------------------------------------------------------------
            // 7.4 Check 3: Busy behaviour (high from meas_en until valid, then low)
            // -------------------------------------------------------------
            // Wait for busy to go low (it should after valid)
            wait (busy == 0);
            $display("PASS: busy went low after valid (test %0d)", i);

            // -------------------------------------------------------------
            // 7.4 Check 4: Ratio accuracy
            // -------------------------------------------------------------
            ratio_diff = $signed(ratio_out) - $signed(expected_ratio);
            if (ratio_diff < 0) ratio_diff = -ratio_diff;
            if (ratio_diff <= 2) begin
                $display("PASS: ratio_out matches expected (diff = %0d LSB)", ratio_diff);
            end else begin
                $display("FAIL: ratio_out = %0d, expected = %0d (diff = %0d LSB)", ratio_out, expected_ratio, ratio_diff);
            end

            // Kill the clock generator and wait
            disable fork;
            repeat (10) @(posedge clk);
        end

        // Finish simulation
        repeat (10) @(posedge clk);
        $display("Simulation finished at time %t", $time);
        $finish;
    end

    // -----------------------------------------------------------------
    // Monitor
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("tb_dual_ro_temp_engine.vcd");
        $dumpvars(0, tb_dual_ro_temp_engine);
    end

    // -----------------------------------------------------------------
    // Simple assertion to catch any unexpected busy hang
    // -----------------------------------------------------------------
    initial begin
        // Timeout after 2 seconds (simulation time)
        #2_000_000_000 $display("ERROR: Simulation timeout!"); $finish;
    end

endmodule
