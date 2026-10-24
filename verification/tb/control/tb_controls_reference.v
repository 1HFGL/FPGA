`timescale 1ns/1ps
module tb_controls_reference;
    reg clk=0,rst_n=0,valid=0,commit=0;
    reg [29:0] raw=0;
    reg [15:0] peak_in=0;
    wire [13:0] value;
    wire [7:0] height;
    reg [47:0] vectors[0:19999];
    reg [7:0] heights[0:65535];
    integer n;
    always #10 clk=~clk;
    adc_knob_if #(.ADC_WIDTH(15),.READY_SAMPLES(1),.FAULT_TIMEOUT(1000000),
        .FILTER_SHIFT(0),.SLEW_STEP(127),.HYSTERESIS_COUNTS(384),.CENTER_CHANNEL(1)) knob(
        .clk(clk),.rst_n(rst_n),.sample_valid(valid),.raw_flat(raw),.value_flat(value));
    display_feedback meter(.pixel_clk(clk),.rst_n(rst_n),.frame_commit(commit),
        .held(13'd0),.instrument_guitar(1'b0),.raw_peak(peak_in),.meter_height(height));
    initial begin
        $readmemh("build/controls_meter_20261024/knob_reference.hex",vectors);
        $readmemh("build/controls_meter_20261024/meter_reference.hex",heights);
        repeat(3)@(negedge clk);rst_n=1;
        for(n=0;n<20000;n=n+1)begin
            if(vectors[n][44])begin rst_n=0;@(negedge clk);rst_n=1;end
            raw=vectors[n][43:14];valid=1;@(negedge clk);valid=0;
            if(value!==vectors[n][13:0])begin $display("FAIL knob Python reference vector=%0d",n);$finish;end
            @(negedge clk);
        end
        for(n=0;n<65536;n=n+1)begin
            peak_in=n;commit=1;@(negedge clk);commit=0;
            if(height!==heights[n])begin $display("FAIL meter Python reference value=%0d",n);$finish;end
            @(negedge clk);
        end
        $display("PASS tb_controls_reference: 20000 dual-channel vectors with resets, all 65536 meter values vs independent Python");$finish;
    end
endmodule
