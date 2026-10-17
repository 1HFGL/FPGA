`timescale 1ns/1ps

// 0=吉他拨弦感，1=弦乐持续感。属于合成预设，不是实录采样/物理乐器复刻。
// R0读表/推进包络，R1亮度乘法并快照包络，R2包络乘法输出。
module voice_instrument #(
    parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem",
    parameter GUITAR_ROM_FILE="rtl/rom/guitar_1024.mem",
    parameter STRINGS_ROM_FILE="rtl/rom/strings_1024.mem",
    parameter [31:0] G_ATTACK=32'd64, G_DECAY=32'd32768, G_RELEASE=32'd4096,
    parameter [16:0] G_SUSTAIN=17'd0,
    parameter [31:0] S_ATTACK=32'd1024, S_DECAY=32'd8192, S_RELEASE=32'd8192,
    parameter [16:0] S_SUSTAIN=17'd49152,
    parameter [31:0] G_TONE_SAMPLES=32'd8192, S_TONE_SAMPLES=32'd2048,
    // 可将第二预设接为固定钢琴波表；默认0保持原吉他/弦乐行为和接口。
    parameter integer S_FIXED_TONE=0
) (
    input wire clk, rst, sample_tick,
    input wire [31:0] phase_inc,
    input wire gate, retrigger, instrument,
    output wire signed [15:0] sample,
    output wire sample_valid,
    output wire [16:0] env_level, tone_level,
    output wire voice_active,
    output reg active_instrument
);
    wire [31:0] phase;
    wire [9:0] addr;
    wire env_active;
    wire [2:0] env_state;
    reg gate_sampled, trigger_pending, pending_instrument;
    wire start_note=sample_tick && gate &&
        (retrigger || trigger_pending || !gate_sampled || !env_active);
    wire event_instrument=retrigger?instrument:(trigger_pending?pending_instrument:instrument);
    wire requested_instrument=start_note?event_instrument:active_instrument;

    localparam [31:0] G_TN=(G_TONE_SAMPLES==0)?1:G_TONE_SAMPLES;
    localparam [31:0] S_TN=(S_TONE_SAMPLES==0)?1:S_TONE_SAMPLES;
    localparam [31:0] MAX_TN=(G_TN>S_TN)?G_TN:S_TN;
    function integer count_bits;
        input [31:0] value;
        reg [31:0] shifted;
        begin shifted=value; count_bits=0;
            while(shifted!=0) begin count_bits=count_bits+1; shifted=shifted>>1; end
            if(count_bits==0) count_bits=1;
        end
    endfunction
    localparam integer TONE_W=count_bits(MAX_TN);
    reg [TONE_W-1:0] tone_age;
    wire [31:0] tone_duration=active_instrument?S_TN:G_TN;
    // 分别使用常量乘除，默认点数是2的幂；充分扩位兼容参数边界。
    // 61440=2^16-2^12，24576=2^14+2^13。先扩至64位再移位，
    // 保持原乘法的全部高位；常量代数展开避免每声部为亮度系数占用DSP。
    wire [63:0] tone_age_wide={{(64-TONE_W){1'b0}},tone_age};
    wire [63:0] guitar_product=(tone_age_wide<<16)-(tone_age_wide<<12);
    wire [63:0] strings_product=(tone_age_wide<<14)+(tone_age_wide<<13);
    wire [63:0] guitar_drop=guitar_product/G_TN, strings_rise=strings_product/S_TN;
    assign tone_level=active_instrument?(S_FIXED_TONE?17'd65536:(17'd8192+strings_rise[16:0])):
                                       (17'd65536-guitar_drop[16:0]);
    always @(posedge clk) begin
        if(rst) begin
            gate_sampled<=0; trigger_pending<=0; pending_instrument<=0;
            active_instrument<=0; tone_age<=0;
        end else if(sample_tick) begin
            gate_sampled<=gate; trigger_pending<=0;
            if(start_note) begin active_instrument<=event_instrument; tone_age<=0; end
            else if(tone_age<tone_duration) tone_age<=tone_age+1'b1;
        end else if(retrigger) begin
            trigger_pending<=1; pending_instrument<=instrument;
        end
    end
    // 松键请求丢弃pending但保留旧预设；S=0仍是SUSTAIN，不能不断自动重起音。
    instrument_env #(.G_ATTACK(G_ATTACK), .G_DECAY(G_DECAY), .G_SUSTAIN(G_SUSTAIN), .G_RELEASE(G_RELEASE),
        .S_ATTACK(S_ATTACK), .S_DECAY(S_DECAY), .S_SUSTAIN(S_SUSTAIN), .S_RELEASE(S_RELEASE)) u_env (
        .clk(clk),.rst(rst),.sample_tick(sample_tick),.gate(gate),
        .note_on(start_note),.instrument(requested_instrument),
        .env_level(env_level),.active(env_active),.state(env_state));
    phase_acc u_phase (
        .clk(clk),.rst(rst),.sample_tick(sample_tick),.phase_inc(phase_inc),
        .phase(phase),.wave_addr(addr));
    wire signed [15:0] base_sample, full_sample;
    wire wave_valid;
    instrument_wave #(.SINE_ROM_FILE(SINE_ROM_FILE),.GUITAR_ROM_FILE(GUITAR_ROM_FILE),
                      .STRINGS_ROM_FILE(STRINGS_ROM_FILE)) u_wave (
        .clk(clk),.rst(rst),.read_en(sample_tick),.addr(addr),
        .instrument(requested_instrument),.harmonics_enable(phase_inc<32'h10000000),
        .base_sample(base_sample),.full_sample(full_sample),.sample_valid(wave_valid));

    // 最高八次谐波：8*f < Fs/2。48kHz时>=3kHz只保留同幅度基波。
    // shape=base+(full-base)*tone，tone在[0,1]，是两端点的凸组合，不会溢出。
    wire signed [16:0] difference=$signed({full_sample[15],full_sample})-
                                 $signed({base_sample[15],base_sample});
    wire signed [17:0] positive_tone=$signed({1'b0,tone_level});
    reg signed [34:0] tone_product;
    reg signed [15:0] base_d1;
    reg [16:0] env_d1;
    reg shape_valid;
    wire signed [34:0] shaped=$signed({{19{base_d1[15]}},base_d1})+(tone_product>>>16);
    always @(posedge clk) begin
        if(rst) begin tone_product<=0; base_d1<=0; env_d1<=0; shape_valid<=0; end
        else begin
            shape_valid<=wave_valid;
            if(wave_valid) begin
                tone_product<=difference*positive_tone;
                base_d1<=base_sample; env_d1<=env_level;
            end
        end
    end
    sample_gain u_amplitude (
        .clk(clk),.rst(rst),.in_valid(shape_valid),.sample_in(shaped[15:0]),
        .gain(env_d1),.sample_out(sample),.out_valid(sample_valid));
    // 增加的R1级必须计入待输出尾音，不能在包络归零那一拍提前回收。
    assign voice_active=env_active | (shape_valid && env_d1!=0) |
                                    (sample_valid && sample!=16'sd0);
endmodule
