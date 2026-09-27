module dds (
    input        clk,
    input        rst_n,
    input        en,
    input  [7:0] phase_step,
    output       wave_out
);

    reg [7:0] phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 8'd0;  //复位
        end else if (en) begin
            phase <= phase + phase_step;  //累加
        end
    end

    assign wave_out = phase[7];







endmodule
