`include "debug_defines.svh"

module cdc_2ff_sync (
    input wire clk_dst, //destination clock (temp_ro_clk)
    input wire rst_n, //asynchronous active low reset
    input wire signal_src, //signal from source clock domain (clk)
    output wire signal_dst //synchronized signal (temp_ro_clk domain)
);

    reg sync_ff1, sync_ff2;

    `ifdef DEBUG
        reg prev_signal_dst;
    `endif

    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;

            `ifdef DEBUG
                prev_signal_dst <= 1'b0;
                $display("[%t] CDC: Reset", $time);
            `endif
        end 
        else begin
            sync_ff1 <= signal_src;
            sync_ff2 <= sync_ff1;
        end
    end

    assign signal_dst = sync_ff2;

    `ifdef DEBUG
        always @(posedge clk_dst) begin
            if (sync_ff2 != prev_signal_dst) begin
                $display("[%t] CDC: signal_dst changed to %b (src was %b)", $time, sync_ff2, signal_src);
                prev_signal_dst <= sync_ff2;
            end
        end
    `endif

endmodule