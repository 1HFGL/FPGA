`timescale 1ns/1ps
module tb_input_fault_cleanup;
    reg clk=0,rst_n=0;
    reg [12:0] keys=13'h1fff;
    wire fault;
    wire [31:0] gate,down;
    wire [5:0] count;
    always #5 clk=~clk;
    interaction_top #(.DEBOUNCE_CYCLES(1),.MAX_EVENTS(4),.FIFO_PTR_WIDTH(2)) dut(
        .clk(clk),.rst_n(rst_n),.key_n(keys),.key_velocity_flat({13{7'd100}}),
        .octave_select(2'd1),.sustain_on(1'b1),.source_clear_valid(1'b0),.source_clear_ready(),
        .source_clear_id(5'd0),.source_clear_mask(5'd0),.timbre_key_n(1'b1),
        .pressure_valid(1'b0),.pressure_raw(12'd0),.knob_raw_flat(24'd0),.knob_valid(1'b1),
        .release_done(32'd0),.release_trigger_id_flat(512'd0),.expr_valid(1'b0),.expr_ready(),
        .expr_source_id(5'd0),.expr_note(7'd0),.expr_pitch_bend(16'd0),.expr_aftertouch(8'd0),
        .expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),.test_enable(1'b0),.test_clear(1'b0),.test_voices(6'd0),
        .key_level(),.key_press(),.key_release(),.timbre_id(),.timbre_press(),.knob_value_flat(),
        .knob_param_valid(),.param_ready(),.param_fault(),.pressure_velocity(),.pressure_active(),
        .event_valid(),.event_type(),.event_source_id(),.event_note(),.event_velocity(),.event_timbre(),
        .test_busy(),.test_done(),.voice_active(),.voice_gate(gate),.voice_key_down(down),
        .voice_trigger_id_flat(),.input_fault(fault),.voice_source_id_flat(),.voice_note_flat(),
        .voice_velocity_flat(),.voice_timbre_flat(),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),.voice_count(count),.max_voice_count(),
        .note_on_count(),.note_off_count(),.steal_count(),.steal_pulse()
    );
    initial begin
        repeat(5) @(negedge clk); rst_n=1; keys[0]=0;
        repeat(70) @(negedge clk);
        if(count!=1 || gate==0) $fatal(1,"Initial input did not sound");
        // Model a downstream stall: encoder must preserve events or raise a fault.
        force dut.normal_event_ready=0; force dut.event_valid=0;
        for(integer n=0;n<12;n=n+1) begin
            keys[0]=1; repeat(8) @(negedge clk);
            keys[0]=0; repeat(8) @(negedge clk);
        end
        release dut.normal_event_ready; release dut.event_valid;
        repeat(100) @(negedge clk);
        if(!fault || gate!=0 || down!=0 || count!=1) $fatal(1,"Overflow cleanup did not release held input under pedal");
        rst_n=0; repeat(4) @(negedge clk); rst_n=1;
        repeat(70) @(negedge clk);
        if(fault || count!=1) $fatal(1,"Input did not recover after reset");
        $display("PASS: tb_input_fault_cleanup overflow/pedal override/tail preserved/reset"); $finish;
    end
    initial begin #200000; $fatal(1,"Input cleanup watchdog"); end
endmodule
