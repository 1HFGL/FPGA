`timescale 1ns/1ps
module tb_voice_adsr;
    // Accelerated functional simulation; four clocks per sample is NOT a
    // proposed board clock. Envelope rates are defined per audio sample.
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, sample_tick=0, gate=0, retrigger=0;
    reg [31:0] phase_inc=32'd39370534; // 440 Hz at 48 kHz
    wire signed [15:0] sample;
    wire sample_valid, voice_active;
    wire [16:0] env_level;
    voice_adsr dut (.clk(clk), .rst(rst), .sample_tick(sample_tick),
        .gate(gate), .retrigger(retrigger), .phase_inc(phase_inc),
        .sample(sample), .sample_valid(sample_valid),
        .env_level(env_level), .voice_active(voice_active));

    integer ref_level=0, ref_state=0, pending_sample=0, expected_sample=0;
    integer clocks_checked=0, samples_checked=0, i, trace_fd=0;
    reg ref_gate=0, pending_trigger=0, pending_valid=0, expected_valid=0;
    reg [31:0] ref_phase=0, random_state=32'h51a7c0de;
    reg [2047:0] trace_path;
    real sine_value;
    integer sine_integer;

    // Independent integer/sine reference, including every pipeline idle cycle.
    always @(posedge clk) begin
        if (rst) begin
            ref_level=0; ref_state=0; ref_gate=0; pending_trigger=0;
            ref_phase=0; pending_sample=0; pending_valid=0;
            expected_sample=0; expected_valid=0;
        end else begin
            expected_valid=pending_valid;
            if (pending_valid) expected_sample=pending_sample;
            pending_valid=sample_tick;
            if (sample_tick) begin
                if (!gate) begin
                    ref_level=(ref_level>3)?ref_level-3:0;
                    ref_state=(ref_level==0)?0:4;
                end else if (retrigger || pending_trigger || !ref_gate ||
                             ref_state==0 || ref_state==1) begin
                    ref_level=ref_level+137;
                    if (ref_level>=65536) begin ref_level=65536; ref_state=2; end
                    else ref_state=1;
                end else if (ref_state==2) begin
                    ref_level=ref_level-7;
                    if (ref_level<=32768) begin ref_level=32768; ref_state=3; end
                end
                ref_gate=gate;
                pending_trigger=0;
                sine_value=32767.0*$sin(6.283185307179586*(ref_phase>>22)/1024.0);
                sine_integer=(sine_value>=0)?$rtoi(sine_value+0.5):$rtoi(sine_value-0.5);
                pending_sample=$rtoi($floor(sine_integer*1.0*ref_level/65536.0));
                ref_phase=ref_phase+phase_inc;
            end else if (retrigger) pending_trigger=1;
        end
        #1;
        if ($signed(sample) !== expected_sample || sample_valid !== expected_valid ||
            env_level !== ref_level || dut.env_state !== ref_state ||
            voice_active !== ((ref_state!=0) || (expected_valid && expected_sample!=0)))
            $fatal(1,"Voice mismatch at clock %0d: sample %0d/%0d valid %b/%b env %0d/%0d",
                   clocks_checked,$signed(sample),expected_sample,sample_valid,expected_valid,
                   env_level,ref_level);
        if (trace_fd!=0)
            $fwrite(trace_fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
                    rst,sample_tick,gate,retrigger,phase_inc,$signed(sample),
                    sample_valid,env_level,voice_active,dut.env_state);
        clocks_checked=clocks_checked+1;
        if (sample_valid) samples_checked=samples_checked+1;
    end

    task cycle;
        input r,t,g,trig;
        input [31:0] inc;
        begin
            @(negedge clk);
            rst=r; sample_tick=t; gate=g; retrigger=trig; phase_inc=inc;
            @(posedge clk); #2;
        end
    endtask
    task audio_tick;
        input g;
        begin
            cycle(0,1,g,0,32'd39370534);
            repeat(3) cycle(0,0,g,0,32'd39370534);
        end
    endtask

    initial begin
        if ($value$plusargs("ADSR_TRACE=%s",trace_path)) begin
            trace_fd=$fopen(trace_path,"w");
            if (trace_fd==0) $fatal(1,"Cannot open ADSR trace");
        end
        cycle(1,1,1,1,32'hffffffff);
        repeat(10) audio_tick(0);
        // Full attack (479 ticks), decay (4682), sustain, release (10923).
        repeat(6000) audio_tick(1);
        repeat(11000) audio_tick(0);
        if (voice_active!==0 || sample!==16'sd0) $fatal(1,"Release did not silence voice");
        repeat(200) audio_tick(1);
        repeat(100) audio_tick(0); // early release then reattack
        repeat(300) audio_tick(1);
        cycle(0,0,1,1,32'd78741067); // pending one-clock retrigger
        cycle(0,0,1,0,32'd78741067);
        repeat(300) cycle(0,1,1,0,32'd78741067); // back-to-back requests
        cycle(1,1,1,1,32'd0); // reset flushes pending output
        repeat(4) cycle(0,1,1,0,32'd0); // zero frequency, DC waveform at phase zero
        repeat(4) cycle(0,1,1,0,32'hffffffff); // wraparound
        // Deterministic varied enables, gate edges, retriggers and resets.
        for(i=0;i<10000;i=i+1) begin
            random_state=random_state*32'd1664525+32'd1013904223;
            cycle((i%997)==0,random_state[31],random_state[27],
                  (random_state[23:20]==0),random_state);
        end
        repeat(22000) cycle(0,1,0,0,32'd39370534);
        repeat(4) cycle(0,0,0,0,32'd39370534);
        if (voice_active!==0 || sample!==16'sd0) $fatal(1,"Final release not silent");
        if (trace_fd!=0) $fclose(trace_fd);
        $display("PASS: voice_adsr sample and pipeline checks (%0d clocks, %0d samples).",
                 clocks_checked,samples_checked);
        $stop;
    end
    initial begin #2000000; $fatal(1,"Voice ADSR timeout"); end
endmodule
