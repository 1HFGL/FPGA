`timescale 1ns/1ps
// Fast envelope/debounce settings exercise input ownership and real A/B output.
// The FPGA project retains 2ms debounce and the production piano envelope.
module tb_piano_13_keys;
    reg clk=0,rst_n=0;
    reg [12:0] keys=13'h1fff;
    reg [1:0] board_keys=2'b11;
    wire tx,bck,ws,din,pa;
    integer key,v,timeout,heard=0;
    piano_13key_top #(.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16),
        .ROM_FILE("rtl/rom/piano_1024.mem"),.ATTACK_SAMPLES(4),.DECAY_SAMPLES(128),.RELEASE_SAMPLES(8)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(board_keys),.piano_key_n(keys),
        .uart_rx(1'b1),.uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    always #10 clk=~clk;
    always @(posedge clk)
        if(dut.u_core.audio_ready && dut.u_core.sample_valid && dut.u_core.sample_data!=0) heard=heard+1;
    task reset_board;
        begin
            @(negedge clk); rst_n=0; keys=13'h1fff; board_keys=2'b11; heard=0;
            repeat(8) @(negedge clk); rst_n=1;
            wait(dut.u_core.audio_ready); repeat(20) @(negedge clk);
            if(dut.u_core.voice_count!=0) begin $display("FAIL: startup voices"); $finish; end
        end
    endtask
    task wait_count;
        input integer expected;
        input integer limit;
        begin
            timeout=0;
            while(dut.u_core.voice_count!=expected && timeout<limit) begin
                @(negedge clk); timeout=timeout+1;
            end
            if(dut.u_core.voice_count!=expected) begin
                $display("FAIL: expected count=%0d actual=%0d",expected,dut.u_core.voice_count); $finish;
            end
        end
    endtask
    function integer find_voice;
        input integer origin;
        input integer note;
        integer index;
        begin
            find_voice=-1;
            for(index=0;index<4;index=index+1)
                if(dut.u_core.voice_active[index] && dut.u_core.voice_source_flat[index*8+:8]==origin &&
                   dut.u_core.voice_note_flat[index*7+:7]==note) find_voice=index;
        end
    endfunction
    initial begin
        for(key=0;key<13;key=key+1) begin
            reset_board;
            keys[key]=0; wait_count(1,2000);
            v=find_voice(key,60+key);
            if(v<0 || !dut.u_core.voice_gate[v]) begin $display("FAIL: key %0d note/source",key); $finish; end
            repeat(6000) @(negedge clk);
            if(heard==0 || pa!==1'b0) begin $display("FAIL: key %0d silent",key); $finish; end
            keys[key]=1; wait_count(0,30000);
        end
        reset_board;
        keys=13'h1fff ^ 13'h1091; // C4/E4/G4/C5, four independent voices.
        wait_count(4,2000);
        if(find_voice(0,60)<0 || find_voice(4,64)<0 || find_voice(7,67)<0 || find_voice(12,72)<0) begin
            $display("FAIL: four-key chord"); $finish;
        end
        keys[1]=0;
        wait(dut.u_core.steal_count==1); repeat(30) @(negedge clk);
        if(find_voice(1,61)<0 || find_voice(0,60)>=0) begin $display("FAIL: fifth-key steal"); $finish; end
        keys[0]=1; repeat(500) @(negedge clk);
        if(dut.u_core.voice_count!=4 || dut.u_core.voice_gate!=4'hf) begin
            $display("FAIL: stolen key release closed another key"); $finish;
        end
        keys=13'h1fff; wait_count(0,30000);
        reset_board;
        board_keys[1]=0; wait_count(1,2000);
        if(find_voice(4,64)<0) begin $display("FAIL: board E4 alias"); $finish; end
        keys[4]=0; repeat(30) @(negedge clk);
        board_keys[1]=1; repeat(500) @(negedge clk);
        if(dut.u_core.voice_count!=1 || dut.u_core.voice_gate==0) begin
            $display("FAIL: alias release ignored external hold"); $finish;
        end
        keys[4]=1; wait_count(0,30000);
        reset_board; keys=0;
        wait(dut.u_core.u_allocator.note_on_count==13); repeat(30) @(negedge clk);
        if(dut.u_core.voice_count!=4 || dut.u_core.steal_count!=9) begin
            $display("FAIL: thirteen-key burst accounting"); $finish;
        end
        for(v=0;v<4;v=v+1) begin
            if(dut.u_core.voice_source_flat[v*8+:8]<9 ||
               dut.u_core.voice_note_flat[v*7+:7]!=60+dut.u_core.voice_source_flat[v*8+:8]) begin
                $display("FAIL: burst final owner"); $finish;
            end
        end
        keys=13'h1fff; wait_count(0,30000);
        keys=0; wait_count(4,2000); @(negedge clk); rst_n=0;
        repeat(5) @(negedge clk);
        if(pa!==1'b1 || dut.u_core.voice_gate!=0 || dut.u_core.voice_count!=0) begin
            $display("FAIL: reset held chord"); $finish;
        end
        $display("PASS tb_piano_13_keys: 13 chromatic notes/audio/chord/steal/release/aliases/burst/reset");
        $finish;
    end
    initial begin #20000000; $display("FAIL: thirteen-key watchdog"); $finish; end
endmodule
