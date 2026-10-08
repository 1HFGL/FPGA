`timescale 1ns/1ps
// 钢琴感预设的数值合同：真实段长、逐点波表/包络/增益/混音对照。
// 采样使能每8个系统周期一次以加速；计数仍按48kHz换算，不模拟模拟电路。
module tb_piano_tone;
    reg clk=0,rst=1,tick=0;
    reg [3:0] gate=0,retrigger=0;
    wire [3:0] released,active;
    wire [67:0] levels;
    wire signed [15:0] sample;
    wire valid,clipped,sounding;
    reg signed [15:0] wave[0:1023];
    reg [31:0] phase[0:3];
    reg [31:0] increments[0:3];
    reg [27:0] notes={7'd72,7'd67,7'd64,7'd60};
    reg [27:0] velocities={7'd127,7'd100,7'd64,7'd0};
    integer n,v,level,expected,total,scaled,peak=0,nonzero=0,checks=0;
    // 同时实例化真实板级wrapper，防止测试参数和实际工程脱节。
    instrument_uart_piano_top #(.ROM_FILE("rtl/rom/piano_1024.mem")) board(
        .sys_clk(clk),.sys_rst_n(!rst),.Key_in(2'b11),.uart_rx(1'b1),
        .uart_tx(),.HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN());
    voice_bank_adsr #(
`ifdef PIANO_NEGATIVE_CONTROL
        .ROM_FILE("rtl/rom/sine_1024.mem"), // 故意用错波表，逐点对照必须拒绝。
`else
        .ROM_FILE("rtl/rom/piano_1024.mem"),
`endif
        .ATTACK_SAMPLES(96),.DECAY_SAMPLES(57600),.SUSTAIN_LEVEL(0),
        .RELEASE_SAMPLES(8640),.MIX_SHIFT(5)) dut(
        .clk(clk),.rst_n(!rst),.sample_request(tick),.voice_gate(gate),
        .voice_retrigger(retrigger),.voice_note_flat(notes),.voice_velocity_flat(velocities),
        .release_done(released),.voice_active(active),.env_level_flat(levels),
        .sounding(sounding),.sample_data(sample),.sample_valid(valid),.sample_clipped(clipped));
    always #10 clk=~clk;
    function integer gain(input integer x,input integer g);
        reg signed [63:0] product;
        begin product=x; product=product*g; gain=product>>>16; end
    endfunction
    task take_sample(input integer expected_level);
        integer j,velocity_gain;
        begin
            total=0;
            for(j=0;j<4;j=j+1) begin
                velocity_gain=(velocities[j*7 +: 7]==127)?65536:(velocities[j*7 +: 7]<<9);
                scaled=gain(gain($signed(wave[phase[j][31:22]]),expected_level),velocity_gain);
                total=total+scaled;
                phase[j]=phase[j]+increments[j];
            end
            expected=total>>>5;
            @(negedge clk); tick=1;
            @(posedge clk); #1;
            for(j=0;j<4;j=j+1)
                if(levels[j*17 +: 17]!==expected_level) $fatal(1,"env check %0d: expected=%0d got=%0d",checks,expected_level,levels[j*17 +: 17]);
            if(valid!==0) $fatal(1,"early valid R0");
            @(negedge clk); tick=0; retrigger=0;
            repeat(2) begin @(posedge clk); #1; if(valid!==0) $fatal(1,"early valid R1/R2"); end
            @(posedge clk); #1;
            if(valid!==1 || $signed(sample)!=expected || clipped!==0)
                $fatal(1,"R3 check %0d: expected=%0d got=%0d valid=%b",checks,expected,$signed(sample),valid);
            if(sample!=0) nonzero=nonzero+1;
            if(sample>peak) peak=sample;
            checks=checks+1;
            repeat(4) @(negedge clk);
        end
    endtask
    initial begin
        $readmemh("rtl/rom/piano_1024.mem",wave);
        if(board.u_core.ATTACK_SAMPLES!=96 || board.u_core.DECAY_SAMPLES!=57600 ||
           board.u_core.SUSTAIN_LEVEL!=0 || board.u_core.RELEASE_SAMPLES!=8640 || board.u_core.FIXED_PIANO!=1)
            $fatal(1,"board preset differs from tested contract");
        // MIDI查表由既有参考验证；这里独立核对本次四音的相位步长。
        increments[0]=23409859; increments[1]=29494575;
        increments[2]=35075158; increments[3]=46819719;
        for(v=0;v<4;v=v+1) phase[v]=0;
        repeat(5) @(negedge clk); rst=0; gate=15;
        for(n=1;n<=96;n=n+1) take_sample((65536*n)/96);
        // 65536*57600超出32位有符号数，参考模型必须先把乘法扩至64位。
        for(n=1;n<=57600;n=n+1) take_sample(65536-(64'sd65536*n)/57600);
        repeat(4) take_sample(0);
        if(sample!==0 || gate!=15) $fatal(1,"held note must decay to zero");
        // 重触发已衰减完的保持音，随后提前松键；释放从当前幅度开始。
        retrigger=15;
        for(n=1;n<=96;n=n+1) take_sample((65536*n)/96);
        gate=0;
        for(n=1;n<=8640;n=n+1) take_sample(65536-(65536*n)/8640);
        repeat(5) take_sample(0);
        if(released!==15 || sounding!==0 || active!==0) $fatal(1,"release did not recycle");
        gate=15;
        for(n=1;n<=12;n=n+1) take_sample((65536*n)/96);
        @(negedge clk); rst=1;
        repeat(5) @(negedge clk);
        if(sample!==0 || valid!==0 || sounding!==0) $fatal(1,"midnote reset");
        if(nonzero<50000 || peak<300) $fatal(1,"silent waveform/checker");
        $display("PASS tb_piano_tone: %0d sample checks, 96/57600/8640, sustain zero, retrigger/reset, peak=%0d",checks,peak);
        $finish;
    end
    initial begin #20000000; $fatal(1,"piano timeout"); end
endmodule
