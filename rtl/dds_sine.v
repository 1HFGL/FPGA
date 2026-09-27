module dds_sine (
    input            clk,
    input            rst_n,
    input            en,
    input      [3:0] phase_step,
    output reg [7:0] wave_out
);

    reg [3:0] phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 4'd0;  //复位
        end else if (en) begin
            phase <= phase + phase_step;  //累加
        end
    end
    always @(*) begin
        case (phase)
            4'd0: wave_out = 8'd128;
            4'd1: wave_out = 8'd177;
            4'd2: wave_out = 8'd218;
            4'd3: wave_out = 8'd246;
            4'd4: wave_out = 8'd255;
            4'd5: wave_out = 8'd246;
            4'd6: wave_out = 8'd218;
            4'd7: wave_out = 8'd177;
            4'd8: wave_out = 8'd128;
            4'd9: wave_out = 8'd79;
            4'd10: wave_out = 8'd38;
            4'd11: wave_out = 8'd10;
            4'd12: wave_out = 8'd0;
            4'd13: wave_out = 8'd10;
            4'd14: wave_out = 8'd38;
            4'd15: wave_out = 8'd79;
            default: wave_out = 8'd128;
        endcase
    end

endmodule
