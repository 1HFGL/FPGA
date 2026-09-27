`timescale 1ns/1ps

module voice_allocator #(
    parameter integer VOICES       = 32,
    parameter integer IDX_WIDTH    = 5,
    parameter integer COUNT_WIDTH  = 6,
    parameter integer TIME_WIDTH   = 32,
    parameter integer SOURCE_WIDTH = 5,
    parameter integer BEND_WIDTH   = 16,
    parameter integer EXPR_WIDTH   = 8
) (
    input  wire clk,
    input  wire rst_n,
    input  wire event_valid,
    output wire event_ready,
    input  wire event_type,
    input  wire [SOURCE_WIDTH-1:0] event_source_id,
    input  wire [6:0] event_note,
    input  wire [6:0] event_velocity,
    input  wire [3:0] event_timbre,
    input  wire expr_valid,
    output wire expr_ready,
    input  wire [SOURCE_WIDTH-1:0] expr_source_id,
    input  wire [6:0] expr_note,
    input  wire [BEND_WIDTH-1:0] expr_pitch_bend,
    input  wire [EXPR_WIDTH-1:0] expr_aftertouch,
    input  wire [EXPR_WIDTH-1:0] expr_vibrato_depth,
    input  wire [EXPR_WIDTH-1:0] expr_vibrato_rate,
    input  wire [VOICES-1:0] release_done,
    output reg  [VOICES-1:0] voice_active,
    output reg  [VOICES-1:0] voice_gate,
    output wire [VOICES*SOURCE_WIDTH-1:0] voice_source_id_flat,
    output wire [VOICES*7-1:0] voice_note_flat,
    output wire [VOICES*7-1:0] voice_velocity_flat,
    output wire [VOICES*4-1:0] voice_timbre_flat,
    output wire [VOICES*BEND_WIDTH-1:0] voice_pitch_bend_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_aftertouch_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_vibrato_depth_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_vibrato_rate_flat,
    output wire [COUNT_WIDTH-1:0] voice_count,
    output reg  [COUNT_WIDTH-1:0] max_voice_count,
    output reg  [31:0] note_on_count,
    output reg  [31:0] note_off_count,
    output reg  [31:0] steal_count,
    output reg  steal_pulse
);

    localparam [1:0] S_IDLE      = 2'd0;
    localparam [1:0] S_SCAN      = 2'd1;
    localparam [1:0] S_EXPR_SCAN = 2'd2;
    localparam [1:0] S_APPLY     = 2'd3;

    reg [SOURCE_WIDTH-1:0] source_id_mem [0:VOICES-1];
    reg [6:0] note_mem [0:VOICES-1];
    reg [6:0] velocity_mem [0:VOICES-1];
    reg [3:0] timbre_mem [0:VOICES-1];
    reg [BEND_WIDTH-1:0] pitch_bend_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] aftertouch_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] vibrato_depth_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] vibrato_rate_mem [0:VOICES-1];
    reg [TIME_WIDTH-1:0] age_mem [0:VOICES-1];
    reg [TIME_WIDTH-1:0] time_counter;

    reg [1:0] state;
    reg op_expr;
    reg [IDX_WIDTH-1:0] scan_idx;

    reg latched_event_type;
    reg [SOURCE_WIDTH-1:0] latched_source_id;
    reg [6:0] latched_note;
    reg [6:0] latched_velocity;
    reg [3:0] latched_timbre;
    reg [SOURCE_WIDTH-1:0] latched_expr_source_id;
    reg [6:0] latched_expr_note;
    reg [BEND_WIDTH-1:0] latched_pitch_bend;
    reg [EXPR_WIDTH-1:0] latched_aftertouch;
    reg [EXPR_WIDTH-1:0] latched_vibrato_depth;
    reg [EXPR_WIDTH-1:0] latched_vibrato_rate;

    reg same_source_found;
    reg [IDX_WIDTH-1:0] same_source_idx;
    reg same_note_found;
    reg [IDX_WIDTH-1:0] same_note_idx;
    reg free_found;
    reg [IDX_WIDTH-1:0] free_idx;
    reg release_found;
    reg [IDX_WIDTH-1:0] release_idx;
    reg oldest_found;
    reg [IDX_WIDTH-1:0] oldest_idx;
    reg [TIME_WIDTH-1:0] oldest_age;

    reg off_source_found;
    reg [IDX_WIDTH-1:0] off_source_idx;
    reg off_note_found;
    reg [IDX_WIDTH-1:0] off_note_idx;

    reg expr_source_found;
    reg [IDX_WIDTH-1:0] expr_source_idx;
    reg expr_note_found;
    reg [IDX_WIDTH-1:0] expr_note_idx;

    reg [IDX_WIDTH-1:0] target_idx;
    reg target_valid;
    reg target_is_same;
    reg target_is_steal;

    integer i;
    integer c;
    reg [COUNT_WIDTH-1:0] active_count;
    reg [IDX_WIDTH-1:0] off_target_idx;
    reg off_target_valid;
    reg [IDX_WIDTH-1:0] expr_target_idx;
    reg expr_target_valid;

    assign voice_count = active_count;
    assign event_ready = (state == S_IDLE);
    assign expr_ready = (state == S_IDLE) && !event_valid;

    always @* begin
        active_count = {COUNT_WIDTH{1'b0}};
        for (c = 0; c < VOICES; c = c + 1) begin
            active_count = active_count + voice_active[c];
        end
    end

    always @* begin
        target_valid = 1'b0;
        target_is_same = 1'b0;
        target_is_steal = 1'b0;
        target_idx = {IDX_WIDTH{1'b0}};
        if (same_source_found) begin
            target_valid = 1'b1;
            target_is_same = 1'b1;
            target_idx = same_source_idx;
        end else if (same_note_found) begin
            target_valid = 1'b1;
            target_is_same = 1'b1;
            target_idx = same_note_idx;
        end else if (free_found) begin
            target_valid = 1'b1;
            target_idx = free_idx;
        end else if (release_found) begin
            target_valid = 1'b1;
            target_idx = release_idx;
        end else if (oldest_found) begin
            target_valid = 1'b1;
            target_is_steal = 1'b1;
            target_idx = oldest_idx;
        end
    end

    always @* begin
        off_target_valid = off_source_found | off_note_found;
        if (off_source_found) begin
            off_target_idx = off_source_idx;
        end else begin
            off_target_idx = off_note_idx;
        end

        expr_target_valid = expr_source_found | expr_note_found;
        if (expr_source_found) begin
            expr_target_idx = expr_source_idx;
        end else begin
            expr_target_idx = expr_note_idx;
        end
    end

    genvar g;
    generate
        for (g = 0; g < VOICES; g = g + 1) begin : g_flat_out
            assign voice_source_id_flat[g*SOURCE_WIDTH +: SOURCE_WIDTH] = source_id_mem[g];
            assign voice_note_flat[g*7 +: 7] = note_mem[g];
            assign voice_velocity_flat[g*7 +: 7] = velocity_mem[g];
            assign voice_timbre_flat[g*4 +: 4] = timbre_mem[g];
            assign voice_pitch_bend_flat[g*BEND_WIDTH +: BEND_WIDTH] = pitch_bend_mem[g];
            assign voice_aftertouch_flat[g*EXPR_WIDTH +: EXPR_WIDTH] = aftertouch_mem[g];
            assign voice_vibrato_depth_flat[g*EXPR_WIDTH +: EXPR_WIDTH] = vibrato_depth_mem[g];
            assign voice_vibrato_rate_flat[g*EXPR_WIDTH +: EXPR_WIDTH] = vibrato_rate_mem[g];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            op_expr <= 1'b0;
            scan_idx <= {IDX_WIDTH{1'b0}};
            time_counter <= {TIME_WIDTH{1'b0}};
            max_voice_count <= {COUNT_WIDTH{1'b0}};
            note_on_count <= 32'd0;
            note_off_count <= 32'd0;
            steal_count <= 32'd0;
            steal_pulse <= 1'b0;
            voice_active <= {VOICES{1'b0}};
            voice_gate <= {VOICES{1'b0}};
            for (i = 0; i < VOICES; i = i + 1) begin
                source_id_mem[i] <= {SOURCE_WIDTH{1'b0}};
                note_mem[i] <= 7'd0;
                velocity_mem[i] <= 7'd0;
                timbre_mem[i] <= 4'd0;
                pitch_bend_mem[i] <= {BEND_WIDTH{1'b0}};
                aftertouch_mem[i] <= {EXPR_WIDTH{1'b0}};
                vibrato_depth_mem[i] <= {EXPR_WIDTH{1'b0}};
                vibrato_rate_mem[i] <= {EXPR_WIDTH{1'b0}};
                age_mem[i] <= {TIME_WIDTH{1'b0}};
            end
        end else begin
            time_counter <= time_counter + 1'b1;
            steal_pulse <= 1'b0;

            for (i = 0; i < VOICES; i = i + 1) begin
                if (voice_active[i] && !voice_gate[i] && release_done[i]) begin
                    voice_active[i] <= 1'b0;
                end
            end

            if (active_count > max_voice_count) begin
                max_voice_count <= active_count;
            end

            case (state)
                S_IDLE: begin
                    if (event_valid) begin
                        op_expr <= 1'b0;
                        latched_event_type <= event_type;
                        latched_source_id <= event_source_id;
                        latched_note <= event_note;
                        latched_velocity <= event_velocity;
                        latched_timbre <= event_timbre;
                        scan_idx <= {IDX_WIDTH{1'b0}};
                        same_source_found <= 1'b0;
                        same_note_found <= 1'b0;
                        free_found <= 1'b0;
                        release_found <= 1'b0;
                        oldest_found <= 1'b0;
                        off_source_found <= 1'b0;
                        off_note_found <= 1'b0;
                        oldest_age <= {TIME_WIDTH{1'b1}};
                        state <= S_SCAN;
                    end else if (expr_valid) begin
                        op_expr <= 1'b1;
                        latched_expr_source_id <= expr_source_id;
                        latched_expr_note <= expr_note;
                        latched_pitch_bend <= expr_pitch_bend;
                        latched_aftertouch <= expr_aftertouch;
                        latched_vibrato_depth <= expr_vibrato_depth;
                        latched_vibrato_rate <= expr_vibrato_rate;
                        scan_idx <= {IDX_WIDTH{1'b0}};
                        expr_source_found <= 1'b0;
                        expr_note_found <= 1'b0;
                        state <= S_EXPR_SCAN;
                    end
                end

                S_SCAN: begin
                    if (voice_active[scan_idx] && voice_gate[scan_idx]) begin
                        if (source_id_mem[scan_idx] == latched_source_id) begin
                            same_source_found <= 1'b1;
                            same_source_idx <= scan_idx;
                        end
                        if (note_mem[scan_idx] == latched_note) begin
                            same_note_found <= 1'b1;
                            same_note_idx <= scan_idx;
                            off_note_found <= 1'b1;
                            off_note_idx <= scan_idx;
                            if (source_id_mem[scan_idx] == latched_source_id) begin
                                off_source_found <= 1'b1;
                                off_source_idx <= scan_idx;
                            end
                        end
                    end

                    if (!voice_active[scan_idx] && !free_found) begin
                        free_found <= 1'b1;
                        free_idx <= scan_idx;
                    end

                    if (voice_active[scan_idx] && !voice_gate[scan_idx] && !release_found) begin
                        release_found <= 1'b1;
                        release_idx <= scan_idx;
                    end

                    if (voice_active[scan_idx] && voice_gate[scan_idx]) begin
                        if (!oldest_found || (age_mem[scan_idx] < oldest_age)) begin
                            oldest_found <= 1'b1;
                            oldest_idx <= scan_idx;
                            oldest_age <= age_mem[scan_idx];
                        end
                    end

                    if (scan_idx == VOICES-1) begin
                        state <= S_APPLY;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                    end
                end

                S_EXPR_SCAN: begin
                    if (voice_active[scan_idx] && voice_gate[scan_idx]) begin
                        if (source_id_mem[scan_idx] == latched_expr_source_id) begin
                            expr_source_found <= 1'b1;
                            expr_source_idx <= scan_idx;
                        end
                        if (note_mem[scan_idx] == latched_expr_note) begin
                            expr_note_found <= 1'b1;
                            expr_note_idx <= scan_idx;
                        end
                    end

                    if (scan_idx == VOICES-1) begin
                        state <= S_APPLY;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                    end
                end

                S_APPLY: begin
                    if (op_expr) begin
                        if (expr_target_valid) begin
                            pitch_bend_mem[expr_target_idx] <= latched_pitch_bend;
                            aftertouch_mem[expr_target_idx] <= latched_aftertouch;
                            vibrato_depth_mem[expr_target_idx] <= latched_vibrato_depth;
                            vibrato_rate_mem[expr_target_idx] <= latched_vibrato_rate;
                        end
                    end else if (latched_event_type) begin
                        if (target_valid) begin
                            voice_active[target_idx] <= 1'b1;
                            voice_gate[target_idx] <= 1'b1;
                            source_id_mem[target_idx] <= latched_source_id;
                            note_mem[target_idx] <= latched_note;
                            velocity_mem[target_idx] <= latched_velocity;
                            timbre_mem[target_idx] <= latched_timbre;
                            age_mem[target_idx] <= time_counter;
                            if (!target_is_same) begin
                                pitch_bend_mem[target_idx] <= {BEND_WIDTH{1'b0}};
                                aftertouch_mem[target_idx] <= {EXPR_WIDTH{1'b0}};
                                vibrato_depth_mem[target_idx] <= {EXPR_WIDTH{1'b0}};
                                vibrato_rate_mem[target_idx] <= {EXPR_WIDTH{1'b0}};
                            end
                            note_on_count <= note_on_count + 1'b1;
                            if (target_is_steal) begin
                                steal_count <= steal_count + 1'b1;
                                steal_pulse <= 1'b1;
                            end
                        end
                    end else begin
                        if (off_target_valid) begin
                            voice_gate[off_target_idx] <= 1'b0;
                            note_off_count <= note_off_count + 1'b1;
                            if (release_done[off_target_idx]) begin
                                voice_active[off_target_idx] <= 1'b0;
                            end
                        end
                    end

                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule