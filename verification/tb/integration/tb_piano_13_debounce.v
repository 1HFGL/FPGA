`timescale 1ns/1ps
// Real 50MHz/48kHz and production 2ms debounce/ADSR. Single fresh external C5.
// Digital observation only; physical contact bounce and DAC analog delay are excluded.
module tb_piano_13_debounce;
    reg clk=0,rst_n=0;
    reg [12:0] keys=13'h1fff;
    wire tx,bck,ws,din,pa;
    integer cycle=0,start_cycle=0,pcm_cycle=0,dac_cycle=0,bits=0,v;
    reg [15:0] serial_word=0;
    piano_13key_top #(.ROM_FILE("rtl/rom/piano_1024.mem")) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(keys),
        .uart_rx(1'b1),.uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    always #10 clk=~clk;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(start_cycle!=0 && pcm_cycle==0 && dut.u_core.sample_valid && dut.u_core.sample_data!=0)
            pcm_cycle=cycle;
    end
    always @(posedge bck or negedge rst_n) begin
        if(!rst_n) begin bits=0; serial_word=0; end
        else if(dut.u_core.audio_ready) begin
            serial_word={serial_word[14:0],din}; bits=bits+1;
            if(bits==16) begin
                bits=0;
                if(start_cycle!=0 && dac_cycle==0 && ws==0 && serial_word!=0) dac_cycle=cycle;
            end
        end
    end
    initial begin
        repeat(8) @(negedge clk); rst_n=1;
        wait(dut.u_core.audio_ready); repeat(20) @(negedge clk);
        keys[12]=0; repeat(50000) @(negedge clk); // 1ms pulse must be rejected.
        keys[12]=1; repeat(50000) @(negedge clk);
        if(dut.u_core.voice_count!=0 || dut.u_core.u_allocator.note_on_count!=0) begin
            $display("FAIL: sub-2ms external pulse accepted"); $finish;
        end
        keys[12]=0; start_cycle=cycle;
        repeat(99990) @(negedge clk);
        if(dut.u_core.voice_count!=0) begin $display("FAIL: accepted before 2ms"); $finish; end
        wait(dac_cycle!=0); @(negedge clk);
        if(pcm_cycle-start_cycle<100000 || dac_cycle-start_cycle>=150000 || pa!==0 ||
           dut.u_core.voice_count!=1) begin $display("FAIL: debounce/digital audio bound"); $finish; end
        v=0;
        while(v<4 && !dut.u_core.voice_active[v]) v=v+1;
        if(v==4 || dut.u_core.voice_note_flat[v*7+:7]!=72 || dut.u_core.voice_source_flat[v*8+:8]!=12) begin
            $display("FAIL: external C5 identity"); $finish;
        end
        $display("PASS tb_piano_13_debounce: rejected1ms stable-input-to-PCM=%0dns left-DAC-word=%0dns", 
            20*(pcm_cycle-start_cycle),20*(dac_cycle-start_cycle));
        $finish;
    end
    initial begin #10000000; $display("FAIL: production-key watchdog"); $finish; end
endmodule
