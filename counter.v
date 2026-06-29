`include "debug_defines.svh"

module counter #(
    parameter WIDTH = 16
)
(
    input wire clk,
    input wire rst_n, //asynchronous active low reset
    input wire enable, //count enable
    input wire [WIDTH-1:0] threshold, //count up to threshold
    output reg [WIDTH-1:0] count,
    output wire done
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {WIDTH{1'b0}};

            `ifdef DEBUG
                $display("[%t] COUNTER: Reset (width=%0d, threshold=%0d)", $time, WIDTH, threshold);
            `endif
        end 
        else if (enable) begin
            if (done) begin
                count <= {WIDTH{1'b0}}; //Auto-reset on reaching threshold

                `ifdef DEBUG
                    $display("[%t] COUNTER: Wrapped at %0d (threshold=%0d)", $time, count, threshold);
                `endif
            end
            else
                count <= count + 1'b1;
        end
    end

    assign done = (count == (threshold - 1'b1)); //done = 1 if count == threshold - 1'b1 and 0 if count != threshold

    `ifdef DEBUG
        reg [WIDTH-1:0] prev_count;
        reg prev_done;
    `endif

    `ifdef DEBUG
        always @(posedge clk) begin
            if (enable) begin
                //detect rising edge of done (0 -> 1 transition)
                if (done && !prev_done) begin
                    $display("[%t] COUNTER: DONE=1 (count=%0d)", $time, count);
                end
                //print count periodically (every 1024 cycles) to track progress
                if (count != prev_count && (count & 16'h03FF) == 0) begin
                    $display("[%t] COUNTER: count=%0d, done=%b", $time, count, done);
                end
                prev_count <= count;
                prev_done <= done;
            end
        end
    `endif

endmodule