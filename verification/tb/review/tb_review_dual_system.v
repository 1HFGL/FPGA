`timescale 1ns/1ps
// 正式板级双模式：KEY2消抖/保持、13实体键+UART共享16路、尾音/抢占/音量弯音。
module tb_review_dual_system;
    reg clk=0,rst=0,rx=1;
    reg [1:0] board_keys=3;
    reg [12:0] keys=13'h1fff;
    reg [13:0] knobs={7'd64,7'd127};
    reg knob_valid=0;
    tri1 sda;
    wire tx,bck,ws,din,pa,scl;
    integer frames=0,cycle=0,request_at=0,n,heard[0:15],total_heard=0;
    reg signed [33:0] product;
    reg signed [15:0] expected;
    always #10 clk=~clk;
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16),.ATTACK_SAMPLES(4),.DECAY_SAMPLES(57600),.RELEASE_SAMPLES(64)) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(board_keys),.piano_key_n(keys),.uart_rx(rx),.uart_tx(tx),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_sda(sda),.knob_scl(scl));
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!dut.u_core.audio_ready)begin frames=0;request_at=0;end
        else begin
            if(dut.u_core.sample_request)begin frames=frames+1;request_at=cycle;end
            if(frames>4 && dut.u_core.sample_underrun)begin $display("FAIL dual system underrun");$finish;end
            if(dut.u_core.sample_valid && cycle-request_at!=7)begin $display("FAIL dual system R7 contract");$finish;end
            if(dut.u_core.bank_sample_valid)begin
                for(n=0;n<16;n=n+1)if($signed(dut.u_core.u_bank.gain_samples[n*16+:16])!=0)heard[n]=heard[n]+1;
                product=$signed(dut.u_core.bank_sample_data)*$signed({1'b0,dut.u_core.g_controls.gain_d4});
                expected=product>>>16;
                #1;if(dut.u_core.sample_data!==expected)begin $display("FAIL dual system master gain alignment");$finish;end
            end
        end
    end
    task wait_frames;
        input integer count;
        integer start;
        begin start=frames;wait(frames>=start+count);@(negedge clk);end
    endtask
    task send;
        input [511:0] text;
        integer bytes,a,b,k;
        begin
            bytes=0;for(k=0;k<64;k=k+1)if(text[k*8+:8]!=0)bytes=k+1;
            for(a=bytes-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end
            repeat(40)@(negedge clk);
        end
    endtask
    task select_knobs;
        input [6:0] volume,bend;
        begin @(negedge clk);knobs={bend,volume};knob_valid=1;@(negedge clk);knob_valid=0;wait_frames(70);end
    endtask
    initial begin
        for(n=0;n<16;n=n+1)heard[n]=0;
        force dut.knob_value_flat=knobs;force dut.knob_valid=knob_valid;
        force dut.param_ready=1'b1;force dut.param_fault=1'b0;
        repeat(8)@(negedge clk);rst=1;wait_frames(8);
        keys[0]=0;wait_frames(30);
        if(dut.u_core.voice_count!=1 || dut.u_core.monitor_instrument_guitar!==0)begin $display("FAIL dual startup piano");$finish;end
        // 短抖动不切换；稳定按下切一次，长按不能重复切换或弹出E4。
        board_keys[1]=0;repeat(2)@(negedge clk);board_keys[1]=1;repeat(20)@(negedge clk);
        if(dut.u_core.monitor_instrument_guitar!==0)begin $display("FAIL dual bounce changed mode");$finish;end
        board_keys[1]=0;wait(dut.u_core.monitor_instrument_guitar);wait_frames(20);
        if(dut.u_core.voice_count!=1 || dut.u_core.voice_timbre_flat[3:0]!=0)begin $display("FAIL mode key played note or changed old piano");$finish;end
        keys[4]=0;wait_frames(30);
        if(dut.u_core.voice_count!=2 || dut.u_core.voice_timbre_flat[7:4]!=1)begin $display("FAIL dual new guitar");$finish;end
        if(dut.u_core.u_bank.g_voice[1].u_voice.g_dual.u_instrument.active_instrument!==0 ||
           dut.u_core.u_bank.g_voice[0].u_voice.g_dual.u_instrument.active_instrument!==1)begin
            $display("FAIL dual synthesis guitar selection not connected");$finish;
        end
        wait_frames(10);if(dut.u_core.monitor_instrument_guitar!==1)begin $display("FAIL dual hold repeated toggle");$finish;end
        board_keys[1]=1;repeat(32)@(negedge clk);board_keys[1]=0;
        wait(!dut.u_core.monitor_instrument_guitar);board_keys[1]=1;keys[7]=0;wait_frames(30);
        if(dut.u_core.voice_timbre_flat[7:4]!=1 || dut.u_core.voice_timbre_flat[11:8]!=0)begin $display("FAIL old guitar or new piano ownership");$finish;end
        if(dut.u_core.u_bank.g_voice[1].u_voice.g_dual.u_instrument.active_instrument!==0 ||
           dut.u_core.u_bank.g_voice[2].u_voice.g_dual.u_instrument.active_instrument!==1)begin
            $display("FAIL dual synthesis old/new preset mismatch");$finish;
        end
        keys=0;wait_frames(60);if(dut.u_core.voice_count!=13)begin $display("FAIL dual 13 physical keys");$finish;end
        send("HELLO\n");send("NOTE_ON 60 100 0\n");send("NOTE_ON 64 100 0\n");send("NOTE_ON 67 100 0\n");wait_frames(60);
        if(dut.u_core.voice_count!=16)begin $display("FAIL dual shared 16 voices");$finish;end
        for(n=0;n<16;n=n+1)if(heard[n]>10)total_heard=total_heard+1;
        if(total_heard!=16)begin $display("FAIL dual silent occupied voices %0d",total_heard);$finish;end
        select_knobs(32,127);
        if(dut.u_core.master_gain>=20000 || dut.u_core.bend_ratio!=73562)begin $display("FAIL dual knobs");$finish;end
        send("NOTE_ON 72 100 0\n");wait_frames(8);
        if(dut.u_core.voice_count!=16 || dut.u_core.steal_count==0)begin $display("FAIL dual seventeenth note");$finish;end
        keys=13'h1fff;send("PANIC\n");wait_frames(4500);
        if(dut.u_core.voice_count!=0 || dut.u_core.monitor_key_down!=0)begin $display("FAIL dual tails not recycled");$finish;end
        board_keys[1]=0;repeat(40)@(negedge clk);wait_frames(3);
        if(dut.u_core.voice_count!=0)begin $display("FAIL isolated mode key produced audio");$finish;end
        rst=0;repeat(8)@(negedge clk);board_keys=3;rst=1;wait_frames(5);
        if(dut.u_core.monitor_instrument_guitar!==0 || dut.u_core.voice_count!=0)begin $display("FAIL dual reset defaults");$finish;end
        $display("PASS tb_review_dual_system: KEY2/bounce/hold, old tails, 13 keys+UART/16 audible voices, steal, knobs, R7 and reset");$finish;
    end
    initial begin #150000000;$display("FAIL dual system timeout");$finish;end
endmodule
