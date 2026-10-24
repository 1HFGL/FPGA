`timescale 1ns/1ps
// Exhaust every three-key combination through the production debounce/event/allocator path.
module tb_three_key_chords;
    parameter integer VOICES=32;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,rst_n=0;
    reg [12:0] keys=13'h1fff;
    reg [1:0] board_keys=3;
    wire [12:0] held,piano,guitar;
    wire mode;
    reg [12:0] expected;
    reg [12:0] previous_mask=0;
    integer a,b,c,m,n,cases=0;
    always #10 clk=~clk;
    instrument_uart_top #(.DEBOUNCE_CYCLES(8),.EXTERNAL_PIANO_KEYS(1),.VOICES(VOICES),
        .ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),.ENABLE_OCTAVE_KEY(1),.ENABLE_BLE(1),
        .FIXED_PIANO(1),.USE_MODAL(1),.REQUEST_LEAD_HALF_EDGES(60),
        .ROM_FILE("rtl/rom/piano_1024.mem"),.MODE_ROM_FILE("rtl/rom/piano_v3_modes.mem"),
        .SHAPER_ROM_FILE("rtl/rom/rock_v2_shaper.mem"),
        .ENABLE_REVERB(1),.ENABLE_CHORUS(1),.ENABLE_DELAY(1)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(board_keys),.piano_key_n(keys),
        .uart_rx(1'b1),.ble_rx(1'b1),.ble_state(1'b0),
        .knob_value_flat({7'd64,7'd127}),.knob_valid(1'b1),.param_ready(1'b1),.param_fault(1'b0),
        .control_sustain(1'b0),.control_octave(2'd1),.control_brightness(7'd127),
        .monitor_key_down(held),.monitor_piano_keys(piano),.monitor_guitar_keys(guitar),
        .monitor_instrument_guitar(mode));
    task check;
        input [12:0] mask;
        begin
            // Three events fit 180 clocks. A legal 13-note burst needs up to
            // 13*(two 16-slot searches + commit/handshake), so allow 800 clocks.
            if(mask==13'h1fff || previous_mask==13'h1fff)repeat(13*(2*VOICES+10)+30)@(negedge clk);
            else repeat(3*(2*VOICES+10)+30)@(negedge clk);
            if(held!==mask || piano!==(mode?13'd0:mask) || guitar!==(mode?mask:13'd0))begin
                $display("FAIL chord mask expected=%h held=%h piano=%h guitar=%h keys=%h",mask,held,piano,guitar,keys);$finish;
            end
            if(dut.input_fault)begin $display("FAIL chord input overflow");$finish;end
            previous_mask=mask;
        end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;check(0);
        for(m=0;m<2;m=m+1)begin
            for(a=0;a<11;a=a+1)for(b=a+1;b<12;b=b+1)for(c=b+1;c<13;c=c+1)begin
                expected=(13'd1<<a)|(13'd1<<b)|(13'd1<<c);
                keys=~expected;check(expected);
                // Brief common-line glitch shorter than the debounce threshold.
                keys=0;repeat(3)@(negedge clk);keys=~expected;check(expected);
                // Release one key while the other two remain held.
                keys=keys|(13'd1<<b);check(expected & ~(13'd1<<b));
                keys=13'h1fff;check(0);cases=cases+1;
            end
            if(m==0)begin board_keys[1]=0;repeat(30)@(negedge clk);board_keys[1]=1;check(0);end
        end
        keys=0;check(13'h1fff);keys=13'h1fff;check(0);
        // Overlapping changes, including old notes with release tails and voice stealing.
        for(n=0;n<100;n=n+1)begin
            expected=(13'd1<<(n%13))|(13'd1<<((n+4)%13))|(13'd1<<((n+7)%13));
            keys=~expected;check(expected);
        end
        keys=13'h1fff;check(0);
        rst_n=0;repeat(5)@(negedge clk);
        if(held!==0)begin $display("FAIL chord reset");$finish;end
        if(cases!=572)begin $display("FAIL chord coverage");$finish;end
        $display("PASS tb_three_key_chords: 572 chords/both timbres, short common glitches, partial release, 13-key chord, 100 overlaps, reset");$finish;
    end
    initial begin #30000000;$display("FAIL chord timeout");$finish;end
endmodule
