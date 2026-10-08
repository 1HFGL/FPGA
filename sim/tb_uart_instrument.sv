`timescale 1ns/1ps
// 真位级串口->分配器->四路合成->DAC逐字检查；只缩短UART和包络/消抖。
// 50MHz/48kHz保持真实比例。本测试不声称实际串口/模拟电路/整机延迟。
module tb_uart_instrument #(parameter integer BIT_CYCLES=16);
    reg clk=0,rst=0,rx=1;
    reg [1:0] keys=3;
    wire tx,bck,ws,din,pa;
    integer cycle=0,frames=0,words=0,bits=0,request_at=0,total=0,nonzero=0,i;
    reg [15:0] previous=0,received=0,expected[0:4095];
    always #10 clk=~clk;
    instrument_uart_top #(.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(BIT_CYCLES),.WATCHDOG_CYCLES(150000),
        .ATTACK_SAMPLES(5),.DECAY_SAMPLES(7),.RELEASE_SAMPLES(13),.ROM_FILE("rtl/rom/sine_1024.mem")) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(keys),.uart_rx(rx),.uart_tx(tx),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!dut.audio_ready) begin frames=0; previous=0; request_at=0; end
        else begin
            if(dut.sample_request) begin
                if(frames>=4096) $fatal(1,"scoreboard overflow");
                expected[frames]=previous; frames=frames+1; request_at=cycle;
            end
            if(dut.sample_valid) begin
                if(cycle-request_at!=4 || dut.sample_clipped!==0) $fatal(1,"R4/clipping");
                previous=dut.sample_data;
            end
        end
    end
    always @(posedge bck or negedge rst) begin
        if(!rst) begin bits=0; words=0; received=0; end
        else if(dut.audio_ready) begin
            if(ws!==(words%2) || dut.sample_underrun!==(words<2)) $fatal(1,"channel/underrun");
            received={received[14:0],din}; bits=bits+1;
            if(bits==16) begin
                if(received!==expected[words/2]) $fatal(1,"serial mismatch word %0d",words);
                if(received!=0) nonzero=nonzero+1;
                words=words+1; total=total+1; bits=0;
            end
        end
    end
    task send(input string text);
        integer a,b;
        begin
            for(a=0;a<text.len();a=a+1) begin
                @(negedge clk); rx=0; repeat(BIT_CYCLES) @(negedge clk);
                for(b=0;b<8;b=b+1) begin rx=(text[a]>>b)&1; repeat(BIT_CYCLES) @(negedge clk); end
                rx=1; repeat(BIT_CYCLES) @(negedge clk);
            end
            repeat(20) @(negedge clk);
        end
    endtask
    task wait_frames(input integer n);
        integer start;
        begin start=frames; wait(frames>=start+n); @(negedge clk); end
    endtask
    function integer held_pc;
        integer v;
        begin
            held_pc=0;
            for(v=0;v<4;v=v+1)
                if(dut.voice_gate[v] && dut.voice_source_flat[v*8+7]) held_pc=held_pc+1;
        end
    endfunction
    initial begin
        repeat(5) @(negedge clk); rst=1; wait_frames(5);
        if(dut.voice_count!=0 || pa!==1) $fatal(1,"idle");
        send("HELLO\n"); wait_frames(2);
        send("NOTE_ON 60 100 0\n"); send("NOTE_ON 64 100 0\n");
        send("NOTE_ON 67 100 0\n"); send("NOTE_ON 72 100 0\n"); wait_frames(10);
        if(dut.voice_count!=4 || held_pc()!=4 || dut.max_voice_count!=4) $fatal(1,"four PC voices");
        send("NOTE_ON 72 100 0\n"); if(held_pc()!=4 || dut.steal_count!=0) $fatal(1,"retrigger");
        send("NOTE_ON 74 100 0\n"); if(held_pc()!=4 || dut.steal_count!=1) $fatal(1,"fifth steal");
        send("NOTE_OFF 60 0\n"); if(held_pc()!=4) $fatal(1,"stale note off");
        send("PANIC\n"); wait_frames(2);
        if(held_pc()!=0 || dut.voice_count==0) $fatal(1,"panic must retain tail");
        wait_frames(25); if(dut.voice_count!=0 || pa!==1) $fatal(1,"panic tail stuck");
        keys=2; wait_frames(8);
        send("NOTE_ON 60 100 0\n"); send("NOTE_ON 64 100 0\n"); wait_frames(5);
        if(dut.voice_count!=3 || held_pc()!=2) $fatal(1,"physical/PC same pitch merged");
        send("NOTE_OFF 60 0\n"); wait_frames(25);
        if(dut.voice_count!=2 || held_pc()!=1) $fatal(1,"PC off damaged physical");
        send("NOTE_ON 60 100 0\n"); send("PANIC\n"); wait_frames(25);
        if(dut.voice_count!=1 || held_pc()!=0 || pa!==0) $fatal(1,"panic damaged physical");
        send("NOTE_ON 67 100 0\n"); repeat(150010) @(negedge clk); wait_frames(25);
        if(dut.session_ready || held_pc()!=0 || dut.voice_count!=1) $fatal(1,"watchdog ownership");
        send("NOTE_ON 72 100 0\n"); wait_frames(5); if(dut.voice_count!=1) $fatal(1,"unready played");
        send("HELLO\n"); wait_frames(2); send("NOTE_ON 72 100 0\n"); wait_frames(5);
        if(dut.voice_count!=2) $fatal(1,"reconnect");
        rst=0; #1; if(tx!==1 || pa!==1) $fatal(1,"midstream reset");
        repeat(5) @(negedge clk); rst=1; wait_frames(15);
        if(dut.session_ready || dut.voice_count!=1 || held_pc()!=0) $fatal(1,"reset state");
        keys=3; wait_frames(25);
        if(dut.voice_count!=0 || total<400 || nonzero<40) $fatal(1,"insufficient coverage");
        $display("PASS tb_uart_instrument: four notes, steal, sources, tail, watchdog, R4/serial/reset"); $finish;
    end
    initial begin #100000000; $fatal(1,"instrument timeout"); end
endmodule

// 补充真实50MHz/434拍串口比例：同一组事件与音频断言再次执行。
module tb_uart_instrument_115200;
    tb_uart_instrument #(.BIT_CYCLES(434)) test();
    final $display("PASS tb_uart_instrument_115200");
endmodule
