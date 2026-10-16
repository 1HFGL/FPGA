// Piano v3 / rock v2 UART performance: shared local/PC voices, fixed velocity 100.
module music_performance_core #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter integer VOICES=16,
    parameter [31:0] P_RELEASE=4096,
    parameter integer REQUEST_LEAD_HALF_EDGES=60
)(
    input wire sys_clk,sys_rst_n,input wire [1:0] Key_in,
    input wire uart_rx,output wire uart_tx,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    // Future C interface: synchronous complete pair, latest value, local wins a same-cycle UART request.
    input wire external_control_valid,input wire [6:0] external_volume,
    input wire [10:0] external_bend,output wire external_control_ready,
    output wire [6:0] monitor_volume,output wire signed [15:0] monitor_bend,
    output reg [12:0] monitor_keys,
    output wire monitor_guitar,monitor_valid,
    output wire signed [15:0] monitor_sample
);
    wire audio_ready,sample_request,sample_underrun;
    wire selected_preset,pc_preset,allocated_preset;
    wire uart_control_valid;wire [6:0] uart_volume,target_volume;wire [10:0] uart_bend,target_bend,bend_current;
    wire [16:0] global_gain_q16,pitch_ratio_q16;
    assign external_control_ready=audio_ready && external_bend<=1024;
    wire external_accept=external_control_valid && external_control_ready;
    music_controls u_controls(.clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
        .control_valid(external_accept || uart_control_valid),
        .control_volume(external_accept?external_volume:uart_volume),
        .control_bend(external_accept?external_bend:uart_bend),
        .target_volume(target_volume),.target_bend(target_bend),.gain_q16(global_gain_q16),
        .bend_current(bend_current),.pitch_ratio_q16(pitch_ratio_q16));
    assign monitor_volume=target_volume;
    wire signed [11:0] bend_offset=$signed({1'b0,target_bend})-12'sd512;
    assign monitor_bend=(target_bend==1024)?16'sd32767:($signed(bend_offset) <<< 6);
    wire [3:0] physical_timbre;
    wire [VOICES*4-1:0] voice_timbre_flat;
    wire [VOICES-1:0] voice_instrument;
    genvar vi;
    generate for(vi=0;vi<VOICES;vi=vi+1)begin:g_preset
        assign voice_instrument[vi]=voice_timbre_flat[vi*4];
    end endgenerate
    wire [1:0] key_press,key_release;
    wire pv,pr,pt,cv,cr,ct,av,ar,at,cancel,cancel_ready,ac,acr,session_ready;
    wire [7:0] ps,asrc;
    wire [6:0] pn,pvel,cn,cvel,an,avel;
    wire [VOICES-1:0] voice_gate,voice_active,voice_trigger,release_done;
    wire [VOICES*7-1:0] voice_note_flat,voice_velocity_flat;
    wire [VOICES*8-1:0] voice_source_flat;
    wire [31:0] steal_count;
    wire [5:0] voice_count,max_voice_count;
    wire signed [15:0] sample_data;
    wire sample_valid,sounding,sample_clipped;
    touch_or_key_if #(.KEY_COUNT(2),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_keys(
        .clk(sys_clk),.rst_n(audio_ready),.raw_key(Key_in),.key_level(),
        .key_press(key_press),.key_release(key_release));
    music_event_encoder #(.KEY_COUNT(2),.SOURCE_WIDTH(8)) u_key_events(
        .clk(sys_clk),.rst_n(audio_ready),.key_press(key_press),.key_release(key_release),
        .key_velocity_flat({7'd100,7'd100}),.input_timbre({3'd0,selected_preset}),
        .event_valid(pv),.event_ready(pr),.event_type(pt),.event_source_id(ps),
        .event_note(pn),.event_velocity(pvel),.event_timbre(physical_timbre));
    music_uart_protocol #(.CLKS_PER_BIT(UART_CLKS_PER_BIT),.WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .VOICES(VOICES)) u_uart(
        .clk(sys_clk),.rst_n(audio_ready),.rx(uart_rx),.tx(uart_tx),
        .event_valid(cv),.event_ready(cr),.event_type(ct),.event_note(cn),.event_velocity(cvel),
        .selected_preset(selected_preset),.event_preset(pc_preset),
        .control_ready(!external_accept),.target_volume(target_volume),.target_bend(target_bend),
        .control_valid(uart_control_valid),.control_volume(uart_volume),.control_bend(uart_bend),
        .cancel_valid(cancel),.cancel_ready(cancel_ready),.session_ready(session_ready),
        .voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count));
    music_uart_event_arbiter u_arbiter(.clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
        .physical_preset(physical_timbre[0]),.pc_preset(pc_preset),.event_preset(allocated_preset),
        .physical_valid(pv),.physical_ready(pr),.physical_type(pt),.physical_source(ps),
        .physical_note(pn),.physical_velocity(pvel),.pc_valid(cv),.pc_ready(cr),
        .pc_type(ct),.pc_note(cn),.pc_velocity(cvel),.cancel_valid(cancel),.cancel_ready(cancel_ready),
        .allocator_cancel(ac),.allocator_cancel_ready(acr),.event_valid(av),.event_ready(ar),
        .event_type(at),.event_source(asrc),.event_note(an),.event_velocity(avel));
    voice_allocator #(.VOICES(VOICES),.IDX_WIDTH(VOICES==16?4:2),.COUNT_WIDTH(6),.SOURCE_WIDTH(8),
        .MERGE_SAME_NOTE(0),.ENABLE_CANCEL(1),.ENABLE_PLAY_CONTROL(0),.CHECK_RELEASE_ID(0)) u_allocator(
        .clk(sys_clk),.rst_n(audio_ready),.event_valid(av),.event_ready(ar),.event_type(at),
        .event_source_id(asrc),.event_note(an),.event_velocity(at ? 7'd100 : 7'd0),.event_timbre({3'd0,allocated_preset}),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(8'd0),.expr_note(7'd0),
        .expr_pitch_bend(16'd0),.expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(release_done),.cancel_valid(ac),.cancel_ready(acr),.cancel_mask(8'h80),.cancel_value(8'h80),
        // This entry uses the music bank's release pulses; optional C sustain/ID inputs are disabled.
        .sustain_on(1'b0),.release_trigger_id_flat({VOICES*16{1'b0}}),
        .voice_trigger_id_flat(),.voice_key_down(),
        .voice_active(voice_active),.voice_gate(voice_gate),.voice_trigger(voice_trigger),
        .voice_source_id_flat(voice_source_flat),.voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(voice_timbre_flat),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),.voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),
        .voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count),
        .note_on_count(),.note_off_count(),.steal_pulse());
    wire overrun, core_busy;
        voice_bank_music_pipe #(.VOICES(VOICES),.MIX_SHIFT(3),.P_RELEASE(P_RELEASE)) u_bank(
            .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
            .global_gain_q16(global_gain_q16),.pitch_ratio_q16(pitch_ratio_q16),
            .voice_gate(voice_gate),.voice_retrigger(voice_trigger),.voice_instrument(voice_instrument),
            .voice_note_flat(voice_note_flat),.voice_velocity_flat(voice_velocity_flat),
            .release_done(release_done),.sounding(sounding),.sample_data(sample_data),
            .sample_valid(sample_valid),.env_level_flat(),.instrument_active(),.voice_active(),
            .sample_clipped(sample_clipped),.overrun(overrun),.busy(core_busy));
    assign monitor_guitar=~selected_preset;
    assign monitor_valid=sample_valid;
    assign monitor_sample=sample_data;
    integer mk;
    reg [6:0] monitor_note;
    always @* begin
        monitor_keys=0;monitor_note=0;
        for(mk=0;mk<VOICES;mk=mk+1) begin
            monitor_note=voice_note_flat[mk*7+:7];
            if(voice_gate[mk] && monitor_note>=60 && monitor_note<=72)
                monitor_keys[monitor_note-60]=1'b1;
        end
    end
    wire output_frame_start;
    // Wait for both pending and transmitting frames before disabling the amplifier.
    reg [1:0] drain_frames;
    always @(posedge sys_clk) begin
        if(!audio_ready) drain_frames<=0;
        else if(sounding) drain_frames<=3;
        else if(output_frame_start && drain_frames!=0) drain_frames<=drain_frames-1'b1;
    end
    synth_top #(.AUDIO_CLK_HZ(50000000),.SAMPLE_RATE_HZ(48000),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),
        .MAX_SAMPLE_LATENCY_CYCLES(56*VOICES+28)) u_b(
        .clk_in(sys_clk),.rst_n(sys_rst_n),.audio_enable(sounding || drain_frames!=0),.sample_data(sample_data),.sample_valid(sample_valid),
        .audio_ready(audio_ready),.sample_request(sample_request),.sample_underrun(sample_underrun),
        .frame_start(output_frame_start),.i2s_bclk(HP_BCK),.i2s_lrclk(HP_WS),.i2s_sdata(HP_DIN),.pa_en(PA_EN));
endmodule
