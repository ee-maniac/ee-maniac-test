`include "debug_defines.svh"

module divider_shifter #(
    parameter TEMP_CNT_W = 17, //width of temp_cnt input
    parameter GATE_VAL   = 32768, //expected power of two value of gate_width
    parameter GATE_W     = $clog2(GATE_VAL) + 1, //width of gate_width input
    parameter RATIO_W    = 20, //width of ratio output (Q4.16)
    parameter FRAC_BITS  = 16 //fractional bits in Q format (default 16)
)
(
    input wire clk,
    input wire rst_n,
    input wire start, //start computation (pulse)
    input wire [TEMP_CNT_W-1:0] temp_cnt, //numerator
    input wire [GATE_W-1:0] gate_width, //denominator (power of two assumed)
    output reg [RATIO_W-1:0] ratio, //Q4.16 output
    output reg done //high for 1 cycle when ratio is ready
);

    `ifdef DEBUG
        reg prev_done; //detect rising edge of done
    `endif

    //shift amount = FRAC_BITS - log2(gate_width)
    //only valid when gate_width is a power of two.
    //using $clog2 from SystemVerilog.
    localparam SHIFT_AMT = FRAC_BITS - $clog2(GATE_VAL);

    //ensure gate_width is power of two (synthesis ignores)
    initial begin
        if (gate_width & (gate_width - 1)) begin
            $display("WARNING: divider_shifter expects power of two gate_width");
        end

        `ifdef DEBUG
            $display("[%t] DIVIDER: TEMP_CNT_W=%0d, GATE_VAL=%0d, GATE_W=%0d, SHIFT_AMT=%0d", $time, TEMP_CNT_W, GATE_VAL, GATE_W, SHIFT_AMT);
        `endif
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ratio <= {RATIO_W{1'b0}};
            done <= 1'b0;

            `ifdef DEBUG
                prev_done <= 1'b0;
                $display("[%t] DIVIDER: Reset", $time);
            `endif
        end 
        else begin
            if (start) begin
                //shift left by (FRAC_BITS - log2(gate_width))
                //example: gate_width=16384 (2^14), FRAC_BITS=16 -> SHIFT_AMT=2
                ratio <= temp_cnt << SHIFT_AMT;
                done <= 1'b1;

                `ifdef DEBUG
                    $display("[%t] DIVIDER: START: temp_cnt=%0d << %0d = %0d (0x%0h)",
                        $time, temp_cnt, SHIFT_AMT, temp_cnt << SHIFT_AMT, temp_cnt << SHIFT_AMT);
                `endif
            end 
            else begin
                done <= 1'b0;
            end
        end
    end

    `ifdef DEBUG
        always @(posedge clk) begin
            //print only when done transitions 0 -> 1
            if (done && !prev_done) begin
                $display("[%t] DIVIDER: DONE=1, ratio=%0d (0x%0h)", $time, ratio, ratio);
            end
            prev_done <= done;
        end
    `endif

endmodule