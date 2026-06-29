`timescale 1ns / 1ps

module tb_dual_ro_temp_engine;
  // Generate clk = 131.072 kHz
  // Generate temp_ro_clk with programmable frequency (e.g., 200 kHz)
  // Instantiate DUT
  // Apply test vectors
  // Monitor ratio_out and compare with expected value using a golden model
  // Measure measurement time using assertion
  // Report pass/fail
  // Declare signals
  reg clk;
  reg rst_n;
  reg temp_ro_clk;
  reg meas_en;
  reg [16:0] gate_width;
  reg [7:0] settle_cycles;
  wire enable_temp_ro;
  wire [19:0] ratio_out;
  wire busy;
  wire valid;

  // Generate clk: 1/131.072kHz = 7629.39ns -> Half period approx 3815ns.
  // Using template's #3810 choice means actual simulation period is 7620ns.
  initial clk = 0;
  always #3810 clk = ~clk;  

  // Instantiate DUT
  dual_ro_temp_engine dut (
      .clk(clk),
      .rst_n(rst_n),
      .temp_ro_clk(temp_ro_clk),
      .meas_en(meas_en),
      .gate_width(gate_width),
      .settle_cycles(settle_cycles),
      .enable_temp_ro(enable_temp_ro),
      .ratio_out(ratio_out),
      .busy(busy),
      .valid(valid)
  );

  // Waveform
  initial begin
    $dumpfile("tb_dual_ro_temp_engine.vcd");
    $dumpvars(0, tb_dual_ro_temp_engine);
  end

  // Golden Model Variables
  reg [19:0] expected_ratio;
  integer expected_n_temp;
  integer ratio_diff;

  parameter integer NUM_TESTS = 2;
  integer freqs_vector[0:NUM_TESTS-1];
  integer i;
  real half_period_ns;

  // Initialize frequency vector in KHz
  initial begin
    freqs_vector[0] = 200; // 25 degrees C
    freqs_vector[1] = 50;
  end

  
  initial begin
    temp_ro_clk = 0;
    forever begin
      #half_period_ns temp_ro_clk = ~temp_ro_clk;
    end
  end

  initial begin
    // Initialize inputs
    rst_n = 1;
    meas_en = 0;
    gate_width = 17'd10000;  // Example gate width (M)
    settle_cycles = 8'd10;   // Example settle cycles

    // Display data before reset
    $display("Before Reset: busy=%b, valid=%b, ratio_out=%d", busy, valid, ratio_out);
    
    // Apply reset
    #100;
    rst_n = 0;

    // Display data after reset
    #10;
    $display("After Reset: busy=%b, valid=%b, ratio_out=%d", busy, valid, ratio_out);

    // Wait for a few clock cycles
    #1000;
    rst_n = 1; // Release reset
    #100;

    // Loop through each frequency test
    for (i = 0; i < NUM_TESTS; i = i + 1) begin
      // Set temp_ro_clk frequency
      half_period_ns = 1000000.0 / freqs_vector[i] / 2.0;
      
      // --- GOLDEN MODEL CALCULATION ---
      // clk period = 2 * 3810 ns = 7620 ns.
      // N_temp = gate_width * (f_temp / f_main) 
      // Using 64'd7620 forces 64-bit precision to prevent intermediate multiplication overflows.
      expected_n_temp = (64'd7620 * gate_width * freqs_vector[i]) / 1000000;
      expected_ratio  = (expected_n_temp << 16) / gate_width;
      // --------------------------------

      #10; // Wait short time before starting measurement

      // Start measurement
      meas_en = 1;
      #10;
      meas_en = 0;

      // Wait for measurement to complete
      wait (valid == 1);
      #1; // Allow output to stabilize post edge
      // Compute absolute difference for tolerance checking
      ratio_diff = ratio_out - expected_ratio;
      if (ratio_diff < 0) ratio_diff = -ratio_diff;

      // Check the output ratio_out against expected value allowing up to +/- 2 LSB quantization error
      if (ratio_diff <= 2) begin
        $display("Test %d Passed: ratio_out = %d, expected = %d (freq = %d kHz, diff = %d LSB)", 
                 i, ratio_out, expected_ratio, freqs_vector[i], ratio_diff);
      end else begin
        $display("Test %d Failed: ratio_out = %d, expected = %d (freq = %d kHz, diff = %d LSB)", 
                 i, ratio_out, expected_ratio, freqs_vector[i], ratio_diff);
      end

      // Wait before next test
      #1000;
    end

    // Finish simulation
    #100;
    $finish;
  end

endmodule