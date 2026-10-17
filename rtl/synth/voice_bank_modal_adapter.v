// A模态合成器与C代次接口之间的薄适配层；全部信号同步于50MHz。
// 请求只在!busy时接受，R(56*VOICES+27)给样本，下一拍由B缓存。
// C的触发代次只在该批结果返回后确认。忙时屏蔽上一批release_done，
// 防止新音尚未计算就因上一批的“空闲”被回收；不改变A的音色公式。
module voice_bank_modal_adapter #(
    parameter integer VOICES=16,
    parameter MODE_ROM_FILE="rtl/rom/piano_v3_modes.mem",
    parameter SHAPER_ROM_FILE="rtl/rom/rock_v2_shaper.mem",
    parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem"
)(
    input wire clk,rst_n,sample_request,
    input wire [16:0] master_gain,bend_ratio,
    input wire [VOICES-1:0] voice_gate,voice_guitar,
    input wire [VOICES*7-1:0] voice_note_flat,voice_velocity_flat,
    input wire [VOICES*16-1:0] voice_trigger_id_flat,
    output reg [VOICES*16-1:0] release_trigger_id_flat,
    output wire [VOICES-1:0] release_done,
    output wire sounding,busy,overrun,
    output wire signed [15:0] sample_data,
    output wire sample_valid,sample_clipped
);
    reg [VOICES*16-1:0] request_ids;
    wire accept=sample_request && !busy;
    wire [VOICES-1:0] retrigger,raw_release;
    genvar v;
    generate for(v=0;v<VOICES;v=v+1)begin:g_generation
        // 持续代次差仅在接受请求时转成一次触发，避免重复填入A的pending。
        assign retrigger[v]=accept &&
            (voice_trigger_id_flat[v*16+:16]!=release_trigger_id_flat[v*16+:16]);
        assign release_done[v]=!rst_n || (!busy && !sample_valid && raw_release[v]);
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin request_ids<=0;release_trigger_id_flat<=0;end
        else begin
            if(accept)request_ids<=voice_trigger_id_flat;
            if(sample_valid)release_trigger_id_flat<=request_ids;
        end
    end
    // 外部0钢琴/1吉他；A内部0吉他/1钢琴。增益和弯音在A内各应用一次。
    voice_bank_music_pipe #(.VOICES(VOICES),.MIX_SHIFT(3),
        .MODE_ROM_FILE(MODE_ROM_FILE),.SHAPER_ROM_FILE(SHAPER_ROM_FILE),
        .SINE_ROM_FILE(SINE_ROM_FILE)) u_modal(
        .clk(clk),.rst_n(rst_n),.sample_request(sample_request),
        .global_gain_q16(master_gain),.pitch_ratio_q16(bend_ratio),
        .voice_gate(voice_gate),.voice_retrigger(retrigger),.voice_instrument(~voice_guitar),
        .voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .release_done(raw_release),.voice_active(),.instrument_active(),.env_level_flat(),
        .sounding(sounding),.busy(busy),.sample_data(sample_data),
        .sample_valid(sample_valid),.sample_clipped(sample_clipped),.overrun(overrun));
endmodule
