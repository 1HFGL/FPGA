// 共用演奏系统：正式顶层启用13键、16声部及旋钮，默认4路兼容已有验证。
// 全部内部模块50MHz同域，audio_ready统一异步断言/同步释放复位。
module instrument_uart_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter [31:0] ATTACK_SAMPLES=96,DECAY_SAMPLES=24000,RELEASE_SAMPLES=5760,
    parameter [16:0] SUSTAIN_LEVEL=6554,
    parameter ROM_FILE="../../rtl/rom/sine_1024.mem",
    parameter integer FIXED_PIANO=0,
    parameter integer REQUEST_LEAD_HALF_EDGES=0,
    parameter integer EXTERNAL_PIANO_KEYS=0,
    parameter integer VOICES=4,
    parameter integer ENABLE_CONTROLS=0
)(
    input wire sys_clk,sys_rst_n,input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx,output wire uart_tx,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    input wire [13:0] knob_value_flat,
    input wire knob_valid,param_ready,param_fault,
    input wire control_sustain,
    input wire [1:0] control_octave,
    output wire control_ready
);
    wire audio_ready,sample_request,sample_underrun;
    assign control_ready=audio_ready;
    localparam integer PHYSICAL_KEYS=EXTERNAL_PIANO_KEYS ? 13 : 2;
    wire [PHYSICAL_KEYS-1:0] physical_key_n,key_press,key_release;
    generate if (EXTERNAL_PIANO_KEYS) begin : g_external_keys
        // Board KEY1/KEY2 remain C4/E4 aliases. Either switch may hold that key.
        assign physical_key_n=piano_key_n & {8'hff,Key_in[1],3'b111,Key_in[0]};
    end else begin : g_board_keys
        assign physical_key_n=Key_in;
    end endgenerate
    wire pv,pr,pt,cv,cr,ct,av,ar,at,cancel,cancel_ready,ac,acr,session_ready;
    wire [7:0] ps,asrc;
    wire [6:0] pn,pvel,cn,cvel,an,avel;
    wire [VOICES-1:0] voice_gate,voice_active,voice_trigger,release_done;
    wire [VOICES*7-1:0] voice_note_flat,voice_velocity_flat;
    wire [VOICES*8-1:0] voice_source_flat;
    wire [31:0] steal_count;
    wire [VOICES*16-1:0] voice_trigger_id_flat,release_trigger_id_flat;
    wire [5:0] voice_count,max_voice_count;
    wire signed [15:0] sample_data;
    wire sample_valid,sounding,sample_clipped;
    wire signed [15:0] bank_sample_data;
    wire bank_sample_valid;
    wire [16:0] master_gain;
    wire [17:0] bend_ratio;
    wire input_fault,allocator_cancel_ready;
    reg local_clear_sent;
    wire local_clear_pending=input_fault && !local_clear_sent;
    always @(posedge sys_clk) begin
        if(!audio_ready) local_clear_sent<=0;
        else if(local_clear_pending && allocator_cancel_ready) local_clear_sent<=1;
    end
    assign acr=allocator_cancel_ready && !local_clear_pending;
    wire output_frame_start;
    reg [1:0] pa_drain_frames;
    reg pa_audio_registered;
    always @(posedge sys_clk) begin
        if(!audio_ready) pa_audio_registered<=1'b0;
        else pa_audio_registered<=sounding || pa_drain_frames!=0;
    end
    // 16路活跃判定经寄存器后再驱动功放，切断合成乘法器到板级PA引脚的长路径。
    wire pa_audio_enable=ENABLE_CONTROLS ? pa_audio_registered : (sounding || pa_drain_frames!=0);
    // A静音时，B还可能在发送上一非零样本。再留三个真实输出帧边界，
    // 让待发/活动帧与左右DAC的零字排完；不增加新音启动等待。
    // 每个系统拍都可重装，避免很短的触发落在两个帧边界之间而漏记。
    always @(posedge sys_clk) begin
        if(!audio_ready) pa_drain_frames<=2'd0;
        else if(sounding) pa_drain_frames<=2'd3;
        else if(output_frame_start && pa_drain_frames!=0)
            pa_drain_frames<=pa_drain_frames-2'd1;
    end
    touch_or_key_if #(.KEY_COUNT(PHYSICAL_KEYS),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_keys(
        .clk(sys_clk),.rst_n(audio_ready),.raw_key(physical_key_n),.key_level(),
        .key_press(key_press),.key_release(key_release));
    event_encoder #(.KEY_COUNT(PHYSICAL_KEYS),.SOURCE_WIDTH(8),.CHROMATIC_KEYS(EXTERNAL_PIANO_KEYS),
        .ENABLE_PLAY_CONTROL(ENABLE_CONTROLS)) u_key_events(
        .clk(sys_clk),.rst_n(audio_ready),.key_press(key_press),.key_release(key_release),
        .key_velocity_flat({PHYSICAL_KEYS{7'd100}}),.input_timbre(4'd0),
        .octave_select(ENABLE_CONTROLS ? control_octave : 2'd1),.input_overflow(input_fault),
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
    voice_allocator #(.VOICES(VOICES),.IDX_WIDTH((VOICES>1)?$clog2(VOICES):1),.COUNT_WIDTH(6),.SOURCE_WIDTH(8),
        .MERGE_SAME_NOTE(0),.ENABLE_CANCEL(1),.ENABLE_PLAY_CONTROL(ENABLE_CONTROLS),
        .CHECK_RELEASE_ID(ENABLE_CONTROLS)) u_allocator(
        .clk(sys_clk),.rst_n(audio_ready),.event_valid(av && !local_clear_pending),.event_ready(ar),.event_type(at),
        .event_source_id(asrc),.event_note(an),.event_velocity(avel),.event_timbre(4'd0),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(8'd0),.expr_note(7'd0),
        .expr_pitch_bend(16'd0),.expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(release_done),.cancel_valid(local_clear_pending || ac),.cancel_ready(allocator_cancel_ready),
        .cancel_mask(local_clear_pending ? 8'hf0 : 8'h80),.cancel_value(local_clear_pending ? 8'h00 : 8'h80),
        .sustain_on(ENABLE_CONTROLS ? control_sustain : 1'b0),
        .release_trigger_id_flat(release_trigger_id_flat),.voice_trigger_id_flat(voice_trigger_id_flat),.voice_key_down(),
        .voice_active(voice_active),.voice_gate(voice_gate),.voice_trigger(voice_trigger),
        .voice_source_id_flat(voice_source_flat),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),.voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),
        .voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count),
        .note_on_count(),.note_off_count(),.steal_pulse());
    // 控制模式：R0弯音乘法 -> R1 DDS/包络 -> R4混音 -> R5音量 -> R6缓存。
    // 当前上位机只选固定预设；明确接零，避免合并新音色接口后出现悬空/Z。
    // 两个表使用同一路径；常量选色允许综合裁剪未使用的明亮分支。
    voice_bank_adsr #(.ROM_FILE(ROM_FILE),.BRIGHT_ROM_FILE(ROM_FILE),.ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),.RELEASE_SAMPLES(RELEASE_SAMPLES),.MIX_SHIFT(5),
        .VOICES(VOICES),.ENABLE_CONTROLS(ENABLE_CONTROLS)) u_bank(
        .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),.voice_gate(voice_gate),
        .voice_retrigger(voice_trigger),.voice_timbre({VOICES{1'b0}}),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .voice_trigger_id_flat(voice_trigger_id_flat),.release_trigger_id_flat(release_trigger_id_flat),.bend_ratio(bend_ratio),
        .release_done(release_done),.sounding(sounding),.sample_data(bank_sample_data),.sample_valid(bank_sample_valid),
        .env_level_flat(),.voice_active(),.sample_clipped(sample_clipped));
    generate if(ENABLE_CONTROLS) begin:g_controls
        piano_controls u_parameters(.clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
            .knob_value_flat(knob_value_flat),.knob_valid(knob_valid),.param_ready(param_ready),.param_fault(param_fault),
            .master_gain(master_gain),.bend_ratio(bend_ratio));
        // 与R0请求快照对齐：R4混音、R5全局增益、R6由B缓存。
        reg [16:0] gain_d0,gain_d1,gain_d2,gain_d3,gain_d4;
        always @(posedge sys_clk) begin
            if(!audio_ready) begin gain_d0<=0;gain_d1<=0;gain_d2<=0;gain_d3<=0;gain_d4<=0;end
            else begin gain_d0<=master_gain;gain_d1<=gain_d0;gain_d2<=gain_d1;gain_d3<=gain_d2;gain_d4<=gain_d3;end
        end
        sample_gain u_master(.clk(sys_clk),.rst(!audio_ready),.in_valid(bank_sample_valid),
            .sample_in(bank_sample_data),.gain(gain_d4),.sample_out(sample_data),.out_valid(sample_valid));
    end else begin:g_fixed_controls
        assign master_gain=17'd65536;
        assign bend_ratio=18'd65536;
        assign sample_data=bank_sample_data;
        assign sample_valid=bank_sample_valid;
    end endgenerate
    synth_top #(.AUDIO_CLK_HZ(50000000),.SAMPLE_RATE_HZ(48000),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),.MAX_SAMPLE_LATENCY_CYCLES(ENABLE_CONTROLS ? 6 : 4)) u_b(
        .clk_in(sys_clk),.rst_n(sys_rst_n),.audio_enable(pa_audio_enable),.sample_data(sample_data),.sample_valid(sample_valid),
        .audio_ready(audio_ready),.sample_request(sample_request),.sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK),.i2s_lrclk(HP_WS),.i2s_sdata(HP_DIN),.pa_en(PA_EN),
        .frame_start(output_frame_start));
endmodule
