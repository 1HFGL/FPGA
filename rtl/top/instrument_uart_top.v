// 共用演奏系统：正式HDMI入口启用13键、32声部和三路ADC表情。
// 本模块默认4声部/关闭扩展，保留旧工程和既有TB的显式兼容配置。
// 数据流：四来源事件 -> 仲裁/分配 -> 实时合成 -> 明亮度 -> 合唱/延迟/混响 -> DAC。
// 全部内部模块50MHz同域，audio_ready统一异步断言/同步释放复位。
module instrument_uart_top #(
    parameter integer DEBOUNCE_CYCLES = 100000,
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer WATCHDOG_CYCLES = 150000000,
    parameter [31:0] ATTACK_SAMPLES = 96, DECAY_SAMPLES = 24000, RELEASE_SAMPLES = 5760,
    parameter [16:0] SUSTAIN_LEVEL = 6554,
    parameter ROM_FILE = "../../rtl/rom/sine_1024.mem",
    parameter integer FIXED_PIANO = 0,
    parameter integer REQUEST_LEAD_HALF_EDGES = 0,
    parameter integer EXTERNAL_PIANO_KEYS = 0,
    parameter integer VOICES = 4,
    parameter integer ENABLE_CONTROLS = 0,
    parameter integer ENABLE_GUITAR = 0,
    parameter GUITAR_ROM_FILE = "",
    parameter SINE_ROM_FILE = "",
    parameter integer USE_MODAL = 0,
    parameter MODE_ROM_FILE = "",
    parameter SHAPER_ROM_FILE = "",
    parameter integer ENABLE_BRIGHTNESS = 0,
    parameter integer ENHANCED_BRIGHTNESS = 0,
    parameter integer BRIGHTNESS_REPEAT_CYCLES = 25000000,
    parameter integer ENABLE_OCTAVE_KEY = 0,
    parameter integer EXTERNAL_BRIGHTNESS = 0,
    parameter integer ENABLE_REVERB = 0,
    parameter integer ENABLE_CHORUS = 0,
    parameter integer ENABLE_DELAY = 0,
    parameter integer ENABLE_BLE = 0,
    parameter integer ENABLE_TOUCH = 0,
    parameter integer ENABLE_CONTROL_FEATURES=0,
    parameter integer GUIDE_MS_CYCLES=50000,
    parameter integer BLE_CLKS_PER_BIT = 5208
)(
    input wire sys_clk, sys_rst_n, input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx, output wire uart_tx,
    output wire HP_BCK, HP_WS, HP_DIN, PA_EN,
    input wire [13:0] knob_value_flat,
    input wire knob_valid, param_ready, param_fault,
    input wire control_sustain,
    input wire [1:0] control_octave,
    output wire control_ready,
    output wire monitor_audio_valid,
    output wire signed [15:0] monitor_audio_sample,
    output reg [12:0] monitor_key_down,
    output wire monitor_instrument_guitar,
    output reg [12:0] monitor_piano_keys, monitor_guitar_keys,
    output reg [1:0] monitor_octave,
    input wire [6:0] control_brightness, // synchronous to sys_clk; used only with EXTERNAL_BRIGHTNESS
    output wire [6:0] monitor_brightness,
    input wire ble_rx, ble_state,
    output wire ble_tx,
    output reg monitor_note_on,
    output reg [6:0] monitor_event_note,
    input wire touch_event_valid, output wire touch_event_ready,
    input wire touch_event_on, touch_event_guitar,
    input wire [7:0] touch_event_source,
    input wire [6:0] touch_event_note, touch_event_velocity,
    input wire touch_cancel_valid, output wire touch_cancel_ready,
    input wire [2:0] function_key_n,
    input wire touch_control_valid,output wire touch_control_ready,
    input wire [3:0] touch_control_kind,input wire [1:0] touch_control_value,
    output wire monitor_sustain,
    output wire [74:0] monitor_guide
);
    // 音频时序是公共复位基准；Key_in[0]=音区，Key_in[1]=乐器。
    wire audio_ready, sample_request, sample_underrun;
    assign control_ready = audio_ready;
    localparam integer PHYSICAL_KEYS = EXTERNAL_PIANO_KEYS ? 13 : 2;
    localparam integer SOURCE_WIDTH = ENABLE_BLE ? 9 : 8;
    // External brightness coexists with KEY1 octave; the old key mode stays exclusive.
    localparam integer USE_BRIGHTNESS = ENABLE_BRIGHTNESS && (EXTERNAL_BRIGHTNESS || !ENABLE_OCTAVE_KEY);
    wire octave_press,mode_press;
    wire command_valid,command_ready;
    wire [3:0] command_kind;
    wire [7:0] command_value;
    wire panel_sustain;
    wire remote_valid,remote_ready;wire [3:0] remote_kind;wire [7:0] remote_value;
    wire config_valid,config_ready,config_abort,config_reply_valid,config_reply_ready;
    wire [3:0] config_kind;wire [31:0] config_seq,config_arg1,config_arg2;
    wire [191:0] config_reply_words;wire [103:0] keymap;wire mapping_idle;
    wire [31:0] song_identity,map_identity;
    wire accept_control=ENABLE_CONTROL_FEATURES && command_valid && command_ready;
    // 板载KEY1/2同沿规则优先；外部请求背压一拍，不丢操作。
    assign command_ready=!octave_press && !mode_press;
    assign monitor_sustain=ENABLE_CONTROL_FEATURES?panel_sustain:control_sustain;
    wire selected_download,download_valid,download_committed,guide_can_commit;
    wire [2:0] guide_state;
    wire [7:0] guide_bpm,download_bpm;
    wire [9:0] guide_progress,download_count;
    wire [1:0] guide_beat;
    wire [36:0] guide_target,score_mask;
    wire [8:0] score_index;
    wire [15:0] score_duration;
    wire guide_missing;
    // 75位原子显示：目标37、进度10、速度8、状态3、拍2、来源1、有效1、缺曲1，保留12。
    assign monitor_guide={12'd0,guide_missing,download_valid,selected_download,guide_beat,
        guide_state,guide_bpm,guide_progress,guide_target};
    generate if(ENABLE_CONTROL_FEATURES)begin:g_panel_control
        performance_controls #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_controls(
            .clk(sys_clk),.rst_n(audio_ready),.key_n(function_key_n),
            .touch_valid(touch_control_valid),.touch_ready(touch_control_ready),
            .touch_kind(touch_control_kind),.touch_value({6'd0,touch_control_value}),
            .remote_valid(remote_valid),.remote_ready(remote_ready),.remote_kind(remote_kind),.remote_value(remote_value),
            .command_valid(command_valid),.command_ready(command_ready),.command_kind(command_kind),
            .command_value(command_value),.sustain(panel_sustain));
        timed_practice_guide #(.MS_CYCLES(GUIDE_MS_CYCLES)) u_guide(
            .clk(sys_clk),.rst_n(audio_ready),.command_valid(accept_control),
            .command_kind(command_kind),.command_value(command_value),
            .download_valid(download_valid),.download_committed(download_committed),
            .download_count(download_count),.download_bpm(download_bpm),
            .read_index(score_index),.read_mask(score_mask),.read_duration(score_duration),
            .selected_download(selected_download),.state(guide_state),.bpm(guide_bpm),
            .progress(guide_progress),.beat(guide_beat),.target(guide_target),
            .missing_download(guide_missing),.can_commit(guide_can_commit));
    end else begin:g_legacy_control
        assign command_valid=0;assign command_kind=0;assign command_value=0;
        assign panel_sustain=0;assign touch_control_ready=1;assign remote_ready=1;
        assign guide_target=0;assign guide_progress=0;assign guide_bpm=90;
        assign guide_state=0;assign guide_beat=0;assign selected_download=0;
        assign guide_missing=0;assign guide_can_commit=1;assign score_index=0;
    end endgenerate
    reg [1:0] selected_octave;

    wire [1:0] next_octave = (selected_octave == 2) ? 2'd0 : selected_octave + 2'd1;
    wire [1:0] active_octave = ENABLE_OCTAVE_KEY ? selected_octave :
    (ENABLE_CONTROLS && control_octave < 3 ? control_octave : 2'd1);
    // Simultaneous accepted KEY1 and note presses use the new range.
    wire [1:0] event_octave = (ENABLE_OCTAVE_KEY && octave_press) ? next_octave:
        (accept_control && command_kind==2 && command_value<3)?command_value[1:0]: active_octave;
    wire [6:0] display_note_base = (active_octave == 0) ? 7'd48 : (active_octave == 2) ? 7'd72 : 7'd60;
    generate
        if (ENABLE_OCTAVE_KEY) begin : g_octave_key
            input_sync_debounce #(
                .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
                .CNT_WIDTH((DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1)
            ) u_octave(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .async_in(Key_in[0]),
                .level(),
                .press_pulse(octave_press),
                .release_pulse()
            );
        end else begin : g_external_octave
            assign octave_press = 1'b0;
        end
    endgenerate
    always @(posedge sys_clk) begin
        if (!audio_ready) selected_octave <= 2'd1;
        else if (octave_press) selected_octave <= next_octave;
        else if(accept_control && command_kind==2 && command_value<3)selected_octave<=command_value[1:0];
    end
    // 编译期从基准ROM的目录定位同目录乐器表，GUI/仿真都沿用各自有效路径。
    // 可用显式参数覆盖；函数只处理常量文件名，不形成硬件路径处理器。
    function[2047:0] sibling_rom;
        input [2047:0] original;
        input [255:0] basename;
        input integer bytes;
        integer c;
        reg found;
        begin
            sibling_rom = basename;
            found = 0;
            for (c = 0; c < 256; c = c + 1) begin
                if (!found && (original[c * 8 +: 8] == 8'h2f || original[c * 8 +: 8] == 8'h5c)) begin
                    sibling_rom = ((original >> (c * 8)) << (bytes * 8)) | basename;
                    found = 1;
                end
            end
        end
    endfunction
    localparam [2047:0] GUITAR_FILE = (GUITAR_ROM_FILE == "") ?
        sibling_rom(ROM_FILE, "guitar_1024.mem", 15) : GUITAR_ROM_FILE;
    localparam [2047:0] SINE_FILE = (SINE_ROM_FILE == "") ? sibling_rom(ROM_FILE, "sine_1024.mem", 13) : SINE_ROM_FILE;
    localparam [2047:0] MODE_FILE = (MODE_ROM_FILE == "") ? sibling_rom(ROM_FILE, "piano_v3_modes.mem", 18) : MODE_ROM_FILE;
    localparam [2047:0] MODE_EVEN_FILE = sibling_rom(ROM_FILE, "modes_even.mem", 14);
    localparam [2047:0] MODE_ODD_FILE = sibling_rom(ROM_FILE, "modes_odd.mem", 13);
    localparam [2047:0] SHAPER_FILE = (SHAPER_ROM_FILE == "") ?
        sibling_rom(ROM_FILE, "rock_v2_shaper.mem", 18) : SHAPER_ROM_FILE;
    reg selected_guitar;

    generate
        if (ENABLE_GUITAR) begin : g_mode_key
            input_sync_debounce #(
                .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
                .CNT_WIDTH((DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1)
            ) u_mode(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .async_in(Key_in[1]),
                .level(),
                .press_pulse(mode_press),
                .release_pulse()
            );
        end else begin : g_fixed_mode
            assign mode_press = 1'b0;
        end
    endgenerate
    always @(posedge sys_clk) begin
        if (!audio_ready) selected_guitar <= 0;
        else if (mode_press) selected_guitar <= ~selected_guitar;
        else if(accept_control && command_kind==1 && command_value<2)selected_guitar<=command_value[0];
    end
    assign monitor_instrument_guitar = ENABLE_GUITAR && selected_guitar;
    // 与模式切换同拍接收的新音使用新模式；旧声部保存自己起音时的选择。
    wire note_guitar = ENABLE_GUITAR && (mode_press?!selected_guitar:
        (accept_control && command_kind==1 && command_value<2)?command_value[0]:selected_guitar);
    wire [PHYSICAL_KEYS - 1:0] physical_key_n, key_press, key_release;
    generate
        if (EXTERNAL_PIANO_KEYS) begin : g_external_keys
            // 正式KEY1切音区、KEY2切乐器；旧兼容配置仍保留C4/E4别名。
            assign physical_key_n = (USE_BRIGHTNESS || ENABLE_OCTAVE_KEY) ?
                piano_key_n : piano_key_n &
                {8'hff, (ENABLE_GUITAR ? 1'b1 : Key_in[1]), 3'b111, Key_in[0]};
        end else begin : g_board_keys
            assign physical_key_n = {ENABLE_GUITAR ? 1'b1 : Key_in[1], ENABLE_OCTAVE_KEY ? 1'b1 : Key_in[0]};
        end
    endgenerate
    // 事件前缀：p=实体键，c=PC串口，b=BLE，a=仲裁后的公共事件。
    // v/r/t分别为valid/ready/type，n/vel分别为音高/力度；type=1表示起音。
    // 原短名保留，便于既有TB按层次观察；所有事件仅在valid && ready时接受。
    wire pv, pr, pt, cv, cr, ct, av, ar, at, cancel, cancel_ready, ac, acr, session_ready;
    wire [7:0] ps;
    wire [SOURCE_WIDTH - 1:0] asrc, cancel_mask, cancel_value;
    wire accepted_touch;
    wire bv, br, bt, bc, bcr;
    wire [6:0] bn, bvel;
    wire [6:0] pn, pvel, cn, cvel, an, avel;

    // 分配器保存各声部的音高、力度、来源、音色与触发代次。
    // flat向量按槽号从低位展开；旧音保存起音音色，不随当前乐器切换。
    wire [VOICES - 1:0] voice_gate, voice_active, voice_trigger, release_done;
    wire [VOICES - 1:0] voice_key_down;
    wire [VOICES * 7 - 1:0] voice_note_flat, voice_velocity_flat;
    wire [VOICES * SOURCE_WIDTH - 1:0] voice_source_flat;
    wire [VOICES * 4 - 1:0] voice_timbre_flat;
    wire [VOICES - 1:0] bank_timbre;
    genvar instrument_voice;
    generate
        for (instrument_voice = 0; instrument_voice < VOICES; instrument_voice = instrument_voice + 1) begin : g_timbre
            assign bank_timbre[instrument_voice] = ENABLE_GUITAR && voice_timbre_flat[instrument_voice * 4];
        end
    endgenerate
    wire [31:0] steal_count;
    wire [VOICES * 16 - 1:0] voice_trigger_id_flat, release_trigger_id_flat;
    wire [5:0] voice_count, max_voice_count;

    // 后级共用单声道音频链；各效果的尾音均参与功放保持判定。
    wire signed [15:0] sample_data;
    wire sample_valid, sounding, sample_clipped;
    wire signed [15:0] output_sample_data;
    wire signed [15:0] tone_sample_data;
    wire tone_sample_valid, reverb_tail, reverb_overrun;
    wire signed [15:0] chorus_sample_data, delay_sample_data;
    wire chorus_sample_valid, delay_sample_valid, chorus_tail, delay_tail, chorus_overrun, delay_overrun;
    wire output_sample_valid, tone_tail, tone_overrun;
    wire [6:0] brightness_target, brightness_current;
    assign monitor_brightness = brightness_current;
    wire output_sounding = sounding || tone_tail || chorus_tail || delay_tail || reverb_tail;
    assign monitor_audio_valid = output_sample_valid;
    assign monitor_audio_sample = output_sample_data;
    // 只观察已接受的声部状态：PC与实体同音作OR，尾音不显示成仍按住。
    // 仅高亮当前13音窗口；换档前仍按住的越区旧音继续发声，按原音高松键。
    reg [12:0] held_keys, piano_held, guitar_held;
    integer monitor_voice, monitor_key;
    always @(*) begin
        held_keys = 0;
        piano_held = 0;
        guitar_held = 0;
        for (monitor_voice = 0; monitor_voice < VOICES; monitor_voice = monitor_voice + 1)
            for (monitor_key = 0; monitor_key < 13; monitor_key = monitor_key + 1)
                if (voice_key_down[monitor_voice] &&
                    voice_note_flat[monitor_voice * 7 +: 7] == display_note_base + monitor_key) begin
                    held_keys[monitor_key] = 1'b1;
                    if (bank_timbre[monitor_voice]) guitar_held[monitor_key] = 1'b1;
                    else piano_held[monitor_key] = 1'b1;
                end
    end
    always @(posedge sys_clk) begin
        if (!audio_ready) begin
            monitor_key_down <= 0;
            monitor_piano_keys <= 0;
            monitor_guitar_keys <= 0;
            monitor_octave <= 1;
        end
        else begin
            monitor_key_down <= held_keys;
            monitor_piano_keys <= piano_held;
            monitor_guitar_keys <= guitar_held;
            monitor_octave <= active_octave;
        end
    end
    wire signed [15:0] bank_sample_data;
    wire bank_sample_valid;
    wire signed [15:0] legacy_sample_data;
    wire legacy_sample_valid, legacy_sounding, legacy_clipped;
    wire [VOICES - 1:0] legacy_release_done;
    wire [VOICES * 16 - 1:0] legacy_release_ids;
    wire [16:0] master_gain;
    wire [17:0] bend_ratio;
    wire input_fault, allocator_cancel_ready;
    reg local_clear_sent;
    wire local_clear_pending = input_fault && !local_clear_sent;
    // 显示副本单独寄存，隔断“串口取消判定→仲裁→导奏比较/使能”的长路径。
    // 只多20ns显示观察延迟；不改变原事件接收或任何音频流水级。
    always @(posedge sys_clk) begin
        if (!audio_ready) begin
            monitor_note_on <= 0;
            monitor_event_note <= 0;
        end
        else begin
            monitor_note_on <= av && ar && !local_clear_pending && at;
            if (av && ar && !local_clear_pending && at) monitor_event_note <= an;
        end
    end
    always @(posedge sys_clk) begin
        if (!audio_ready) local_clear_sent <= 0;
        else if (local_clear_pending && allocator_cancel_ready) local_clear_sent <= 1;
    end
    assign acr = allocator_cancel_ready && !local_clear_pending;
    wire output_frame_start;
    reg [1:0] pa_drain_frames;
    reg pa_audio_registered;
    always @(posedge sys_clk) begin
        if (!audio_ready) pa_audio_registered <= 1'b0;
        else pa_audio_registered <= output_sounding || pa_drain_frames != 0;
    end
    // 全部声部/效果的活跃判定先寄存，再驱动功放，隔断到板级PA引脚的长路径。
    wire pa_audio_enable = ENABLE_CONTROLS ? pa_audio_registered : (output_sounding || pa_drain_frames != 0);
    // A静音时，B还可能在发送上一非零样本。再留三个真实输出帧边界，
    // 让待发/活动帧与左右DAC的零字排完；不增加新音启动等待。
    // 每个系统拍都可重装，避免很短的触发落在两个帧边界之间而漏记。
    always @(posedge sys_clk) begin
        if (!audio_ready) pa_drain_frames <= 2'd0;
        else if (output_sounding) pa_drain_frames <= 2'd3;
        else if (output_frame_start && pa_drain_frames != 0)
            pa_drain_frames <= pa_drain_frames - 2'd1;
    end
    // 输入接入：实体键与PC/BLE各有自己的接收上下文，断连只取消本来源。
    touch_or_key_if #(
        .KEY_COUNT(PHYSICAL_KEYS),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_keys(
        .clk(sys_clk),
        .rst_n(audio_ready),
        .raw_key(physical_key_n),
        .key_level(),
        .key_press(key_press),
        .key_release(key_release)
    );
    event_encoder #(
        .KEY_COUNT(PHYSICAL_KEYS),
        .SOURCE_WIDTH(8),
        .CHROMATIC_KEYS(EXTERNAL_PIANO_KEYS),
        .ENABLE_PLAY_CONTROL(ENABLE_CONTROLS || ENABLE_OCTAVE_KEY),.ENABLE_KEYMAP(ENABLE_CONTROL_FEATURES && EXTERNAL_PIANO_KEYS)) u_key_events(
        .clk(sys_clk),
        .rst_n(audio_ready),
        .key_press(key_press),
        .key_release(key_release),
        .key_velocity_flat({PHYSICAL_KEYS{7'd100}}),
        .input_timbre(4'd0),
        .octave_select(event_octave),
        .input_overflow(input_fault),.keymap(keymap),.mapping_idle(mapping_idle),
        .event_valid(pv),
        .event_ready(pr),
        .event_type(pt),
        .event_source_id(ps),
        .event_note(pn),
        .event_velocity(pvel),
        .event_timbre()
    );
    generate if(ENABLE_CONTROL_FEATURES)begin:g_store
        performance_store u_store(.clk(sys_clk),.rst_n(audio_ready),.abort_upload(config_abort),
            .request_valid(config_valid),.request_ready(config_ready),.request_kind(config_kind),
            .seq(config_seq),.arg1(config_arg1),.arg2(config_arg2),
            .reply_valid(config_reply_valid),.reply_ready(config_reply_ready),.reply_words(config_reply_words),
            .remote_valid(remote_valid),.remote_ready(remote_ready),.remote_kind(remote_kind),.remote_value(remote_value),
            .guide_can_commit(guide_can_commit && !command_valid),.map_can_commit(mapping_idle),
            .actual_flags({15'd0,guide_bpm,guide_state,download_valid,selected_download,monitor_sustain,active_octave,selected_guitar}),
            .guide_progress(guide_progress),.download_valid(download_valid),.download_committed(download_committed),
            .download_count(download_count),.download_bpm(download_bpm),.read_index(score_index),
            .read_mask(score_mask),.read_duration(score_duration),.keymap(keymap),.song_identity(song_identity),.map_identity(map_identity));
    end else begin:g_no_store
        assign config_ready=0;assign config_reply_valid=0;assign config_reply_words=0;
        assign remote_valid=0;assign remote_kind=0;assign remote_value=0;
        assign download_valid=0;assign download_committed=0;assign download_count=0;assign download_bpm=90;
        assign score_mask=0;assign score_duration=96;assign keymap=0;assign song_identity=0;assign map_identity=0;
    end endgenerate
    uart_synth_protocol #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .ENABLE_GUITAR(ENABLE_GUITAR),
        .FIXED_PIANO(FIXED_PIANO),
        .VOICES(VOICES)
    ) u_uart(
        .clk(sys_clk),
        .rst_n(audio_ready),
        .rx(uart_rx),
        .tx(uart_tx),
        .config_valid(),.config_ready(1'b0),.config_kind(),.config_seq(),.config_arg1(),.config_arg2(),.config_abort(),
        .config_reply_valid(1'b0),.config_reply_ready(),.config_reply_words(192'd0),
        .event_valid(cv),
        .event_ready(cr),
        .event_type(ct),
        .event_note(cn),
        .event_velocity(cvel),
        .cancel_valid(cancel),
        .cancel_ready(cancel_ready),
        .session_ready(session_ready),
        .voice_count(voice_count),
        .max_voice_count(max_voice_count),
        .steal_count(steal_count)
    );
    generate
        if (ENABLE_BLE) begin : g_ble
            // STATE必须连接：原始异步信号仅进入meta；断连独立清BLE，不重置音频。
            // link_live在系统时钟边沿释放协议复位，接收器/解析器从干净会话开始。
            reg state_meta, state_sync, link_live, disconnect_pending;
            wire protocol_cancel;
            wire link_reset_n = audio_ready && link_live;
            always @(posedge sys_clk or negedge audio_ready) begin
                if (!audio_ready) begin
                    state_meta <= 0;
                    state_sync <= 0;
                end
                else begin
                    state_meta <= ble_state;
                    state_sync <= state_meta;
                end
            end
            always @(posedge sys_clk) begin
                if (!audio_ready) begin
                    link_live <= 0;
                    disconnect_pending <= 0;
                end
                else begin
                    if (state_sync) link_live <= 1;
                    else link_live <= 0;
                    if (bcr) disconnect_pending <= 0;
                    if (link_live && !state_sync) disconnect_pending <= 1;
                end
            end
        wire protocol_config_abort;
        assign config_abort=!link_live || !state_sync || protocol_config_abort;
        uart_synth_protocol #(
                .CLKS_PER_BIT(BLE_CLKS_PER_BIT),
                .WATCHDOG_CYCLES(WATCHDOG_CYCLES),
            .ENABLE_CONFIG(ENABLE_CONTROL_FEATURES),.ENABLE_GUITAR(ENABLE_GUITAR),
                .FIXED_PIANO(FIXED_PIANO),
                .VOICES(VOICES)
            ) u_protocol(
                .clk(sys_clk),
                .rst_n(link_reset_n),
                .rx(ble_rx),
                .tx(ble_tx),
            .config_valid(config_valid),.config_ready(config_ready),.config_kind(config_kind),
            .config_seq(config_seq),.config_arg1(config_arg1),.config_arg2(config_arg2),.config_abort(protocol_config_abort),
            .config_reply_valid(config_reply_valid),.config_reply_ready(config_reply_ready),.config_reply_words(config_reply_words),
                .event_valid(bv),
                .event_ready(br),
                .event_type(bt),
                .event_note(bn),
                .event_velocity(bvel),
                .cancel_valid(protocol_cancel),
                .cancel_ready(bcr),
                .session_ready(),
                .voice_count(voice_count),
                .max_voice_count(max_voice_count),
                .steal_count(steal_count)
            );
            assign bc = protocol_cancel || disconnect_pending;
        end else begin : g_no_ble
            assign bv = 1'b0;
            assign bt = 1'b0;
            assign bn = 7'd0;
            assign bvel = 7'd0;
            assign bc = 1'b0;
            assign ble_tx = 1'b1;
        assign config_valid=0;assign config_kind=0;assign config_seq=0;assign config_arg1=0;assign config_arg2=0;
        assign config_abort=1;assign config_reply_ready=1;
        end
    endgenerate
    // 来源编号由仲裁器统一编码，避免相同音高的实体/USB/PC/BLE相互松键。
    uart_event_arbiter #(
        .ENABLE_BLE(ENABLE_BLE),
        .ENABLE_TOUCH(ENABLE_TOUCH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    ) u_arbiter(
        .clk(sys_clk),
        .rst_n(audio_ready),
        .sample_request(sample_request),
        .physical_valid(pv),
        .physical_ready(pr),
        .physical_type(pt),
        .physical_source(ps),
        .physical_note(pn),
        .physical_velocity(pvel),
        .pc_valid(cv),
        .pc_ready(cr),
        .pc_type(ct),
        .pc_note(cn),
        .pc_velocity(cvel),
        .cancel_valid(cancel),
        .cancel_ready(cancel_ready),
        .allocator_cancel(ac),
        .allocator_cancel_ready(acr),
        .event_valid(av),
        .event_ready(ar),
        .event_type(at),
        .event_source(asrc),
        .event_note(an),
        .event_velocity(avel),
        .ble_valid(bv),
        .ble_ready(br),
        .ble_type(bt),
        .ble_note(bn),
        .ble_velocity(bvel),
        .ble_cancel_valid(bc),
        .ble_cancel_ready(bcr),
        .allocator_cancel_mask(cancel_mask),
        .allocator_cancel_value(cancel_value),
        .touch_valid(touch_event_valid),
        .touch_ready(touch_event_ready),
        .touch_type(touch_event_on),
        .touch_source(touch_event_source),
        .touch_note(touch_event_note),
        .touch_velocity(touch_event_velocity),
        .touch_cancel_valid(touch_cancel_valid),
        .touch_cancel_ready(touch_cancel_ready),
        .event_touch(accepted_touch)
    );
    // 只有分配器修改声部所有权；参数表达式通道当前未开放，延音为独立电平。
    voice_allocator #(
        .VOICES(VOICES),
        .IDX_WIDTH((VOICES > 1) ? $clog2(VOICES) : 1),
        .COUNT_WIDTH(6),
        .SOURCE_WIDTH(SOURCE_WIDTH),
        .MERGE_SAME_NOTE(0),
        .ENABLE_CANCEL(1),
        .ENABLE_PLAY_CONTROL(ENABLE_CONTROLS),
        .CHECK_RELEASE_ID(ENABLE_CONTROLS)
    ) u_allocator(
        .clk(sys_clk),
        .rst_n(audio_ready),
        .event_valid(av && !local_clear_pending),
        .event_ready(ar),
        .event_type(at),
        .event_source_id(asrc),
        .event_note(an),
        .event_velocity(avel),
        .event_timbre({3'd0, accepted_touch ? touch_event_guitar : note_guitar}),
        .expr_valid(1'b0),
        .expr_ready(),
        .expr_source_id({SOURCE_WIDTH{1'b0}}),
        .expr_note(7'd0),
        .expr_pitch_bend(16'd0),
        .expr_aftertouch(8'd0),
        .expr_vibrato_depth(8'd0),
        .expr_vibrato_rate(8'd0),
        .release_done(release_done),
        .cancel_valid(local_clear_pending || ac),
        .cancel_ready(allocator_cancel_ready),
        .cancel_mask(local_clear_pending ? {{(SOURCE_WIDTH - 4){1'b1}}, 4'b0} : cancel_mask),
        .cancel_value(local_clear_pending ? {SOURCE_WIDTH{1'b0}} : cancel_value),
        .sustain_on(ENABLE_CONTROLS ? monitor_sustain : 1'b0),
        .release_trigger_id_flat(release_trigger_id_flat),
        .voice_trigger_id_flat(voice_trigger_id_flat),
        .voice_key_down(voice_key_down),
        .voice_active(voice_active),
        .voice_gate(voice_gate),
        .voice_trigger(voice_trigger),
        .voice_source_id_flat(voice_source_flat),
        .voice_note_flat(voice_note_flat),
        .voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(voice_timbre_flat),
        .voice_pitch_bend_flat(),
        .voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(),
        .voice_vibrato_rate_flat(),
        .voice_count(voice_count),
        .max_voice_count(max_voice_count),
        .steal_count(steal_count),
        .note_on_count(),
        .note_off_count(),
        .steal_pulse()
    );
    // 旧DDS兼容路径：单预设R6缓存，双乐器R7缓存；这些拍数不代表正式模态路径。
    // 正式USE_MODAL=1由下方适配层给出样本，32声部原始有效时刻为R925。
    voice_bank_adsr #(
        .ROM_FILE(ROM_FILE),
        .BRIGHT_ROM_FILE(ROM_FILE),
        .ATTACK_SAMPLES(ATTACK_SAMPLES),
        .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
        .RELEASE_SAMPLES(RELEASE_SAMPLES),
        .MIX_SHIFT(5),
        .VOICES(VOICES),
        .ENABLE_CONTROLS(ENABLE_CONTROLS),
        .ENABLE_GUITAR(ENABLE_GUITAR),
        .GUITAR_ROM_FILE(GUITAR_FILE),
        .SINE_ROM_FILE(SINE_FILE)
    ) u_bank(
        .clk(sys_clk),
        .rst_n(audio_ready),
        .sample_request(sample_request),
        .voice_gate(voice_gate),
        .voice_retrigger(voice_trigger),
        .voice_timbre(bank_timbre),
        .voice_note_flat(voice_note_flat),
        .voice_velocity_flat(voice_velocity_flat),
        .voice_trigger_id_flat(voice_trigger_id_flat),
        .release_trigger_id_flat(legacy_release_ids),
        .bend_ratio(bend_ratio),
        .release_done(legacy_release_done),
        .sounding(legacy_sounding),
        .sample_data(bank_sample_data),
        .sample_valid(bank_sample_valid),
        .env_level_flat(),
        .voice_active(),
        .sample_clipped(legacy_clipped)
    );
    generate
        if (ENABLE_CONTROLS) begin : g_controls
            // 复位默认值必须是满音量：这是既有集成测试和上电行为约定的合同。
            // 低音量软启动会改变复位后的首个采样，属于对外可观察行为，不能由音色模式决定。
            piano_controls #(
                .RESET_GAIN(17'd65536)
            ) u_parameters(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .sample_request(sample_request),
                .knob_value_flat(knob_value_flat),
                .knob_valid(knob_valid),
                .param_ready(param_ready),
                .param_fault(param_fault),
                .master_gain(master_gain),
                .bend_ratio(bend_ratio)
            );
            // 与R0请求快照对齐；双乐器多延迟一拍增益，不能给旧样本乘上新旋钮值。
            reg [16:0] gain_d0, gain_d1, gain_d2, gain_d3, gain_d4_raw, gain_d5;
            wire [16:0] gain_d4 = ENABLE_GUITAR ? gain_d5 : gain_d4_raw;
            always @(posedge sys_clk) begin
                if (!audio_ready) begin
                    gain_d0 <= 0;
                    gain_d1 <= 0;
                    gain_d2 <= 0;
                    gain_d3 <= 0;
                    gain_d4_raw <= 0;
                    gain_d5 <= 0;
                end
                else begin
                    gain_d0 <= master_gain;
                    gain_d1 <= gain_d0;
                    gain_d2 <= gain_d1;
                    gain_d3 <= gain_d2;
                    gain_d4_raw <= gain_d3;
                    gain_d5 <= gain_d4_raw;
                end
            end
            sample_gain u_master(
                .clk(sys_clk),
                .rst(!audio_ready),
                .in_valid(bank_sample_valid),
                .sample_in(bank_sample_data),
                .gain(gain_d4),
                .sample_out(legacy_sample_data),
                .out_valid(legacy_sample_valid)
            );
        end else begin : g_fixed_controls
            assign master_gain = 17'd65536;
            assign bend_ratio = 18'd65536;
            assign legacy_sample_data = bank_sample_data;
            assign legacy_sample_valid = bank_sample_valid;
        end
    endgenerate
    generate
        if (USE_MODAL) begin : g_modal
            wire core_busy, core_overrun;
            voice_bank_modal_adapter #(
                .VOICES(VOICES),
                .MODE_ROM_FILE(MODE_FILE),
                .MODE_EVEN_FILE(MODE_EVEN_FILE),
                .MODE_ODD_FILE(MODE_ODD_FILE),
                .SHAPER_ROM_FILE(SHAPER_FILE),
                .SINE_ROM_FILE(SINE_FILE)
            ) u_bank(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .sample_request(sample_request),
                .master_gain(master_gain),
                .bend_ratio(bend_ratio[16:0]),
                .voice_gate(voice_gate),
                .voice_guitar(bank_timbre),
                .voice_note_flat(voice_note_flat),
                .voice_velocity_flat(voice_velocity_flat),
                .voice_trigger_id_flat(voice_trigger_id_flat),
                .release_trigger_id_flat(release_trigger_id_flat),
                .release_done(release_done),
                .sounding(sounding),
                .busy(core_busy),
                .overrun(core_overrun),
                .sample_data(sample_data),
                .sample_valid(sample_valid),
                .sample_clipped(sample_clipped)
            );
        end else begin : g_legacy_bank
            assign sample_data = legacy_sample_data;
            assign sample_valid = legacy_sample_valid;
            assign sounding = legacy_sounding;
            assign sample_clipped = legacy_clipped;
            assign release_done = legacy_release_done;
            assign release_trigger_id_flat = legacy_release_ids;
        end
    endgenerate
    // Three-clock tone pipeline follows either bank. It never blocks audio requests.
    // External control slews once per audio request, independently of pixel refresh.
    generate
        if (USE_BRIGHTNESS) begin : g_brightness
            if (EXTERNAL_BRIGHTNESS) begin : g_external
                reg [6:0] current;
                assign brightness_target = control_brightness;
                assign brightness_current = current;
                always @(posedge sys_clk) begin
                    if (!audio_ready) current <= 127;
                    else if (sample_request) begin
                        if (current < brightness_target) current <= current + 1'b1;
                        else if (current > brightness_target) current <= current - 1'b1;
                    end
                end
            end else begin : g_keys
                brightness_keys #(
                    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
                    .REPEAT_CYCLES(BRIGHTNESS_REPEAT_CYCLES),
                    .SINGLE_KEY(ENABLE_GUITAR)
                ) u_keys(
                    .clk(sys_clk),
                    .rst_n(audio_ready),
                    .sample_request(sample_request),
                    .key_n(Key_in),
                    .target(brightness_target),
                    .current(brightness_current)
                );
            end
            if (ENHANCED_BRIGHTNESS) begin : g_expressive
                tone_filter_expressive u_tone(
                    .clk(sys_clk),
                    .rst_n(audio_ready),
                    .in_valid(sample_valid),
                    .sample_in(sample_data),
                    .brightness(brightness_current),
                    .sample_out(tone_sample_data),
                    .out_valid(tone_sample_valid),
                    .tail_active(tone_tail),
                    .overrun(tone_overrun)
                );
            end else begin : g_legacy_tone
                tone_filter u_tone(
                    .clk(sys_clk),
                    .rst_n(audio_ready),
                    .in_valid(sample_valid),
                    .sample_in(sample_data),
                    .brightness(brightness_current),
                    .sample_out(tone_sample_data),
                    .out_valid(tone_sample_valid),
                    .tail_active(tone_tail),
                    .overrun(tone_overrun)
                );
            end
        end else begin : g_no_brightness
            assign brightness_target = 127;
            assign brightness_current = 127;
            assign tone_sample_data = sample_data;
            assign tone_sample_valid = sample_valid;
            assign tone_tail = 0;
            assign tone_overrun = 0;
        end
    endgenerate
    // Shared post-mix effects: chorus -> echo -> room; each direct path remains immediate.
    // None of these copies is an independently playable voice.
    generate
        if (ENABLE_CHORUS) begin : g_chorus
            chorus_effect u_chorus(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .in_valid(tone_sample_valid),
                .sample_in(tone_sample_data),
                .sample_out(chorus_sample_data),
                .out_valid(chorus_sample_valid),
                .tail_active(chorus_tail),
                .busy(),
                .overrun(chorus_overrun)
            );
        end else begin : g_no_chorus
            assign chorus_sample_data = tone_sample_data;
            assign chorus_sample_valid = tone_sample_valid;
            assign chorus_tail = 0;
            assign chorus_overrun = 0;
        end
    endgenerate
    generate
        if (ENABLE_DELAY) begin : g_delay
            echo_delay u_delay(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .in_valid(chorus_sample_valid),
                .sample_in(chorus_sample_data),
                .sample_out(delay_sample_data),
                .out_valid(delay_sample_valid),
                .tail_active(delay_tail),
                .busy(),
                .overrun(delay_overrun)
            );
        end else begin : g_no_delay
            assign delay_sample_data = chorus_sample_data;
            assign delay_sample_valid = chorus_sample_valid;
            assign delay_tail = 0;
            assign delay_overrun = 0;
        end
    endgenerate
    // The existing room algorithm and preset are unchanged.
    generate
        if (ENABLE_REVERB) begin : g_reverb
            room_reverb u_room(
                .clk(sys_clk),
                .rst_n(audio_ready),
                .in_valid(delay_sample_valid),
                .sample_in(delay_sample_data),
                .sample_out(output_sample_data),
                .out_valid(output_sample_valid),
                .tail_active(reverb_tail),
                .busy(),
                .overrun(reverb_overrun)
            );
        end else begin : g_dry
            assign output_sample_data = delay_sample_data;
            assign output_sample_valid = delay_sample_valid;
            assign reverb_tail = 0;
            assign reverb_overrun = 0;
        end
    endgenerate
    synth_top #(
        .AUDIO_CLK_HZ(50000000),
        .SAMPLE_RATE_HZ(48000),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),
        // 请求到缓存的原有周期预算：合成路径 + 明亮度 + 三个后级效果。
        // 保留原括号/常数；正式32声部增强明亮度与三效果合计为958拍。
        .MAX_SAMPLE_LATENCY_CYCLES(
            (USE_MODAL ?
                ((VOICES == 32) ? 926 :
                    ((VOICES > 16) ? (24 * VOICES + 36) : (56 * VOICES + 28))) :
                ((ENABLE_CONTROLS ? 6 : 4) + (ENABLE_GUITAR ? 1 : 0))) +
            (USE_BRIGHTNESS ? (ENHANCED_BRIGHTNESS ? 6 : 3) : 0) +
            (ENABLE_CHORUS ? 12 : 0) +
            (ENABLE_DELAY ? 5 : 0) +
            (ENABLE_REVERB ? 9 : 0)
        )
    ) u_b(
        .clk_in(sys_clk),
        .rst_n(sys_rst_n),
        .audio_enable(pa_audio_enable),
        .sample_data(output_sample_data),
        .sample_valid(output_sample_valid),
        .audio_ready(audio_ready),
        .sample_request(sample_request),
        .sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK),
        .i2s_lrclk(HP_WS),
        .i2s_sdata(HP_DIN),
        .pa_en(PA_EN),
        .frame_start(output_frame_start)
    );
endmodule
