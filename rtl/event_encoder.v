`timescale 1ns/1ps

module event_encoder #(
    parameter integer KEY_COUNT    = 2,
    parameter integer MAX_EVENTS   = 64,
    parameter integer PTR_WIDTH    = 6,
    parameter integer SOURCE_WIDTH = 5
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [KEY_COUNT-1:0] key_press,
    input  wire [KEY_COUNT-1:0] key_release,
    input  wire [KEY_COUNT*7-1:0] key_velocity_flat,
    input  wire [3:0] input_timbre,
    output wire event_valid,
    output wire event_type,
    output wire [SOURCE_WIDTH-1:0] event_source_id,
    output wire [6:0] event_note,
    output wire [6:0] event_velocity,
    output wire [3:0] event_timbre,
    input  wire event_ready
);

    localparam integer EVENT_WIDTH = SOURCE_WIDTH + 19;

    reg pending_on  [0:KEY_COUNT-1];
    reg pending_off [0:KEY_COUNT-1];
    reg [EVENT_WIDTH-1:0] fifo_mem [0:MAX_EVENTS-1];
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH:0]   fifo_count;

    integer i;
    integer sel_idx;
    integer on_idx;
    integer off_idx;
    reg sel_is_on;
    reg has_on;
    reg has_off;
    reg [SOURCE_WIDTH-1:0] sel_source_id;
    reg [6:0] sel_velocity;
    reg [EVENT_WIDTH-1:0] wr_data;
    wire [EVENT_WIDTH-1:0] rd_data;
    wire do_read;
    wire do_write;

    function [6:0] key_to_note;
        input integer key_index;
        begin
            case (key_index)
                0: key_to_note = 7'd60;
                1: key_to_note = 7'd64;
                2: key_to_note = 7'd67;
                3: key_to_note = 7'd72;
                default: key_to_note = 7'd60 + key_index[6:0];
            endcase
        end
    endfunction

    assign event_valid    = (fifo_count != 0);
    assign rd_data        = fifo_mem[rd_ptr];
    assign event_type     = rd_data[SOURCE_WIDTH+18];
    assign event_source_id = rd_data[SOURCE_WIDTH+17:18];
    assign event_note     = rd_data[17:11];
    assign event_velocity = rd_data[10:4];
    assign event_timbre   = rd_data[3:0];

    assign do_read  = event_valid & event_ready;
    assign do_write = (has_on | has_off) & (fifo_count < MAX_EVENTS);

    always @* begin
        has_on      = 1'b0;
        has_off     = 1'b0;
        on_idx      = 0;
        off_idx     = 0;
        sel_idx     = 0;
        sel_is_on   = 1'b1;
        sel_source_id = {SOURCE_WIDTH{1'b0}};
        sel_velocity  = 7'd0;
        wr_data       = {EVENT_WIDTH{1'b0}};

        for (i = KEY_COUNT-1; i >= 0; i = i - 1) begin
            if (pending_on[i]) begin
                has_on = 1'b1;
                on_idx = i;
            end
        end

        for (i = KEY_COUNT-1; i >= 0; i = i - 1) begin
            if (pending_off[i]) begin
                has_off = 1'b1;
                off_idx = i;
            end
        end

        if (has_on) begin
            sel_idx       = on_idx;
            sel_is_on     = 1'b1;
            sel_source_id = on_idx;
            sel_velocity  = key_velocity_flat[on_idx*7 +: 7];
            wr_data       = {1'b1, sel_source_id, key_to_note(on_idx), sel_velocity, input_timbre};
        end else if (has_off) begin
            sel_idx       = off_idx;
            sel_is_on     = 1'b0;
            sel_source_id = off_idx;
            sel_velocity  = 7'd0;
            wr_data       = {1'b0, sel_source_id, key_to_note(off_idx), 7'd0, input_timbre};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= {PTR_WIDTH{1'b0}};
            rd_ptr     <= {PTR_WIDTH{1'b0}};
            fifo_count <= {(PTR_WIDTH+1){1'b0}};
            for (i = 0; i < KEY_COUNT; i = i + 1) begin
                pending_on[i]  <= 1'b0;
                pending_off[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < KEY_COUNT; i = i + 1) begin
                if (key_press[i]) begin
                    pending_on[i] <= 1'b1;
                end
                if (key_release[i]) begin
                    pending_off[i] <= 1'b1;
                end
            end

            if (do_write) begin
                fifo_mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
                if (sel_is_on) begin
                    pending_on[sel_idx] <= 1'b0;
                end else begin
                    pending_off[sel_idx] <= 1'b0;
                end
            end

            if (do_read) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            if (do_read & do_write) begin
                fifo_count <= fifo_count;
            end else if (do_write) begin
                fifo_count <= fifo_count + 1'b1;
            end else if (do_read) begin
                fifo_count <= fifo_count - 1'b1;
            end
        end
    end

endmodule