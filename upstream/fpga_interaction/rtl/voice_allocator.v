`timescale 1ns/1ps
module voice_allocator #(
    parameter integer VOICES=32, IDX_WIDTH=5, COUNT_WIDTH=6,
    parameter integer TIME_WIDTH=32, // compatibility only; ordering has no clock timestamp
    parameter integer SOURCE_WIDTH=5, BEND_WIDTH=16, EXPR_WIDTH=8,
    parameter integer CHECK_RELEASE_ID=0
) (
    input wire clk, rst_n, event_valid,
    output wire event_ready,
    input wire event_type,
    input wire [SOURCE_WIDTH-1:0] event_source_id,
    input wire [6:0] event_note, event_velocity,
    input wire [3:0] event_timbre,
    input wire sustain_on, source_clear_valid,
    output wire source_clear_ready,
    input wire [SOURCE_WIDTH-1:0] source_clear_id, source_clear_mask,
    input wire expr_valid,
    output wire expr_ready,
    input wire [SOURCE_WIDTH-1:0] expr_source_id,
    input wire [6:0] expr_note,
    input wire [BEND_WIDTH-1:0] expr_pitch_bend,
    input wire [EXPR_WIDTH-1:0] expr_aftertouch, expr_vibrato_depth, expr_vibrato_rate,
    input wire [VOICES-1:0] release_done,
    input wire [VOICES*16-1:0] release_trigger_id_flat,
    output reg [VOICES-1:0] voice_active, voice_gate, voice_key_down,
    output wire [VOICES*16-1:0] voice_trigger_id_flat,
    output wire [VOICES*SOURCE_WIDTH-1:0] voice_source_id_flat,
    output wire [VOICES*7-1:0] voice_note_flat, voice_velocity_flat,
    output wire [VOICES*4-1:0] voice_timbre_flat,
    output wire [VOICES*BEND_WIDTH-1:0] voice_pitch_bend_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_aftertouch_flat, voice_vibrato_depth_flat, voice_vibrato_rate_flat,
    output wire [COUNT_WIDTH-1:0] voice_count,
    output reg [COUNT_WIDTH-1:0] max_voice_count,
    output reg [31:0] note_on_count, note_off_count, steal_count,
    output reg steal_pulse
);
    localparam [2:0] S_IDLE=0, S_SCAN=1, S_EXPR_SCAN=2, S_APPLY=3, S_CLEAR=4;
    reg [2:0] state;
    reg op_expr;
    reg [IDX_WIDTH-1:0] scan_idx;
    reg latched_event_type;
    reg [SOURCE_WIDTH-1:0] latched_source_id, latched_expr_source_id, clear_id, clear_mask;
    reg [6:0] latched_note, latched_velocity, latched_expr_note;
    reg [3:0] latched_timbre;
    reg [BEND_WIDTH-1:0] latched_pitch_bend;
    reg [EXPR_WIDTH-1:0] latched_aftertouch, latched_vibrato_depth, latched_vibrato_rate;
    reg [SOURCE_WIDTH-1:0] source_id_mem [0:VOICES-1];
    reg [6:0] note_mem [0:VOICES-1], velocity_mem [0:VOICES-1];
    reg [3:0] timbre_mem [0:VOICES-1];
    reg [BEND_WIDTH-1:0] pitch_bend_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] aftertouch_mem [0:VOICES-1], vibrato_depth_mem [0:VOICES-1], vibrato_rate_mem [0:VOICES-1];
    reg [15:0] trigger_id_mem [0:VOICES-1];
    // A[i][j]=1 means voice i started before voice j. Uptime cannot change this relation.
    reg [VOICES-1:0] older_than_mem [0:VOICES-1];
    reg same_found, free_found, released_found, oldest_found, off_found, expr_found;
    reg [IDX_WIDTH-1:0] same_idx, free_idx, released_idx, oldest_idx, off_idx, expr_idx;
    reg target_valid, target_same, target_steal;
    reg [IDX_WIDTH-1:0] target_idx;
    reg [COUNT_WIDTH-1:0] active_count;
    integer i, c;
    assign voice_count=active_count;
    assign event_ready=(state==S_IDLE);
    assign source_clear_ready=(state==S_IDLE) && !event_valid;
    assign expr_ready=(state==S_IDLE) && !event_valid && !source_clear_valid;
    always @* begin
        active_count=0;
        for(c=0;c<VOICES;c=c+1) active_count=active_count+voice_active[c];
    end
    always @* begin
        target_valid=same_found | free_found | released_found | oldest_found;
        target_same=same_found; target_steal=0;
        if(same_found) target_idx=same_idx;
        else if(free_found) target_idx=free_idx;
        else if(released_found) begin target_idx=released_idx; target_steal=1; end
        else begin target_idx=oldest_idx; target_steal=oldest_found; end
    end
    genvar g;
    generate for(g=0;g<VOICES;g=g+1) begin:g_flat_out
        assign voice_trigger_id_flat[g*16+:16]=trigger_id_mem[g];
        assign voice_source_id_flat[g*SOURCE_WIDTH+:SOURCE_WIDTH]=source_id_mem[g];
        assign voice_note_flat[g*7+:7]=note_mem[g];
        assign voice_velocity_flat[g*7+:7]=velocity_mem[g];
        assign voice_timbre_flat[g*4+:4]=timbre_mem[g];
        assign voice_pitch_bend_flat[g*BEND_WIDTH+:BEND_WIDTH]=pitch_bend_mem[g];
        assign voice_aftertouch_flat[g*EXPR_WIDTH+:EXPR_WIDTH]=aftertouch_mem[g];
        assign voice_vibrato_depth_flat[g*EXPR_WIDTH+:EXPR_WIDTH]=vibrato_depth_mem[g];
        assign voice_vibrato_rate_flat[g*EXPR_WIDTH+:EXPR_WIDTH]=vibrato_rate_mem[g];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; op_expr<=0; scan_idx<=0;
            voice_active<=0; voice_gate<=0; voice_key_down<=0;
            max_voice_count<=0; note_on_count<=0; note_off_count<=0; steal_count<=0; steal_pulse<=0;
            same_found<=0; free_found<=0; released_found<=0; oldest_found<=0; off_found<=0; expr_found<=0;
            same_idx<=0; free_idx<=0; released_idx<=0; oldest_idx<=0; off_idx<=0; expr_idx<=0;
            for(i=0;i<VOICES;i=i+1) begin
                source_id_mem[i]<=0; note_mem[i]<=0; velocity_mem[i]<=0; timbre_mem[i]<=0;
                pitch_bend_mem[i]<=0; aftertouch_mem[i]<=0; vibrato_depth_mem[i]<=0; vibrato_rate_mem[i]<=0;
                trigger_id_mem[i]<=0; older_than_mem[i]<=0;
            end
        end else begin
            steal_pulse<=0;
            if(active_count>max_voice_count) max_voice_count<=active_count;
            for(i=0;i<VOICES;i=i+1) begin
                if(voice_active[i] && !voice_key_down[i] && release_done[i] &&
                   (!CHECK_RELEASE_ID || release_trigger_id_flat[i*16+:16]==trigger_id_mem[i])) begin
                    voice_active[i]<=0; voice_gate[i]<=0;
                end
                if(!sustain_on && voice_active[i] && !voice_key_down[i]) voice_gate[i]<=0;
            end
            case(state)
                S_IDLE: begin
                    if(event_valid) begin
                        op_expr<=0; latched_event_type<=event_type; latched_source_id<=event_source_id;
                        latched_note<=event_note; latched_velocity<=event_velocity; latched_timbre<=event_timbre;
                        scan_idx<=0; same_found<=0; free_found<=0; released_found<=0; oldest_found<=0; off_found<=0;
                        state<=S_SCAN;
                    end else if(source_clear_valid) begin
                        clear_id<=source_clear_id; clear_mask<=source_clear_mask; scan_idx<=0; state<=S_CLEAR;
                    end else if(expr_valid) begin
                        op_expr<=1; latched_expr_source_id<=expr_source_id; latched_expr_note<=expr_note;
                        latched_pitch_bend<=expr_pitch_bend; latched_aftertouch<=expr_aftertouch;
                        latched_vibrato_depth<=expr_vibrato_depth; latched_vibrato_rate<=expr_vibrato_rate;
                        scan_idx<=0; expr_found<=0; state<=S_EXPR_SCAN;
                    end
                end
                S_SCAN: begin
                    // Equal pitches from different sources must never close or replace one another.
                    if(voice_active[scan_idx] && voice_key_down[scan_idx] &&
                       source_id_mem[scan_idx]==latched_source_id && note_mem[scan_idx]==latched_note) begin
                        same_found<=1; same_idx<=scan_idx; off_found<=1; off_idx<=scan_idx;
                    end
                    if(!voice_active[scan_idx] && !free_found) begin free_found<=1; free_idx<=scan_idx; end
                    if(voice_active[scan_idx] && !voice_key_down[scan_idx] &&
                       (!released_found || older_than_mem[scan_idx][released_idx])) begin
                        released_found<=1; released_idx<=scan_idx;
                    end
                    if(voice_active[scan_idx] && voice_key_down[scan_idx] &&
                       (!oldest_found || older_than_mem[scan_idx][oldest_idx])) begin
                        oldest_found<=1; oldest_idx<=scan_idx;
                    end
                    if(scan_idx==VOICES-1) state<=S_APPLY; else scan_idx<=scan_idx+1'b1;
                end
                S_EXPR_SCAN: begin
                    if(voice_active[scan_idx] && voice_key_down[scan_idx] &&
                       source_id_mem[scan_idx]==latched_expr_source_id && note_mem[scan_idx]==latched_expr_note) begin
                        expr_found<=1; expr_idx<=scan_idx;
                    end
                    if(scan_idx==VOICES-1) state<=S_APPLY; else scan_idx<=scan_idx+1'b1;
                end
                S_CLEAR: begin
                    if(voice_active[scan_idx] && (source_id_mem[scan_idx]&clear_mask)==(clear_id&clear_mask)) begin
                        voice_key_down[scan_idx]<=0; voice_gate[scan_idx]<=0;
                    end
                    if(scan_idx==VOICES-1) state<=S_IDLE; else scan_idx<=scan_idx+1'b1;
                end
                S_APPLY: begin
                    if(op_expr) begin
                        if(expr_found) begin
                            pitch_bend_mem[expr_idx]<=latched_pitch_bend; aftertouch_mem[expr_idx]<=latched_aftertouch;
                            vibrato_depth_mem[expr_idx]<=latched_vibrato_depth; vibrato_rate_mem[expr_idx]<=latched_vibrato_rate;
                        end
                    end else if(latched_event_type && target_valid) begin
                        voice_active[target_idx]<=1; voice_gate[target_idx]<=1; voice_key_down[target_idx]<=1;
                        trigger_id_mem[target_idx]<=trigger_id_mem[target_idx]+1'b1;
                        source_id_mem[target_idx]<=latched_source_id; note_mem[target_idx]<=latched_note;
                        velocity_mem[target_idx]<=latched_velocity; timbre_mem[target_idx]<=latched_timbre;
                        older_than_mem[target_idx]<=0;
                        for(i=0;i<VOICES;i=i+1) if(i!=target_idx) older_than_mem[i][target_idx]<=voice_active[i];
                        if(!target_same) begin
                            pitch_bend_mem[target_idx]<=0; aftertouch_mem[target_idx]<=0;
                            vibrato_depth_mem[target_idx]<=0; vibrato_rate_mem[target_idx]<=0;
                        end
                        note_on_count<=note_on_count+1'b1;
                        if(target_steal) begin steal_count<=steal_count+1'b1; steal_pulse<=1; end
                    end else if(!latched_event_type && off_found) begin
                        voice_key_down[off_idx]<=0; voice_gate[off_idx]<=sustain_on;
                        note_off_count<=note_off_count+1'b1;
                    end
                    state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
