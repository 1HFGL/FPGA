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
    parameter integer ENABLE_CONTROLS=0,
    parameter integer ENABLE_GUITAR=0,
    parameter GUITAR_ROM_FILE="",
    parameter SINE_ROM_FILE="",
    parameter integer USE_MODAL=0,
    parameter MODE_ROM_FILE="",
    parameter SHAPER_ROM_FILE="",
    parameter integer ENABLE_BRIGHTNESS=0,
    parameter integer BRIGHTNESS_REPEAT_CYCLES=25000000,
    parameter integer ENABLE_OCTAVE_KEY=0,
    parameter integer EXTERNAL_BRIGHTNESS=0,
    parameter integer ENABLE_REVERB=0,
    parameter integer ENABLE_CHORUS=0,
    parameter integer ENABLE_DELAY=0
)(
    input wire sys_clk,sys_rst_n,input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx,output wire uart_tx,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    input wire [13:0] knob_value_flat,
    input wire knob_valid,param_ready,param_fault,
    input wire control_sustain,
    input wire [1:0] control_octave,
    output wire control_ready,
    output wire monitor_audio_valid,
    output wire signed [15:0] monitor_audio_sample,
    output reg [12:0] monitor_key_down,
    output wire monitor_instrument_guitar,
    output reg [12:0] monitor_piano_keys,monitor_guitar_keys,
    output reg [1:0] monitor_octave,
    input wire [6:0] control_brightness, // synchronous to sys_clk; used only with EXTERNAL_BRIGHTNESS
    output wire [6:0] monitor_brightness
);
    wire audio_ready,sample_request,sample_underrun;
    assign control_ready=audio_ready;
    localparam integer PHYSICAL_KEYS=EXTERNAL_PIANO_KEYS ? 13 : 2;
    // External brightness coexists with KEY1 octave; the old key mode stays exclusive.
    localparam integer USE_BRIGHTNESS=ENABLE_BRIGHTNESS && (EXTERNAL_BRIGHTNESS || !ENABLE_OCTAVE_KEY);
    reg [1:0] selected_octave;
    wire octave_press;
    wire [1:0] next_octave=(selected_octave==2)?2'd0:selected_octave+2'd1;
    wire [1:0] active_octave=ENABLE_OCTAVE_KEY ? selected_octave :
        (ENABLE_CONTROLS && control_octave<3 ? control_octave : 2'd1);
    // Simultaneous accepted KEY1 and note presses use the new range.
    wire [1:0] event_octave=(ENABLE_OCTAVE_KEY && octave_press)?next_octave:active_octave;
    wire [6:0] display_note_base=(active_octave==0)?7'd48:(active_octave==2)?7'd72:7'd60;
    generate if(ENABLE_OCTAVE_KEY)begin:g_octave_key
        input_sync_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
            .CNT_WIDTH((DEBOUNCE_CYCLES>1)?$clog2(DEBOUNCE_CYCLES):1)) u_octave(
            .clk(sys_clk),.rst_n(audio_ready),.async_in(Key_in[0]),
            .level(),.press_pulse(octave_press),.release_pulse());
    end else begin:g_external_octave
        assign octave_press=1'b0;
    end endgenerate
    always @(posedge sys_clk)begin
        if(!audio_ready)selected_octave<=2'd1;
        else if(octave_press)selected_octave<=next_octave;
    end
    // 编译期从基准ROM的目录定位同目录乐器表，GUI/仿真都沿用各自有效路径。
    // 可用显式参数覆盖；函数只处理常量文件名，不形成硬件路径处理器。
    function [2047:0] sibling_rom;
        input [2047:0] original;
        input [255:0] basename;
        input integer bytes;
        integer c;
        reg found;
        begin
            sibling_rom=basename;found=0;
            for(c=0;c<256;c=c+1)begin
                if(!found && (original[c*8+:8]==8'h2f || original[c*8+:8]==8'h5c))begin
                    sibling_rom=((original>>(c*8))<<(bytes*8))|basename;found=1;
                end
            end
        end
    endfunction
    localparam [2047:0] GUITAR_FILE=(GUITAR_ROM_FILE=="")?sibling_rom(ROM_FILE,"guitar_1024.mem",15):GUITAR_ROM_FILE;
    localparam [2047:0] SINE_FILE=(SINE_ROM_FILE=="")?sibling_rom(ROM_FILE,"sine_1024.mem",13):SINE_ROM_FILE;
    localparam [2047:0] MODE_FILE=(MODE_ROM_FILE=="")?sibling_rom(ROM_FILE,"piano_v3_modes.mem",18):MODE_ROM_FILE;
    localparam [2047:0] MODE_EVEN_FILE=sibling_rom(ROM_FILE,"modes_even.mem",14);
    localparam [2047:0] MODE_ODD_FILE=sibling_rom(ROM_FILE,"modes_odd.mem",13);
    localparam [2047:0] SHAPER_FILE=(SHAPER_ROM_FILE=="")?sibling_rom(ROM_FILE,"rock_v2_shaper.mem",18):SHAPER_ROM_FILE;
    reg selected_guitar;
    wire mode_press;
    generate if(ENABLE_GUITAR)begin:g_mode_key
        input_sync_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
            .CNT_WIDTH((DEBOUNCE_CYCLES>1)?$clog2(DEBOUNCE_CYCLES):1)) u_mode(
            .clk(sys_clk),.rst_n(audio_ready),.async_in(Key_in[1]),
            .level(),.press_pulse(mode_press),.release_pulse());
    end else begin:g_fixed_mode
        assign mode_press=1'b0;
    end endgenerate
    always @(posedge sys_clk)begin
        if(!audio_ready)selected_guitar<=0;
        else if(mode_press)selected_guitar<=~selected_guitar;
    end
    assign monitor_instrument_guitar=ENABLE_GUITAR && selected_guitar;
    // 与模式切换同拍接收的新音使用新模式；旧声部保存自己起音时的选择。
    wire note_guitar=ENABLE_GUITAR && (selected_guitar ^ mode_press);
    wire [PHYSICAL_KEYS-1:0] physical_key_n,key_press,key_release;
    generate if (EXTERNAL_PIANO_KEYS) begin : g_external_keys
        // 正式KEY1切音区、KEY2切乐器；旧兼容配置仍保留C4/E4别名。
        assign physical_key_n=(USE_BRIGHTNESS || ENABLE_OCTAVE_KEY) ? piano_key_n : piano_key_n & {8'hff,(ENABLE_GUITAR?1'b1:Key_in[1]),3'b111,Key_in[0]};
    end else begin : g_board_keys
        assign physical_key_n={ENABLE_GUITAR?1'b1:Key_in[1],ENABLE_OCTAVE_KEY?1'b1:Key_in[0]};
    end endgenerate
    wire pv,pr,pt,cv,cr,ct,av,ar,at,cancel,cancel_ready,ac,acr,session_ready;
    wire [7:0] ps,asrc;
    wire [6:0] pn,pvel,cn,cvel,an,avel;
    wire [VOICES-1:0] voice_gate,voice_active,voice_trigger,release_done;
    wire [VOICES-1:0] voice_key_down;
    wire [VOICES*7-1:0] voice_note_flat,voice_velocity_flat;
    wire [VOICES*8-1:0] voice_source_flat;
    wire [VOICES*4-1:0] voice_timbre_flat;
    wire [VOICES-1:0] bank_timbre;
    genvar instrument_voice;
    generate for(instrument_voice=0;instrument_voice<VOICES;instrument_voice=instrument_voice+1)begin:g_timbre
        assign bank_timbre[instrument_voice]=ENABLE_GUITAR && voice_timbre_flat[instrument_voice*4];
    end endgenerate
    wire [31:0] steal_count;
    wire [VOICES*16-1:0] voice_trigger_id_flat,release_trigger_id_flat;
    wire [5:0] voice_count,max_voice_count;
    wire signed [15:0] sample_data;
    wire sample_valid,sounding,sample_clipped;
    wire signed [15:0] output_sample_data;
    wire signed [15:0] tone_sample_data;
    wire tone_sample_valid,reverb_tail,reverb_overrun;
    wire signed [15:0] chorus_sample_data,delay_sample_data;
    wire chorus_sample_valid,delay_sample_valid,chorus_tail,delay_tail,chorus_overrun,delay_overrun;
    wire output_sample_valid,tone_tail,tone_overrun;
    wire [6:0] brightness_target,brightness_current;
    assign monitor_brightness=brightness_current;
    wire output_sounding=sounding || tone_tail || chorus_tail || delay_tail || reverb_tail;
    assign monitor_audio_valid=output_sample_valid;
    assign monitor_audio_sample=output_sample_data;
    // 只观察已接受的声部状态：PC与实体同音作OR，尾音不显示成仍按住。
    // 仅高亮当前13音窗口；换档前仍按住的越区旧音继续发声，按原音高松键。
    reg [12:0] held_keys,piano_held,guitar_held;
    integer monitor_voice,monitor_key;
    always @(*) begin
        held_keys=0;piano_held=0;guitar_held=0;
        for(monitor_voice=0;monitor_voice<VOICES;monitor_voice=monitor_voice+1)
            for(monitor_key=0;monitor_key<13;monitor_key=monitor_key+1)
                if(voice_key_down[monitor_voice] && voice_note_flat[monitor_voice*7+:7]==display_note_base+monitor_key)
                begin
                    held_keys[monitor_key]=1'b1;
                    if(bank_timbre[monitor_voice])guitar_held[monitor_key]=1'b1;
                    else piano_held[monitor_key]=1'b1;
                end
    end
    always @(posedge sys_clk) begin
        if(!audio_ready)begin monitor_key_down<=0;monitor_piano_keys<=0;monitor_guitar_keys<=0;monitor_octave<=1;end
        else begin
            monitor_key_down<=held_keys;monitor_piano_keys<=piano_held;monitor_guitar_keys<=guitar_held;
            monitor_octave<=active_octave;
        end
    end
    wire signed [15:0] bank_sample_data;
    wire bank_sample_valid;
    wire signed [15:0] legacy_sample_data;
    wire legacy_sample_valid,legacy_sounding,legacy_clipped;
    wire [VOICES-1:0] legacy_release_done;
    wire [VOICES*16-1:0] legacy_release_ids;
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
        else pa_audio_registered<=output_sounding || pa_drain_frames!=0;
    end
    // 16路活跃判定经寄存器后再驱动功放，切断合成乘法器到板级PA引脚的长路径。
    wire pa_audio_enable=ENABLE_CONTROLS ? pa_audio_registered : (output_sounding || pa_drain_frames!=0);
    // A静音时，B还可能在发送上一非零样本。再留三个真实输出帧边界，
    // 让待发/活动帧与左右DAC的零字排完；不增加新音启动等待。
    // 每个系统拍都可重装，避免很短的触发落在两个帧边界之间而漏记。
    always @(posedge sys_clk) begin
        if(!audio_ready) pa_drain_frames<=2'd0;
        else if(output_sounding) pa_drain_frames<=2'd3;
        else if(output_frame_start && pa_drain_frames!=0)
            pa_drain_frames<=pa_drain_frames-2'd1;
    end
    touch_or_key_if #(.KEY_COUNT(PHYSICAL_KEYS),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_keys(
        .clk(sys_clk),.rst_n(audio_ready),.raw_key(physical_key_n),.key_level(),
        .key_press(key_press),.key_release(key_release));
    event_encoder #(.KEY_COUNT(PHYSICAL_KEYS),.SOURCE_WIDTH(8),.CHROMATIC_KEYS(EXTERNAL_PIANO_KEYS),
        .ENABLE_PLAY_CONTROL(ENABLE_CONTROLS || ENABLE_OCTAVE_KEY)) u_key_events(
        .clk(sys_clk),.rst_n(audio_ready),.key_press(key_press),.key_release(key_release),
        .key_velocity_flat({PHYSICAL_KEYS{7'd100}}),.input_timbre(4'd0),
        .octave_select(event_octave),.input_overflow(input_fault),
        .event_valid(pv),.event_ready(pr),.event_type(pt),.event_source_id(ps),
        .event_note(pn),.event_velocity(pvel),.event_timbre());
    uart_synth_protocol #(.CLKS_PER_BIT(UART_CLKS_PER_BIT),.WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .ENABLE_GUITAR(ENABLE_GUITAR),.FIXED_PIANO(FIXED_PIANO),.VOICES(VOICES)) u_uart(
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
        .event_source_id(asrc),.event_note(an),.event_velocity(avel),.event_timbre({3'd0,note_guitar}),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(8'd0),.expr_note(7'd0),
        .expr_pitch_bend(16'd0),.expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(release_done),.cancel_valid(local_clear_pending || ac),.cancel_ready(allocator_cancel_ready),
        .cancel_mask(local_clear_pending ? 8'hf0 : 8'h80),.cancel_value(local_clear_pending ? 8'h00 : 8'h80),
        .sustain_on(ENABLE_CONTROLS ? control_sustain : 1'b0),
        .release_trigger_id_flat(release_trigger_id_flat),.voice_trigger_id_flat(voice_trigger_id_flat),.voice_key_down(voice_key_down),
        .voice_active(voice_active),.voice_gate(voice_gate),.voice_trigger(voice_trigger),
        .voice_source_id_flat(voice_source_flat),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(voice_timbre_flat),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),.voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),
        .voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count),
        .note_on_count(),.note_off_count(),.steal_pulse());
    // 单预设：R0弯音 -> R1 DDS/包络 -> R4混音 -> R5音量 -> R6缓存。
    // 双乐器：多一拍亮度处理，R5混音 -> R6音量 -> R7缓存；共用同一16席声部池。
    voice_bank_adsr #(.ROM_FILE(ROM_FILE),.BRIGHT_ROM_FILE(ROM_FILE),.ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),.RELEASE_SAMPLES(RELEASE_SAMPLES),.MIX_SHIFT(5),
        .VOICES(VOICES),.ENABLE_CONTROLS(ENABLE_CONTROLS),.ENABLE_GUITAR(ENABLE_GUITAR),
        .GUITAR_ROM_FILE(GUITAR_FILE),.SINE_ROM_FILE(SINE_FILE)) u_bank(
        .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),.voice_gate(voice_gate),
        .voice_retrigger(voice_trigger),.voice_timbre(bank_timbre),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .voice_trigger_id_flat(voice_trigger_id_flat),.release_trigger_id_flat(legacy_release_ids),.bend_ratio(bend_ratio),
        .release_done(legacy_release_done),.sounding(legacy_sounding),.sample_data(bank_sample_data),.sample_valid(bank_sample_valid),
        .env_level_flat(),.voice_active(),.sample_clipped(legacy_clipped));
    generate if(ENABLE_CONTROLS) begin:g_controls
        // 复位默认值必须是满音量：这是既有集成测试和上电行为约定的合同。
        // 低音量软启动会改变复位后的首个采样，属于对外可观察行为，不能由音色模式决定。
        piano_controls #(.RESET_GAIN(17'd65536)) u_parameters(.clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
            .knob_value_flat(knob_value_flat),.knob_valid(knob_valid),.param_ready(param_ready),.param_fault(param_fault),
            .master_gain(master_gain),.bend_ratio(bend_ratio));
        // 与R0请求快照对齐；双乐器多延迟一拍增益，不能给旧样本乘上新旋钮值。
        reg [16:0] gain_d0,gain_d1,gain_d2,gain_d3,gain_d4_raw,gain_d5;
        wire [16:0] gain_d4=ENABLE_GUITAR?gain_d5:gain_d4_raw;
        always @(posedge sys_clk) begin
            if(!audio_ready) begin gain_d0<=0;gain_d1<=0;gain_d2<=0;gain_d3<=0;gain_d4_raw<=0;gain_d5<=0;end
            else begin gain_d0<=master_gain;gain_d1<=gain_d0;gain_d2<=gain_d1;gain_d3<=gain_d2;
                gain_d4_raw<=gain_d3;gain_d5<=gain_d4_raw;end
        end
        sample_gain u_master(.clk(sys_clk),.rst(!audio_ready),.in_valid(bank_sample_valid),
            .sample_in(bank_sample_data),.gain(gain_d4),.sample_out(legacy_sample_data),.out_valid(legacy_sample_valid));
    end else begin:g_fixed_controls
        assign master_gain=17'd65536;
        assign bend_ratio=18'd65536;
        assign legacy_sample_data=bank_sample_data;
        assign legacy_sample_valid=bank_sample_valid;
    end endgenerate
    generate if(USE_MODAL)begin:g_modal
        wire core_busy,core_overrun;
        voice_bank_modal_adapter #(.VOICES(VOICES),.MODE_ROM_FILE(MODE_FILE),
            .MODE_EVEN_FILE(MODE_EVEN_FILE),.MODE_ODD_FILE(MODE_ODD_FILE),
            .SHAPER_ROM_FILE(SHAPER_FILE),.SINE_ROM_FILE(SINE_FILE)) u_bank(
            .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
            .master_gain(master_gain),.bend_ratio(bend_ratio[16:0]),
            .voice_gate(voice_gate),.voice_guitar(bank_timbre),
            .voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
            .voice_trigger_id_flat(voice_trigger_id_flat),.release_trigger_id_flat(release_trigger_id_flat),
            .release_done(release_done),.sounding(sounding),.busy(core_busy),.overrun(core_overrun),
            .sample_data(sample_data),.sample_valid(sample_valid),.sample_clipped(sample_clipped));
    end else begin:g_legacy_bank
        assign sample_data=legacy_sample_data;assign sample_valid=legacy_sample_valid;
        assign sounding=legacy_sounding;assign sample_clipped=legacy_clipped;
        assign release_done=legacy_release_done;assign release_trigger_id_flat=legacy_release_ids;
    end endgenerate
    // Three-clock tone pipeline follows either bank. It never blocks audio requests.
    // External control slews once per audio request, independently of pixel refresh.
    generate if(USE_BRIGHTNESS) begin:g_brightness
        if(EXTERNAL_BRIGHTNESS)begin:g_external
            reg [6:0] current;
            assign brightness_target=control_brightness;
            assign brightness_current=current;
            always @(posedge sys_clk)begin
                if(!audio_ready)current<=127;
                else if(sample_request)begin
                    if(current<brightness_target)current<=current+1'b1;
                    else if(current>brightness_target)current<=current-1'b1;
                end
            end
        end else begin:g_keys
            brightness_keys #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.REPEAT_CYCLES(BRIGHTNESS_REPEAT_CYCLES),
                .SINGLE_KEY(ENABLE_GUITAR)) u_keys(
                .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),.key_n(Key_in),
                .target(brightness_target),.current(brightness_current));
        end
        tone_filter u_tone(.clk(sys_clk),.rst_n(audio_ready),.in_valid(sample_valid),
            .sample_in(sample_data),.brightness(brightness_current),.sample_out(tone_sample_data),
            .out_valid(tone_sample_valid),.tail_active(tone_tail),.overrun(tone_overrun));
    end else begin:g_no_brightness
        assign brightness_target=127;assign brightness_current=127;
        assign tone_sample_data=sample_data;assign tone_sample_valid=sample_valid;
        assign tone_tail=0;assign tone_overrun=0;
    end endgenerate
    // Shared post-mix effects: chorus -> echo -> room; each direct path remains immediate.
    // None of these copies is an independently playable voice.
    generate if(ENABLE_CHORUS)begin:g_chorus
        chorus_effect u_chorus(.clk(sys_clk),.rst_n(audio_ready),.in_valid(tone_sample_valid),
            .sample_in(tone_sample_data),.sample_out(chorus_sample_data),.out_valid(chorus_sample_valid),
            .tail_active(chorus_tail),.busy(),.overrun(chorus_overrun));
    end else begin:g_no_chorus
        assign chorus_sample_data=tone_sample_data;assign chorus_sample_valid=tone_sample_valid;
        assign chorus_tail=0;assign chorus_overrun=0;
    end endgenerate
    generate if(ENABLE_DELAY)begin:g_delay
        echo_delay u_delay(.clk(sys_clk),.rst_n(audio_ready),.in_valid(chorus_sample_valid),
            .sample_in(chorus_sample_data),.sample_out(delay_sample_data),.out_valid(delay_sample_valid),
            .tail_active(delay_tail),.busy(),.overrun(delay_overrun));
    end else begin:g_no_delay
        assign delay_sample_data=chorus_sample_data;assign delay_sample_valid=chorus_sample_valid;
        assign delay_tail=0;assign delay_overrun=0;
    end endgenerate
    // The existing room algorithm and preset are unchanged.
    generate if(ENABLE_REVERB)begin:g_reverb
        room_reverb u_room(.clk(sys_clk),.rst_n(audio_ready),.in_valid(delay_sample_valid),
            .sample_in(delay_sample_data),.sample_out(output_sample_data),.out_valid(output_sample_valid),
            .tail_active(reverb_tail),.busy(),.overrun(reverb_overrun));
    end else begin:g_dry
        assign output_sample_data=delay_sample_data;assign output_sample_valid=delay_sample_valid;
        assign reverb_tail=0;assign reverb_overrun=0;
    end endgenerate
    synth_top #(.AUDIO_CLK_HZ(50000000),.SAMPLE_RATE_HZ(48000),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),
        .MAX_SAMPLE_LATENCY_CYCLES((USE_MODAL?((VOICES>16)?(24*VOICES+36):(56*VOICES+28)):((ENABLE_CONTROLS?6:4)+(ENABLE_GUITAR?1:0)))+(USE_BRIGHTNESS?3:0)+(ENABLE_CHORUS?12:0)+(ENABLE_DELAY?5:0)+(ENABLE_REVERB?9:0))) u_b(
        .clk_in(sys_clk),.rst_n(sys_rst_n),.audio_enable(pa_audio_enable),.sample_data(output_sample_data),.sample_valid(output_sample_valid),
        .audio_ready(audio_ready),.sample_request(sample_request),.sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK),.i2s_lrclk(HP_WS),.i2s_sdata(HP_DIN),.pa_en(PA_EN),
        .frame_start(output_frame_start));
endmodule
