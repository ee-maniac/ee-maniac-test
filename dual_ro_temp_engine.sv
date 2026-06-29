`include "debug_defines.svh"

module dual_ro_temp_engine #(
    parameter GATE_VAL  = 32768, //width of temp_cnt input
    parameter GATE_W    = $clog2(GATE_VAL) + 1, //width of gate_width input
    parameter SETTLE_W  = 8, //width of settle_cycles input
    parameter TEMP_CNT_W = 17, //width of temp_cnt (safe default)
    parameter RATIO_W   = 20, //width of ratio output (Q4.16)
    parameter FRAC_BITS = 16 //fractional bits in Q format
)
(
    input wire clk,
    input wire rst_n,
    input wire temp_ro_clk,
    input wire meas_en,
    input wire [GATE_W-1:0] gate_width,
    input wire [SETTLE_W-1:0] settle_cycles,
    output reg enable_temp_ro,
    output reg [RATIO_W-1:0] ratio_out,
    output reg busy,
    output reg valid
);

    //------------------------------------------------------------
    //local parameters
    //------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        SETTLE  = 3'b001,
        GATE    = 3'b010,
        COMPUTE = 3'b011,
        RESULT  = 3'b100
    } state_t;

    state_t state, next_state;

    //------------------------------------------------------------
    //internal signals
    //------------------------------------------------------------
    reg gate_active;
    reg div_start;

    wire cnt_done;
    wire [GATE_W-1:0] cnt_threshold;
    wire [GATE_W-1:0] gate_cnt;
    wire gate_active_sync;
    wire [TEMP_CNT_W-1:0] temp_cnt;
    wire [RATIO_W-1:0] ratio_int;
    wire div_done;

    //------------------------------------------------------------
    //threshold mux
    //------------------------------------------------------------
    assign cnt_threshold = (state == SETTLE) ? settle_cycles : gate_width; //auto pad settle_cycles by GATE_W-SETTLE_W zero bits

    //------------------------------------------------------------
    //submodule instantiations
    //------------------------------------------------------------

    //CDC synchronizer
    cdc_2ff_sync sync_inst (
        .clk_dst    (temp_ro_clk),
        .rst_n  (rst_n),
        .signal_src (gate_active),
        .signal_dst (gate_active_sync)
    );

    //Temp counter (temp_ro_clk domain)
    temp_counter #(
        .WIDTH (TEMP_CNT_W)
    ) temp_cnt_inst (
        .clk   (temp_ro_clk),
        .rst_n (rst_n),
        .enable(gate_active_sync),
        .count (temp_cnt)
    );

    //Gate counter (clk domain)
    counter #(
        .WIDTH (GATE_W)
    ) gate_cnt_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (state == SETTLE || state == GATE),
        .threshold(cnt_threshold),
        .count    (gate_cnt),
        .done     (cnt_done)
    );

    //Divider / Shifter
    divider_shifter #(
        .TEMP_CNT_W (TEMP_CNT_W),
        .GATE_VAL   (GATE_VAL),
        .GATE_W     (GATE_W),
        .RATIO_W    (RATIO_W),
        .FRAC_BITS  (FRAC_BITS)
    ) div_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (div_start),
        .temp_cnt (temp_cnt),
        .gate_width(gate_width),
        .ratio    (ratio_int),
        .done     (div_done)
    );

    //------------------------------------------------------------
    //FSM: state register
    //------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;

            `ifdef DEBUG
                $display("[%t] FSM: Reset -> IDLE", $time);
            `endif
        end
        else begin
            state <= next_state;

            `ifdef DEBUG
                if (state != next_state) begin
                    $display("[%t] FSM: %s -> %s", $time, state.name(), next_state.name());
                end
            `endif
        end
    end

    //------------------------------------------------------------
    //FSM: next state logic
    //------------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (meas_en) next_state = SETTLE;
            end
            SETTLE: begin
                if (cnt_done) next_state = GATE;
            end
            GATE: begin
                if (cnt_done) next_state = COMPUTE;
            end
            COMPUTE: begin
                if (div_done) next_state = RESULT;
            end
            RESULT: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    //------------------------------------------------------------
    //FSM: output logic (Moore)
    //------------------------------------------------------------
    always_comb begin
        enable_temp_ro = (state == SETTLE) || (state == GATE);
        busy = (state != IDLE);
        valid = (state == RESULT);
        gate_active = (state == GATE);
        div_start = (state == COMPUTE);
    end

    //------------------------------------------------------------
    //output register
    //------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ratio_out <= {RATIO_W{1'b0}};
        end 
        else if (next_state == RESULT) begin
            ratio_out <= ratio_int;

            `ifdef DEBUG
                $display("[%t] FSM: RESULT -> ratio_out=0x%0h (%0d)", $time, ratio_int, ratio_int);
            `endif
        end
    end

    //------------------------------------------------------------
    //DEBUG: monitor key conditions
    //------------------------------------------------------------
    `ifdef DEBUG
        always @(posedge clk) begin
            //meas_en detection in IDLE
            if (meas_en && state == IDLE) begin
                $display("[%t] FSM: meas_en detected in IDLE", $time);
            end

            //Settle complete
            if (state == SETTLE && cnt_done) begin
                $display("[%t] FSM: settle complete (cnt_done=1)", $time);
            end

            //Gate complete
            if (state == GATE && cnt_done) begin
                $display("[%t] FSM: gate complete (cnt_done=1)", $time);
            end

            //Division complete
            if (state == COMPUTE && div_done) begin
                $display("[%t] FSM: division complete (div_done=1)", $time);
            end
        end
    `endif

endmodule