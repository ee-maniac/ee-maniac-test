`include "debug_defines.svh"

module temp_counter #(
    parameter WIDTH = 17 //default 17 bits to avoid overflow
)
(
    input wire clk, //temp_ro_clk
    input wire rst_n, //asynchronous active low reset
    input wire enable, //synchronized gate_active
    output reg [WIDTH-1:0] count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {WIDTH{1'b0}};

            `ifdef DEBUG
                $display("[%t] TEMP_CNT: Reset (width=%0d)", $time, WIDTH);
            `endif
        end
        else if (enable) begin
            count <= count + 1'b1;
        end
    end

    `ifdef DEBUG
        reg [WIDTH-1:0] prev_count; //tracks previous count for change detection
        reg prev_enable; //tracks previous enable for edge detection
    `endif

    `ifdef DEBUG
        always @(posedge clk) begin
            //detect rising edge of enable (0 -> 1 transition)
            if (enable && !prev_enable) begin
                $display("[%t] TEMP_CNT: ENABLED (starting count at %0d)", $time, count);
            end

            //detect falling edge of enable (1 -> 0 transition)
            if (!enable && prev_enable) begin
                $display("[%t] TEMP_CNT: DISABLED (final count = %0d)", $time, count);
            end

            //print count periodically (every 1024 cycles) to track progress
            if (enable && count != prev_count && (count & 16'h03FF) == 0) begin
                $display("[%t] TEMP_CNT: count=%0d", $time, count);
            end

            //update tracking registers
            prev_count <= count;
            prev_enable <= enable;
        end
    `endif

endmodule