`timescale 1ns/1ps
module tb_wave_lut_timbre;
    reg clk=0, rst=1, en=0, timbre=0;
    reg [9:0] addr=0;
    wire signed [15:0] sample;
    wire valid;
    always #10 clk=~clk;
    wave_lut_timbre dut(.clk(clk),.rst(rst),.read_en(en),.addr(addr),
        .timbre(timbre),.sample(sample),.sample_valid(valid));
    integer checks=0, expected=0, a, t;
    function integer value(input integer address, tone);
        real angle, y;
        begin
            angle=6.283185307179586*address/1024.0;
            y=(tone==0)?32767.0*$sin(angle):32767.0*
                (8*$sin(angle)+4*$sin(2*angle)+2*$sin(3*angle)+$sin(4*angle))/15.0;
            value=(y>=0)?$rtoi(y+0.5):$rtoi(y-0.5);
        end
    endfunction
    task read_cycle(input bit reset, enable, tone, input integer address);
        @(negedge clk); rst=reset; en=enable; timbre=tone; addr=address;
        if(reset) expected=0; else if(enable) expected=value(address,tone);
        @(posedge clk); #2;
        if($signed(sample)!==expected || valid!==(enable&&!reset))
            $fatal(1,"two-ROM addr=%0d tone=%0d got=%0d expected=%0d valid=%b",address,tone,$signed(sample),expected,valid);
        checks++;
    endtask

    // 直接在相位步长边界验证4次谐波保护，不仅测试MIDI查表中的几个音符。
    reg vr=1, ve=0, vg=0, vt=0;
    reg [31:0] inc=0;
    wire signed [15:0] vs;
    wire vv, va;
    wire [16:0] vl;
    voice_timbre_adsr #(.ATTACK_SAMPLES(0),.DECAY_SAMPLES(1),
        .SUSTAIN_LEVEL(65536),.RELEASE_SAMPLES(1)) voice (
        .clk(clk),.rst(vr),.sample_tick(ve),.phase_inc(inc),.gate(vg),
        .retrigger(ve),.timbre(vt),.sample(vs),.sample_valid(vv),.env_level(vl),.voice_active(va));
    reg [31:0] ref_phase=0;
    reg queued=0, expected_v=0;
    integer raw_q=0, expected_voice=0, voice_checks=0, fallback=0, bright=0;
    always @(posedge clk) begin
        if(vr) begin ref_phase=0; queued=0; expected_v=0; raw_q=0; expected_voice=0; end
        else begin
            expected_v=queued;
            if(queued) expected_voice=raw_q;
            queued=ve;
            if(ve) begin
                raw_q=vg?value(ref_phase>>22,vt && inc<32'h20000000):0;
                if(vt && inc>=32'h20000000) fallback++;
                if(vt && inc<32'h20000000) bright++;
                ref_phase=ref_phase+inc;
            end
        end
        #1;
        if(vv!==expected_v || $signed(vs)!==expected_voice)
            $fatal(1,"voice threshold/pipeline check inc=%h actual=%0d expected=%0d",inc,$signed(vs),expected_voice);
        voice_checks++;
    end
    integer k;
    initial begin
        read_cycle(1,1,1,193);
        for(a=0;a<1024;a++) for(t=0;t<2;t++) read_cycle(0,1,t,a);
        repeat(8) read_cycle(0,0,1,23);
        read_cycle(1,1,1,800);
        read_cycle(0,1,1,511);
        read_cycle(0,0,0,12);
        read_cycle(0,1,0,255);
        for(k=0;k<1200;k++) begin
            @(negedge clk); vr=(k%307==0); ve=(k%7!=0); vg=1; vt=(k%5!=0);
            case(k%4)
                0:inc=32'h1fffffff;
                1:inc=32'h20000000;
                2:inc=32'h20000001;
                3:inc=32'd39370534; // A4附近，不依赖查表来决定保护边界
            endcase
        end
        @(negedge clk); ve=0;
        repeat(4) @(negedge clk);
        if(bright<100 || fallback<100) $fatal(1,"missing threshold coverage");
        $display("ROM addresses verified=2048, clock checks=%0d, voice checks=%0d, bright=%0d fallback=%0d",checks,voice_checks,bright,fallback);
        $display("PASS: two timbre ROMs, idle/reset, direct threshold and R1 pipeline.");
        $finish;
    end
endmodule
