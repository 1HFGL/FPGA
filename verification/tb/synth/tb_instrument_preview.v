`timescale 1ns/1ps
// 试听来自真实四声部RTL；只开第0声部，软件逐样本核对后才输出WAV。
// 快速仿真每6个clk请求一次；音频播放仍按48kHz解释这些样本。
module tb_instrument_preview;
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gate=0, instruments=0;
    reg [27:0] notes=0;
    wire [3:0] done_voice, active, selected;
    wire [67:0] env, tone;
    wire sounding, valid, clipped;
    wire signed [15:0] sample;
    reg [8191:0] path, kind;
    integer fd=0, preset=0, written=0, n, mode, count, note;
    always #10 clk=~clk;
    voice_bank_instruments dut (
        .clk(clk),.rst_n(rst_n),.sample_request(request),
        .voice_gate(gate),.voice_retrigger(4'b0),.voice_instrument(instruments),
        .voice_note_flat(notes),.voice_velocity_flat({4{7'd127}}),
        .release_done(done_voice),.voice_active(active),.env_level_flat(env),
        .instrument_active(selected),.tone_level_flat(tone),
        .sounding(sounding),.sample_data(sample),.sample_valid(valid),.sample_clipped(clipped));
    always @(posedge clk) begin
        #1;
        if(valid) begin
            if(!fd || clipped) begin $display("FAIL: preview file missing or clipping"); $finish; end
            $fdisplay(fd,"%s,%0d,%0d,%0d,%0d,%0d",kind,preset,written,note,gate[0],$signed(sample));
            written=written+1;
        end
    end
    initial begin
        if(!$value$plusargs("INSTRUMENT_PREVIEW=%s",path)) begin $display("FAIL: INSTRUMENT_PREVIEW path required"); $finish; end
        fd=$fopen(path,"w");
        if(!fd) begin $display("FAIL: cannot open preview CSV"); $finish; end
        $fdisplay(fd,"kind,instrument,index,note,gate,sample");
        for(mode=0;mode<2;mode=mode+1) for(preset=0;preset<2;preset=preset+1) begin
            kind=(mode==0)?"probe":"melody";
            count=(mode==0)?96000:120000;
            @(negedge clk); rst_n=0; request=0; gate=0; instruments=preset;
            repeat(3) @(negedge clk);
            rst_n=1; written=0;
            for(n=0;n<count;n=n+1) begin
                @(negedge clk);
                if(mode==0) begin note=69; gate=(n<72000)?1:0; end
                else begin
                    case(n/24000)
                        0:note=60; 1:note=62; 2:note=64; 3:note=67; default:note=72;
                    endcase
                    gate=(n%24000<14400)?1:0;
                end
                notes={21'd0,note[6:0]}; request=1;
                @(negedge clk); request=0;
                repeat(4) @(negedge clk);
            end
            repeat(5) @(negedge clk);
            if(written!=count || sample!==0 || active!==0 || done_voice!==15)
                begin $display("FAIL: preview incomplete: kind=%s instrument=%0d count=%0d",kind,preset,written); $finish; end
        end
        $fclose(fd); fd=0;
        $display("PASS: instrument RTL preview, 432000 samples, four silent tails.");
        $finish;
    end
endmodule
