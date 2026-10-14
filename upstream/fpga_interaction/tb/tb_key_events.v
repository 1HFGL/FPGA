`timescale 1ns/1ps
module tb_key_events;
    reg clk=0,rst_n=0,ready=0;
    reg [12:0] press=0,release_key=0;
    reg [1:0] octave=1;
    reg [90:0] velocities={13{7'd100}};
    reg [3:0] timbre=1;
    wire valid,on,fault;
    wire [4:0] source;
    wire [6:0] note,velocity;
    wire [3:0] event_timbre;
    reg [12:0] on_seen=0,off_seen=0;
    integer mode=0,received=0,k;
    always #5 clk=~clk;
    event_encoder #(.MAX_EVENTS(4),.PTR_WIDTH(2)) dut(
        .clk(clk),.rst_n(rst_n),.key_press(press),.key_release(release_key),.key_velocity_flat(velocities),
        .input_timbre(timbre),.octave_select(octave),.input_overflow(fault),.event_valid(valid),
        .event_type(on),.event_source_id(source),.event_note(note),.event_velocity(velocity),
        .event_timbre(event_timbre),.event_ready(ready)
    );
    always @(posedge clk) if(rst_n && valid && ready) begin
        if(mode==0) begin
            if(source>12 || note!=60+source) begin $display("FAIL: Chord/octave snapshot wrong: src=%d note=%d",source,note); $finish; end
            if(on) begin
                if(on_seen[source] || velocity!=100 || event_timbre!=1) begin $display("FAIL: Duplicate or unsnapshotted press"); $finish; end
                on_seen[source]=1;
            end else begin
                if(!on_seen[source] || off_seen[source]) begin $display("FAIL: Per-key ordering wrong"); $finish; end
                off_seen[source]=1;
            end
        end else if(mode==1) begin
            if(note!=72 || on!=(received==0)) begin $display("FAIL: Octave change closed wrong note"); $finish; end
        end
        received=received+1;
    end
    task pulse;
        input is_on;
        begin
            @(negedge clk); if(is_on) press=1; else release_key=1;
            @(negedge clk); press=0; release_key=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); press=13'h1fff;
        @(negedge clk); press=0; octave=2; velocities={13{7'd40}}; timbre=2;
        @(negedge clk); release_key=13'h1fff;
        @(negedge clk); release_key=0;
        repeat(20) @(negedge clk); ready=1;
        wait(received==26); @(negedge clk);
        if(fault || on_seen!=13'h1fff || off_seen!=13'h1fff) begin $display("FAIL: Thirteen-key burst lost events"); $finish; end
        mode=1; received=0; pulse(1); octave=0; pulse(0);
        wait(received==2); @(negedge clk);
        if(fault) begin $display("FAIL: Unexpected FIFO fault"); $finish; end
        rst_n=0; ready=0; mode=2; repeat(4) @(negedge clk); rst_n=1;
        for(k=0;k<12;k=k+1) begin pulse(1); pulse(0); end
        repeat(8) @(negedge clk);
        if(!fault || valid) begin $display("FAIL: Overflow failed to stop unsafe delivery"); $finish; end
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
        if(fault) begin $display("FAIL: Reset did not clear input fault"); $finish; end
        $display("PASS: tb_key_events 13-key burst/backpressure/order/octave/overflow/reset"); $finish;
    end
    initial begin #200000; begin $display("FAIL: Key-event watchdog"); $finish; end end
endmodule
