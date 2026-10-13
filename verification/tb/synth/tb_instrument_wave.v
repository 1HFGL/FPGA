`timescale 1ns/1ps
module tb_instrument_wave;
    reg clk=0, rst=1, en=0, instrument=0, harmonics=0;
    reg [9:0] addr=0;
    wire signed [15:0] base_sample, full_sample;
    wire valid;
    always #10 clk=~clk;
    instrument_wave dut(.clk(clk),.rst(rst),.read_en(en),.addr(addr),
        .instrument(instrument),.harmonics_enable(harmonics),
        .base_sample(base_sample),.full_sample(full_sample),.sample_valid(valid));
    integer checks=0, expected_base=0, expected_full=0, a, t, h;
    // 独立解析公式，不读被测ROM，不调用波表生成脚本。
    function integer rounded(input real y);
        rounded=(y>=0)?$rtoi(y+0.5):$rtoi(y-0.5);
    endfunction
    function integer wave(input integer address, preset);
        real x,y;
        begin
            x=6.283185307179586*address/1024.0;
            if(preset==0) y=32767.0*(16*$sin(x)+8*$sin(2*x)+4*$sin(3*x)+2*$sin(5*x)+$sin(6*x)+$sin(7*x))/32.0;
            else y=32767.0*(16*$sin(x)+6*$sin(2*x)+3*$sin(3*x)+2*$sin(4*x)+2*$sin(5*x)+$sin(6*x)+$sin(7*x)+$sin(8*x))/32.0;
            wave=rounded(y);
        end
    endfunction
    function integer base(input integer address);
        base=rounded(32767.0*$sin(6.283185307179586*address/1024.0))>>>1;
    endfunction
    task read_cycle(input reset,enable,preset,harm,input integer address);
        begin
@(negedge clk); rst=reset; en=enable; instrument=preset; harmonics=harm; addr=address;
        if(reset) begin expected_base=0; expected_full=0; end
        else if(enable) begin expected_base=base(address); expected_full=harm?wave(address,preset):expected_base; end
        @(posedge clk); #2;
        if($signed(base_sample)!==expected_base || $signed(full_sample)!==expected_full || valid!==(enable&&!reset))
            begin $display("FAIL: ROM mismatch addr=%0d preset=%0d harmonics=%0d",address,preset,harm); $finish; end
        checks=checks+1;
        end
    endtask
    // 默认保护阈值的前一点/等于/后一点直接测试，避免只依赖MIDI查表。
    // 每次请求都显式重触发，A=1且S=1，让包络恒1、亮度固定起点。
    reg vr=1, ve=0, vi=0;
    reg [31:0] inc=0;
    wire signed [15:0] vs;
    wire vv, va, selected;
    wire [16:0] vl, tone;
    voice_instrument #(.G_ATTACK(1),.G_DECAY(1),.G_SUSTAIN(65536),.G_RELEASE(1),
        .S_ATTACK(1),.S_DECAY(1),.S_SUSTAIN(65536),.S_RELEASE(1)) voice (
        .clk(clk),.rst(vr),.sample_tick(ve),.phase_inc(inc),.gate(1'b1),
        .retrigger(ve),.instrument(vi),.sample(vs),.sample_valid(vv),.env_level(vl),
        .tone_level(tone),.voice_active(va),.active_instrument(selected));
    reg [31:0] phase=0;
    reg q0=0,q1=0,expect_valid=0;
    integer s0=0,s1=0,expect_sample=0,b,f,k,voice_checks=0,guarded=0,rich=0;
    reg signed [63:0] product;
    always @(posedge clk) begin
        if(vr) begin phase=0;q0=0;q1=0;expect_valid=0;s0=0;s1=0;expect_sample=0;end
        else begin
            expect_valid=q1;
            if(q1) expect_sample=s1;
            q1=q0; s1=s0; q0=ve;
            if(ve) begin
                b=base(phase>>22); f=(inc<32'h10000000)?wave(phase>>22,vi):b;
                product=f-b; product=product*(vi?8192:65536);
                s0=b+(product>>>16);
                if(inc<32'h10000000) rich=rich+1; else guarded=guarded+1;
                phase=phase+inc;
            end
        end
        #1;
        if(vv!==expect_valid || $signed(vs)!==expect_sample)
            begin $display("FAIL: R2 guard/pipeline mismatch inc=%h actual=%0d expected=%0d",inc,$signed(vs),expect_sample); $finish; end
        voice_checks=voice_checks+1;
    end
    initial begin
        read_cycle(1,1,1,1,193);
        for(a=0;a<1024;a=a+1) for(t=0;t<2;t=t+1) for(h=0;h<2;h=h+1) read_cycle(0,1,t,h,a);
        repeat(8) read_cycle(0,0,1,0,23);
        read_cycle(1,1,1,1,800);
        read_cycle(0,1,1,1,511);
        read_cycle(0,0,0,0,12);
        for(k=0;k<1400;k=k+1) begin
            @(negedge clk); vr=(k%307==0); ve=(k%7!=0); vi=(k%2);
            case(k%4)
                0:inc=32'h0fffffff;1:inc=32'h10000000;2:inc=32'h10000001;3:inc=32'd39370534;
            endcase
        end
        @(negedge clk); ve=0;
        repeat(5) @(negedge clk);
        if(rich<100 || guarded<100) begin $display("FAIL: missing threshold coverage"); $finish; end
        $display("ROM checks=%0d voice clocks=%0d rich=%0d guarded=%0d",checks,voice_checks,rich,guarded);
        $display("PASS: instrument ROMs, direct threshold and R2 pipeline.");
        $finish;
    end
endmodule
