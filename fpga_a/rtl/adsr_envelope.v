`timescale 1ns/1ps

module adsr_envelope #(
    parameter integer ATTACK_STEP   = 2048,
    parameter integer DECAY_STEP    = 256,
    parameter integer RELEASE_STEP  = 256,
    parameter integer SUSTAIN_LEVEL = 49152
) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_tick,
    input  wire gate,
    input  wire retrigger,
    output reg  [15:0] level,
    output reg  release_done
);

    localparam [2:0] E_IDLE    = 3'd0;
    localparam [2:0] E_ATTACK  = 3'd1;
    localparam [2:0] E_DECAY   = 3'd2;
    localparam [2:0] E_SUSTAIN = 3'd3;
    localparam [2:0] E_RELEASE = 3'd4;

    reg [2:0] state;
    reg gate_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= E_IDLE;
            gate_d <= 1'b0;
            level <= 16'd0;
            release_done <= 1'b0;
        end else if (sample_tick) begin
            gate_d <= gate;
            release_done <= 1'b0;

            if (retrigger || (gate && !gate_d)) begin
                state <= E_ATTACK;
                level <= 16'd0;
            end else begin
                case (state)
                    E_IDLE: begin
                        level <= 16'd0;
                        if (gate) state <= E_ATTACK;
                    end
                    E_ATTACK: begin
                        if (!gate) begin
                            state <= E_RELEASE;
                        end else if ((level + ATTACK_STEP) >= 16'hFFFF) begin
                            level <= 16'hFFFF;
                            state <= E_DECAY;
                        end else begin
                            level <= level + ATTACK_STEP;
                        end
                    end
                    E_DECAY: begin
                        if (!gate) begin
                            state <= E_RELEASE;
                        end else if (level <= (SUSTAIN_LEVEL + DECAY_STEP)) begin
                            level <= SUSTAIN_LEVEL;
                            state <= E_SUSTAIN;
                        end else begin
                            level <= level - DECAY_STEP;
                        end
                    end
                    E_SUSTAIN: begin
                        level <= SUSTAIN_LEVEL;
                        if (!gate) state <= E_RELEASE;
                    end
                    E_RELEASE: begin
                        if (gate) begin
                            state <= E_ATTACK;
                        end else if (level <= RELEASE_STEP) begin
                            level <= 16'd0;
                            release_done <= 1'b1;
                            state <= E_IDLE;
                        end else begin
                            level <= level - RELEASE_STEP;
                        end
                    end
                    default: state <= E_IDLE;
                endcase
            end
        end
    end

endmodule
