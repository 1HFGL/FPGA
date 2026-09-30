`timescale 1ns/1ps

// Linear, sample-enabled ADSR. All inputs belong to clk's clock domain.
// Level is unsigned Q1.16: 0 = silence, 65536 = exactly unity gain.
module adsr_env #(
    parameter [16:0] ATTACK_STEP   = 17'd137,
    parameter [16:0] DECAY_STEP    = 17'd7,
    parameter [16:0] SUSTAIN_LEVEL = 17'd32768,
    parameter [16:0] RELEASE_STEP  = 17'd3
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire        gate,
    input  wire        retrigger,
    output reg  [16:0] env_level,
    output wire        active,
    output reg  [2:0]  state
);
    localparam [2:0] IDLE = 3'd0, ATTACK = 3'd1, DECAY = 3'd2,
                     SUSTAIN = 3'd3, RELEASE = 3'd4;
    localparam [16:0] UNITY = 17'd65536;
    localparam [16:0] SUSTAIN_CLAMP =
        (SUSTAIN_LEVEL > UNITY) ? UNITY : SUSTAIN_LEVEL;

    reg gate_sampled;
    reg retrigger_pending;
    reg [16:0] next_level;
    reg [2:0] next_state;
    wire [17:0] attack_sum = {1'b0, env_level} + {1'b0, ATTACK_STEP};
    wire [17:0] decay_floor = {1'b0, SUSTAIN_CLAMP} + {1'b0, DECAY_STEP};
    assign active = (state != IDLE);

    // Release has priority over retrigger. A new attack starts at the current
    // level (including mid-release), rather than jumping back to zero.
    // Step=0 means finish that stage on its next sample tick, not get stuck.
    always @* begin
        next_level = env_level;
        next_state = state;
        if (!gate) begin
            if ((RELEASE_STEP == 0) || (env_level <= RELEASE_STEP)) begin
                next_level = 0;
                next_state = IDLE;
            end else begin
                next_level = env_level - RELEASE_STEP;
                next_state = RELEASE;
            end
        end else if (retrigger || retrigger_pending || !gate_sampled ||
                     (state == IDLE) || (state == ATTACK)) begin
            if ((ATTACK_STEP == 0) || (attack_sum >= {1'b0, UNITY})) begin
                next_level = UNITY;
                next_state = DECAY;
            end else begin
                next_level = attack_sum[16:0];
                next_state = ATTACK;
            end
        end else if (state == DECAY) begin
            if ((DECAY_STEP == 0) || ({1'b0, env_level} <= decay_floor)) begin
                next_level = SUSTAIN_CLAMP;
                next_state = SUSTAIN;
            end else begin
                next_level = env_level - DECAY_STEP;
            end
        end else if (state == SUSTAIN) begin
            next_level = SUSTAIN_CLAMP;
        end else begin
            next_level = 0;
            next_state = IDLE;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            env_level <= 0;
            state <= IDLE;
            gate_sampled <= 1'b0;
            retrigger_pending <= 1'b0;
        end else begin
            // Capture a one-clock pulse even between audio sample requests.
            // Multiple pulses before a request coalesce into one retrigger.
            if (sample_tick) begin
                env_level <= next_level;
                state <= next_state;
                gate_sampled <= gate;
                retrigger_pending <= 1'b0;
            end else if (retrigger) begin
                retrigger_pending <= 1'b1;
            end
        end
    end
endmodule
