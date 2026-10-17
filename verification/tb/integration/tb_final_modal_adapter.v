`timescale 1ns/1ps
// 与未经修改的A核心并行逐点比较；参考侧独立保存已返回的触发代次。
module tb_final_modal_adapter;
    reg clk=0,rst_n=0,request=0;
    always #10 clk=~clk;
    reg [15:0] gates=0,guitar=0;
    reg [111:0] notes=0,velocities={16{7'd100}};
    reg [255:0] ids=0,reference_ids=0,reference_batch=0;
    reg [16:0] gain=65536,ratio=65536;
    wire [255:0] ack;
    wire [15:0] released;
    wire busy,valid,overrun,sounding,clipped;
    wire signed [15:0] sample_data;
    voice_bank_modal_adapter dut(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .master_gain(gain),.bend_ratio(ratio),.voice_gate(gates),.voice_guitar(guitar),
        .voice_note_flat(notes),.voice_velocity_flat(velocities),.voice_trigger_id_flat(ids),
        .release_trigger_id_flat(ack),.release_done(released),.sounding(sounding),
        .busy(busy),.overrun(overrun),.sample_data(sample_data),.sample_valid(valid),.sample_clipped(clipped));
    wire [15:0] reference_trigger;
    wire ref_busy,ref_valid,ref_overrun,ref_sounding,ref_clip;
    genvar v;
    generate for(v=0;v<16;v=v+1)begin:g_ref
        assign reference_trigger[v]=request && !ref_busy && ids[v*16+:16]!=reference_ids[v*16+:16];
    end endgenerate
    wire signed [15:0] ref_sample;
    voice_bank_music_pipe reference(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .global_gain_q16(gain),.pitch_ratio_q16(ratio),.voice_gate(gates),
        .voice_retrigger(reference_trigger),.voice_instrument(~guitar),
        .voice_note_flat(notes),.voice_velocity_flat(velocities),.voice_active(),.release_done(),
        .instrument_active(),.env_level_flat(),.sounding(ref_sounding),.busy(ref_busy),
        .sample_data(ref_sample),.sample_valid(ref_valid),.sample_clipped(ref_clip),.overrun(ref_overrun));
    integer cycle=0,issue_cycle=0,checked=0,nonzero=0,k,frame;
    reg outstanding=0;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!rst_n)begin reference_ids<=0;reference_batch<=0;outstanding<=0;end
        else begin
            if(request && !ref_busy)begin reference_batch<=ids;issue_cycle=cycle;outstanding<=1;end
            if(ref_valid)begin reference_ids<=reference_batch;outstanding<=0;end
        end
        #1;
        if(rst_n)begin
            if({valid,busy,overrun,sounding,clipped,sample_data}!==
               {ref_valid,ref_busy,ref_overrun,ref_sounding,ref_clip,ref_sample})begin
                $display("FAIL modal golden mismatch frame=%0d sample=%0d ref=%0d",checked,sample_data,ref_sample);$finish;
            end
            if((busy || valid) && released!==0)begin $display("FAIL stale release while modal batch active");$finish;end
            if(ack!==reference_ids)begin $display("FAIL modal generation acknowledgement");$finish;end
            if(valid)begin
                if(cycle-issue_cycle!=923)begin $display("FAIL modal latency=%0d expected923",cycle-issue_cycle);$finish;end
                checked=checked+1;if(sample_data!=0)nonzero=nonzero+1;
            end
        end
    end
    task tick_frame;
        begin
            @(negedge clk);request=1;
            @(negedge clk);request=0;
            repeat(1041)@(negedge clk);
        end
    endtask
    initial begin
        for(k=0;k<16;k=k+1)notes[k*7+:7]=60+k;
        repeat(4)@(negedge clk);rst_n=1;
        gates=16'hffff;ids={16{16'd1}};
        repeat(64)tick_frame;
        guitar=16'haaaa;ids={16{16'd2}};
        repeat(64)tick_frame;
        // 一批计算中途改变下一音的归属/代次；不能用新id确认旧结果。
        @(negedge clk);request=1;
        @(negedge clk);request=0;
        repeat(200)@(negedge clk);ids[15:0]=3;guitar[0]=1;notes[6:0]=72;
        repeat(842)@(negedge clk);
        repeat(32)tick_frame;
        gain=0;repeat(8)tick_frame;
        if(sample_data!==0)begin $display("FAIL modal master mute");$finish;end
        gain=32768;ratio=58386;repeat(32)tick_frame;
        gain=65536;ratio=73562;repeat(32)tick_frame;
        gates=0;repeat(4200)tick_frame;
        if(released!==16'hffff || sounding!==0)begin $display("FAIL modal tail drain");$finish;end
        ids[15:0]=16'hffff;gates[0]=1;tick_frame;
        ids[15:0]=0;tick_frame;
        // 忙时再次请求必须报告overrun，随后复位清除。
        @(negedge clk);request=1;@(negedge clk);request=0;
        repeat(20)@(negedge clk);request=1;@(negedge clk);request=0;
        repeat(3)@(negedge clk);
        if(!overrun)begin $display("FAIL modal overrun not observed");$finish;end
        rst_n=0;repeat(3)@(negedge clk);request=0;gates=0;ids=0;rst_n=1;
        tick_frame;
        if(overrun || sample_data!==0 || ack!==0)begin $display("FAIL modal reset recovery");$finish;end
        if(checked<4400 || nonzero<100)begin $display("FAIL modal ineffective stimulus samples=%0d nonzero=%0d",checked,nonzero);$finish;end
        $display("PASS tb_final_modal_adapter: samples=%0d nonzero=%0d R923 golden, generations, tails, control, recovery",checked,nonzero);$finish;
    end
    initial begin #120000000; $display("FAIL modal adapter timeout");$finish;end
endmodule
