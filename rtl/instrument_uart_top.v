// UART基础演奏独立板级顶层：KEY0复位、KEY1/2演奏、电脑共享四复音。
// 全部内部模块50MHz同域，audio_ready统一异步断言/同步释放复位。
module instrument_uart_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter [31:0] ATTACK_SAMPLES=96,DECAY_SAMPLES=24000,RELEASE_SAMPLES=5760,
    parameter [16:0] SUSTAIN_LEVEL=6554,
    parameter ROM_FILE="../../rtl/rom/sine_1024.mem",
    parameter integer FIXED_PIANO=0
)(
    input wire sys_clk,sys_rst_n,input wire [1:0] Key_in,
    input wire uart_rx,output wire uart_tx,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN
);
    wire audio_ready,sample_request,sample_underrun;
    wire [1:0] key_press,key_release;
    wire pv,pr,pt,cv,cr,ct,av,ar,at,cancel,cancel_ready,ac,acr,session_ready;
    wire [7:0] ps,asrc;
    wire [6:0] pn,pvel,cn,cvel,an,avel;
    wire [3:0] voice_gate,voice_active,voice_trigger,release_done;
    wire [27:0] voice_note_flat,voice_velocity_flat;
    wire [31:0] voice_source_flat,steal_count;
    wire [5:0] voice_count,max_voice_count;
    wire signed [15:0] sample_data;
    wire sample_valid,sounding,sample_clipped;
    wire output_frame_start;
    reg [1:0] pa_drain_frames;
    // A静音时，B还可能在发送上一非零样本。再留三个真实输出帧边界，
    // 让待发/活动帧与左右DAC的零字排完；不增加新音启动等待。
    // 每个系统拍都可重装，避免很短的触发落在两个帧边界之间而漏记。
    always @(posedge sys_clk) begin
        if(!audio_ready) pa_drain_frames<=2'd0;
        else if(sounding) pa_drain_frames<=2'd3;
        else if(output_frame_start && pa_drain_frames!=0)
            pa_drain_frames<=pa_drain_frames-2'd1;
    end
    touch_or_key_if #(.KEY_COUNT(2),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_keys(
        .clk(sys_clk),.rst_n(audio_ready),.raw_key(Key_in),.key_level(),
        .key_press(key_press),.key_release(key_release));
    event_encoder #(.KEY_COUNT(2),.SOURCE_WIDTH(8)) u_key_events(
        .clk(sys_clk),.rst_n(audio_ready),.key_press(key_press),.key_release(key_release),
        .key_velocity_flat({7'd100,7'd100}),.input_timbre(4'd0),
        .event_valid(pv),.event_ready(pr),.event_type(pt),.event_source_id(ps),
        .event_note(pn),.event_velocity(pvel),.event_timbre());
    uart_synth_protocol #(.CLKS_PER_BIT(UART_CLKS_PER_BIT),.WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .FIXED_PIANO(FIXED_PIANO)) u_uart(
        .clk(sys_clk),.rst_n(audio_ready),.rx(uart_rx),.tx(uart_tx),
        .event_valid(cv),.event_ready(cr),.event_type(ct),.event_note(cn),.event_velocity(cvel),
        .cancel_valid(cancel),.cancel_ready(cancel_ready),.session_ready(session_ready),
        .voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count));
    uart_event_arbiter u_arbiter(.clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
        .physical_valid(pv),.physical_ready(pr),.physical_type(pt),.physical_source(ps),
        .physical_note(pn),.physical_velocity(pvel),.pc_valid(cv),.pc_ready(cr),
        .pc_type(ct),.pc_note(cn),.pc_velocity(cvel),.cancel_valid(cancel),.cancel_ready(cancel_ready),
        .allocator_cancel(ac),.allocator_cancel_ready(acr),.event_valid(av),.event_ready(ar),
        .event_type(at),.event_source(asrc),.event_note(an),.event_velocity(avel));
    voice_allocator #(.VOICES(4),.IDX_WIDTH(2),.COUNT_WIDTH(6),.SOURCE_WIDTH(8),
        .MERGE_SAME_NOTE(0),.ENABLE_CANCEL(1)) u_allocator(
        .clk(sys_clk),.rst_n(audio_ready),.event_valid(av),.event_ready(ar),.event_type(at),
        .event_source_id(asrc),.event_note(an),.event_velocity(avel),.event_timbre(4'd0),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(8'd0),.expr_note(7'd0),
        .expr_pitch_bend(16'd0),.expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(release_done),.cancel_valid(ac),.cancel_ready(acr),.cancel_mask(8'h80),.cancel_value(8'h80),
        .voice_active(voice_active),.voice_gate(voice_gate),.voice_trigger(voice_trigger),
        .voice_source_id_flat(voice_source_flat),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),.voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),
        .voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count),
        .note_on_count(),.note_off_count(),.steal_pulse());
    // 保留R0请求 -> R3混音有效 -> R4缓存 -> 下一音频帧输出，不改变A/B合同。
    // 当前上位机只选固定预设；明确接零，避免合并新音色接口后出现悬空/Z。
    // 两个表使用同一路径；常量选色允许综合裁剪未使用的明亮分支。
    voice_bank_adsr #(.ROM_FILE(ROM_FILE),.BRIGHT_ROM_FILE(ROM_FILE),.ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),.RELEASE_SAMPLES(RELEASE_SAMPLES),.MIX_SHIFT(5)) u_bank(
        .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),.voice_gate(voice_gate),
        .voice_retrigger(voice_trigger),.voice_timbre(4'b0000),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .release_done(release_done),.sounding(sounding),.sample_data(sample_data),.sample_valid(sample_valid),
        .env_level_flat(),.voice_active(),.sample_clipped(sample_clipped));
    synth_top #(.AUDIO_CLK_HZ(50000000),.SAMPLE_RATE_HZ(48000)) u_b(
        .clk_in(sys_clk),.rst_n(sys_rst_n),.audio_enable(sounding || pa_drain_frames!=0),.sample_data(sample_data),.sample_valid(sample_valid),
        .audio_ready(audio_ready),.sample_request(sample_request),.sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK),.i2s_lrclk(HP_WS),.i2s_sdata(HP_DIN),.pa_en(PA_EN),
        .frame_start(output_frame_start));
endmodule
