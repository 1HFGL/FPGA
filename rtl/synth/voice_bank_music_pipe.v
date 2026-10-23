`timescale 1ns/1ps
// Shared piano v3 / classic-rock synthesis. 0=rock, 1=piano, latched on note-on.
// Serial compatibility: R(56*VOICES+27). Paired pipeline: R(24*VOICES+35).
// Paired mode overlaps the next voice reads with the previous voice envelope/mix.
// Both paths keep the same 48 components, fixed-point arithmetic and shared guitar FX.
// Guitar-only bus feeds distortion/cabinet; piano bypasses those effects.
module voice_bank_music_pipe #(
 parameter integer VOICES=16, MIX_SHIFT=3,
 parameter integer PAIRED=(VOICES>16),
 parameter [31:0] P_RELEASE=4096, G_RELEASE=2048,
 parameter MODE_ROM_FILE="rtl/rom/piano_v3_modes.mem",
 parameter MODE_EVEN_FILE="rtl/rom/modes_even.mem",
 parameter MODE_ODD_FILE="rtl/rom/modes_odd.mem",
 parameter SHAPER_ROM_FILE="rtl/rom/rock_v2_shaper.mem",
 parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem"
)(
 input wire clk,rst_n,sample_request,
 input wire [16:0] global_gain_q16,pitch_ratio_q16,
 input wire [VOICES-1:0] voice_gate,voice_retrigger,voice_instrument,
 input wire [VOICES*7-1:0] voice_note_flat,voice_velocity_flat,
 output wire [VOICES-1:0] voice_active,release_done,
 output reg [VOICES-1:0] instrument_active,
 output wire [VOICES*17-1:0] env_level_flat,
 output wire sounding,busy,
 output reg signed [15:0] sample_data,
 output reg sample_valid,sample_clipped,overrun
);
 function integer bits_for;
 input integer n; integer t;
 begin t=n-1;bits_for=0;while(t>0)begin bits_for=bits_for+1;t=t>>1;end
 if(bits_for==0)bits_for=1;end
 endfunction
 localparam IW=bits_for(VOICES), SW=IW+(PAIRED?5:6);
 localparam IDLE=0,RUN=1,ENV_GAIN=2,VELOCITY_GAIN=3,RAW=4,CROSS=5,VOICE_OUT=6,FX_START=7,FX_INTERP=8,FX_READ=9,FX_MUL1=10,FX_ADD1=11,FX_MUL2=12,FX_ADD2=13,MASTER_GAIN=14,MIX=15;
 reg [3:0] state;
 reg [IW-1:0] voice_index, output_voice_index, result_voice2;
 wire [IW-1:0] finish_voice=PAIRED?output_voice_index:voice_index;
 reg [5:0] issue_index;
 reg issued_all;
 reg signed [15:0] sine_rom[0:1023];
 reg [15:0] shaper_rom[0:1023];
 reg [31:0] phases[0:VOICES*(PAIRED?32:64)-1];
 reg [23:0] amplitudes[0:VOICES*(PAIRED?32:64)-1];
 initial begin
  $readmemh(SINE_ROM_FILE,sine_rom);
  $readmemh(SHAPER_ROM_FILE,shaper_rom);
 end
 reg [VOICES-1:0] gate_previous,pending,pending_preset,starts,initialized;
 reg [VOICES*7-1:0] notes,velocities;
 wire accept=sample_request && !busy;
 wire [VOICES-1:0] note_on=voice_gate & (voice_retrigger | pending | ~gate_previous);
 wire [VOICES-1:0] event_preset=(voice_retrigger & voice_instrument) |
  (~voice_retrigger & pending & pending_preset) |
  (~voice_retrigger & ~pending & voice_instrument);
 wire [VOICES-1:0] requested_preset=(note_on & event_preset) | (~note_on & instrument_active);
 wire [VOICES-1:0] envelope_active;
 reg signed [15:0] last_voice[0:VOICES-1];
 reg signed [16:0] correction[0:VOICES-1];
 reg [5:0] fade_left[0:VOICES-1];
 reg [15:0] lfsr[0:VOICES-1],bend[0:VOICES-1];
 reg signed [15:0] noise_sample[0:VOICES-1];
 genvar v;
 generate for(v=0;v<VOICES;v=v+1) begin:g_env
  instrument_env #(.G_ATTACK(16),.G_DECAY(1),.G_SUSTAIN(65536),.G_RELEASE(G_RELEASE),.S_ATTACK(64),.S_DECAY(1),.S_SUSTAIN(65536),.S_RELEASE(P_RELEASE)) u_env(
   .clk(clk),.rst(!rst_n),.sample_tick(accept),.gate(voice_gate[v]),
   .note_on(note_on[v]),.instrument(requested_preset[v]),.env_level(env_level_flat[v*17 +:17]),
   .active(envelope_active[v]),.state());
  assign voice_active[v]=rst_n && (voice_gate[v] || envelope_active[v] || last_voice[v]!=0);
  assign release_done[v]=!voice_active[v];
 end endgenerate
 assign busy=(state!=IDLE);

 // Tags follow RAM reads across voice boundaries. Each voice still sums in 22 bits.
 reg valid0,valid1,valid2,last0,last1,last2;
 reg [SW-1:0] slot0,slot1;
 wire [IW-1:0] read_voice=slot0[SW-1:(PAIRED?5:6)];
 reg [75:0] cfg0;
 reg [31:0] phase0,phase_next1;
 reg [23:0] amp0,amp1;
 reg signed [15:0] sine1,noise1;
 reg noise_flag1,muted1;
 reg [39:0] loss1;
 reg [48:0] pitch1;
 reg [16:0] gain_latched,ratio_latched;
 reg [33:0] voice_ratio_product;
 reg signed [39:0] master_product;
 wire signed [21:0] gained_mix=master_product[37:16];
 reg signed [32:0] product2;
 wire [31:0] phase_use0=starts[read_voice]?{cfg0[9:0],22'd0}:
                        (initialized[read_voice]?phase0:32'd0);
 wire [23:0] amp_use0=starts[read_voice]?{cfg0[41:26],8'd0}:
          ((initialized[read_voice] && envelope_active[read_voice])?amp0:24'd0);
 wire [16:0] decrement1={1'b0,loss1[39:24]}+(|loss1[23:0]);
 wire signed [17:0] modal_sample=product2[32:15];
 reg signed [21:0] mode_sum;
 reg signed [39:0] env_product;
 wire signed [15:0] enveloped=env_product[31:16];
 wire [6:0] velocity=velocities[finish_voice*7 +:7];
 wire signed [8:0] velocity_scale=(velocity==127)?9'sd128:$signed({2'b0,velocity});
 reg signed [24:0] velocity_product;
 reg signed [15:0] raw_sample;
 reg signed [23:0] cross_product;
 wire signed [24:0] blended=$signed(raw_sample)+($signed(cross_product)>>>6);
 wire signed [15:0] voice_result=!envelope_active[finish_voice]?16'sd0:
  starts[finish_voice]?last_voice[finish_voice]:
  (blended>32767?16'sh7fff:(blended < -32768?16'sh8000:blended[15:0]));
 // Up to 32 signed 16-bit voices fit 21 signed bits; keep 22 before saturation.
     reg signed [21:0] guitar_sum, piano_sum, piano_hold;
    reg signed [21:0] previous_input, guitar_target, interp_q, interp_step;
    reg [1:0] substep;
    wire [21:0] interp_abs=interp_q[21] ? -interp_q : interp_q;
    wire [9:0] shaper_address=(interp_abs>32767)?10'd1023:interp_abs[14:5];
    reg [15:0] shaper_q;
    reg shaper_negative;
    wire signed [16:0] shaped=shaper_negative ? -$signed({1'b0,shaper_q}) : $signed({1'b0,shaper_q});
    reg signed [24:0] cabinet_a, cabinet_b; // Q16.8, bounded by +/-16100*256
    wire signed [24:0] shaped_q8=$signed(shaped) <<< 8;
    wire signed [25:0] delta_a=$signed(shaped_q8)-$signed(cabinet_a);
    wire signed [25:0] delta_b=$signed(cabinet_a)-$signed(cabinet_b);
    reg signed [42:0] filter_product;
    localparam signed [16:0] CAB_ALPHA=17'sd10795;
    wire signed [43:0] next_a=$signed(cabinet_a)+($signed(filter_product)>>>16);
    wire signed [43:0] next_b=$signed(cabinet_b)+($signed(filter_product)>>>16);

 // At most 32 signed 16-bit dry voices plus a +/-16100 cabinet output,
 // even at MIX_SHIFT=0, fit 22 bits. Narrow explicitly after the 25-bit add.
 wire signed [24:0] mix_wide=$signed(piano_hold)+(cabinet_b >>> (8+MIX_SHIFT));
 wire signed [21:0] scaled_mix=mix_wide[21:0];
 assign sounding=rst_n && ((|voice_active) || cabinet_a!=0 || cabinet_b!=0 || sample_data!=0);
 function [15:0] noise_seed;
 input integer index;reg [31:0] seed_product;
 begin seed_product=index*32'h1234;noise_seed=16'h1ace^seed_product[15:0];end
 endfunction

 wire issuing=(PAIRED?(state!=IDLE):(state==RUN)) && !issued_all;
 wire [SW-1:0] issue_slot=PAIRED?{voice_index,issue_index[5:1]}:{voice_index,issue_index};
 wire signed [18:0] modal_pair=$signed(modal_sample)+$signed(PAIRED?modal_sample_b:18'sd0);
 reg [75:0] cfg0_b;
 wire signed [17:0] modal_sample_b;
 generate if(PAIRED)begin:g_odd
  reg [31:0] phases_b[0:VOICES*32-1];
  reg [23:0] amplitudes_b[0:VOICES*32-1];
  reg [31:0] phase0_b,phase_next1_b;
  reg [23:0] amp0_b,amp1_b;
  reg signed [15:0] sine1_b;
  reg [39:0] loss1_b;
  reg [48:0] pitch1_b;
  reg flag1_b,muted1_b;
  reg signed [32:0] product2_b;
  wire [31:0] use_phase=starts[read_voice]?{cfg0_b[9:0],22'd0}:(initialized[read_voice]?phase0_b:32'd0);
  wire [23:0] use_amp=starts[read_voice]?{cfg0_b[41:26],8'd0}:
   ((initialized[read_voice] && envelope_active[read_voice])?amp0_b:24'd0);
  wire [16:0] decrement={1'b0,loss1_b[39:24]}+(|loss1_b[23:0]);
  assign modal_sample_b=product2_b[32:15];
  // No state-RAM reset: initialized/starts protect reads after every reset.
  always @(posedge clk)begin
   if(issuing)begin phase0_b<=phases_b[issue_slot];amp0_b<=amplitudes_b[issue_slot];end
   if(valid0)begin
    sine1_b<=sine_rom[use_phase[31:22]];
    pitch1_b<=cfg0_b[73:42]*voice_ratio_product[32:16];
    loss1_b<=use_amp*cfg0_b[25:10];amp1_b<=use_amp;phase_next1_b<=use_phase;
    flag1_b<=cfg0_b[74];muted1_b<=(cfg0_b[41:26]==0);
   end
   if(valid1)begin
    product2_b<=muted1_b?33'sd0:(flag1_b?noise1:sine1_b)*$signed({1'b0,amp1_b[23:8]});
    phases_b[slot1]<=phase_next1_b+pitch1_b[47:16];
    amplitudes_b[slot1]<=(amp1_b<256 || amp1_b<=decrement)?24'd0:amp1_b-decrement;
   end
  end
 end else begin:g_no_odd
  assign modal_sample_b=18'sd0;
 end endgenerate
 // 75 payload bits plus one zero padding bit for 19 hex digits per ROM word.
 // Compact paired banks omit only the 16 unused slots per preset/note.
 // 256 records * 24 pairs; coefficient bytes and mode order are unchanged.
 wire [12:0] pair_address={instrument_active[voice_index],notes[voice_index*7+:7]}*13'd24+{8'd0,issue_index[5:1]};
 generate if(PAIRED)begin:g_pair_rom
  reg [75:0] even_rom[0:6143],odd_rom[0:6143];
  initial begin $readmemh(MODE_EVEN_FILE,even_rom);$readmemh(MODE_ODD_FILE,odd_rom);end
  always @(posedge clk)if(issuing)begin cfg0<=even_rom[pair_address];cfg0_b<=odd_rom[pair_address];end
 end else begin:g_serial_rom
  reg [75:0] mode_rom[0:16383];
  initial $readmemh(MODE_ROM_FILE,mode_rom);
  always @(posedge clk)if(issuing)cfg0<=mode_rom[{instrument_active[voice_index],notes[voice_index*7+:7],issue_index}];
 end endgenerate
 integer k;
 always @(posedge clk) begin
  if(!rst_n) begin
   state<=IDLE;voice_index<=0;output_voice_index<=0;result_voice2<=0;issue_index<=0;issued_all<=0;
   gate_previous<=0;pending<=0;pending_preset<=0;instrument_active<=0;starts<=0;initialized<=0;notes<=0;velocities<=0;
   sample_data<=0;sample_valid<=0;sample_clipped<=0;overrun<=0;
   valid0<=0;valid1<=0;valid2<=0;last0<=0;last1<=0;last2<=0;
   slot0<=0;slot1<=0;phase0<=0;amp0<=0;phase_next1<=0;amp1<=0;
   gain_latched<=65536;ratio_latched<=65536;voice_ratio_product<=0;master_product<=0;
   sine1<=0;noise1<=0;noise_flag1<=0;muted1<=0;loss1<=0;pitch1<=0;product2<=0;
   mode_sum<=0;guitar_sum<=0;piano_sum<=0;piano_hold<=0;
   previous_input<=0;guitar_target<=0;interp_q<=0;interp_step<=0;
   substep<=0;shaper_q<=0;shaper_negative<=0;cabinet_a<=0;cabinet_b<=0;filter_product<=0;env_product<=0;velocity_product<=0;raw_sample<=0;cross_product<=0;
   for(k=0;k<VOICES;k=k+1)begin
    last_voice[k]<=0;correction[k]<=0;fade_left[k]<=0;
    lfsr[k]<=noise_seed(k);noise_sample[k]<=0;bend[k]<=0;
   end
   // No bulk reset of state RAM; initialized masks locations until first note.
  end else begin
   sample_valid<=0;
   if(sample_request && busy)overrun<=1;
   if(accept) begin
    gain_latched<=global_gain_q16;ratio_latched<=pitch_ratio_q16;
    pending<=0;gate_previous<=voice_gate;starts<=note_on;initialized<=initialized|note_on;
    notes<=voice_note_flat;velocities<=voice_velocity_flat;instrument_active<=requested_preset;
    for(k=0;k<VOICES;k=k+1)begin
     noise_sample[k]<=lfsr[k];
     if(note_on[k])bend[k]<=requested_preset[k]?16'd0:16'd512;
     else bend[k]<=(bend[k]==0)?16'd0:bend[k]-(bend[k]>>9)-1'b1;
     lfsr[k]<={lfsr[k][14:0],lfsr[k][15]^lfsr[k][13]^lfsr[k][12]^lfsr[k][10]};
    end
   end else begin
    pending<=pending|voice_retrigger;
    for(k=0;k<VOICES;k=k+1)if(voice_retrigger[k])pending_preset[k]<=voice_instrument[k];
   end

   valid0<=0;valid1<=valid0;valid2<=valid1;
   if(issuing)begin
    // Compute one combined frequency ratio per voice, overlapping the first ROM read.
    // Center ratio reproduces inc + floor(inc*pluck_bend/65536) exactly.
    if(issue_index==0)voice_ratio_product<=ratio_latched*(17'd65536+{1'b0,bend[voice_index]});
    phase0<=phases[issue_slot];amp0<=amplitudes[issue_slot];
    slot0<=issue_slot;valid0<=1;last0<=(issue_index==(PAIRED?46:47));
    if(issue_index==(PAIRED?46:47))begin
     if(PAIRED && voice_index!=VOICES-1)begin voice_index<=voice_index+1'b1;issue_index<=0;end
     else issued_all<=1;
    end else issue_index<=issue_index+(PAIRED?6'd2:6'd1);
   end
   if(valid0)begin
    sine1<=sine_rom[phase_use0[31:22]];
    pitch1<=cfg0[73:42]*voice_ratio_product[32:16];
    loss1<=amp_use0*cfg0[25:10];amp1<=amp_use0;
    phase_next1<=phase_use0;slot1<=slot0;last1<=last0;
    noise1<=noise_sample[read_voice];noise_flag1<=cfg0[74];muted1<=(cfg0[41:26]==0);
   end
   if(valid1)begin
    product2<=muted1?33'sd0:(noise_flag1?noise1:sine1)*$signed({1'b0,amp1[23:8]});
    phases[slot1]<=phase_next1+pitch1[47:16];
    amplitudes[slot1]<=(amp1<256 || amp1<=decrement1)?24'd0:amp1-decrement1;
    last2<=last1;result_voice2<=slot1[SW-1:(PAIRED?5:6)];
   end
   if(valid2)begin
    mode_sum<=mode_sum+modal_pair;
    if(last2)begin state<=ENV_GAIN;output_voice_index<=result_voice2;end
   end
   case(state)
    IDLE:if(accept)begin voice_index<=0;issue_index<=0;issued_all<=0;mode_sum<=0;guitar_sum<=0;piano_sum<=0;state<=RUN;end
    RUN:begin end
    ENV_GAIN:begin env_product<=mode_sum*$signed({1'b0,env_level_flat[finish_voice*17 +:17]});
     if(PAIRED)mode_sum<=valid2?modal_pair:19'sd0; // first pair of the next voice arrives this cycle
     state<=VELOCITY_GAIN;end
    VELOCITY_GAIN:begin velocity_product<=enveloped*velocity_scale;state<=RAW;end
    RAW:begin raw_sample<=velocity_product[22:7];state<=CROSS;end
    CROSS:begin cross_product<=correction[finish_voice]*$signed({1'b0,fade_left[finish_voice]});state<=VOICE_OUT;end
    VOICE_OUT:begin
     if(starts[finish_voice])begin
      correction[finish_voice]<=$signed({last_voice[finish_voice][15],last_voice[finish_voice]})-$signed({raw_sample[15],raw_sample});
      fade_left[finish_voice]<=63;
     end else if(fade_left[finish_voice]!=0)fade_left[finish_voice]<=fade_left[finish_voice]-1'b1;
     last_voice[finish_voice]<=voice_result;
     if(instrument_active[finish_voice])piano_sum<=piano_sum+voice_result;
     else guitar_sum<=guitar_sum+voice_result;
     if(finish_voice==VOICES-1)state<=FX_START;
     else if(PAIRED)state<=RUN;
     else begin voice_index<=voice_index+1'b1;issue_index<=0;issued_all<=0;mode_sum<=0;state<=RUN;end
    end
                FX_START: begin
                    // Keep the original /4 bus gain; classic-rock drive and makeup are in the ROM.
                    // 22-bit interpolation prevents wraparound with 16 voices.
                    guitar_target<=guitar_sum >>> 2;
                    interp_step<=((guitar_sum >>> 2)-$signed(previous_input)) >>> 2;
                    interp_q<=previous_input; previous_input<=guitar_sum >>> 2;
                    piano_hold<=piano_sum >>> MIX_SHIFT;
                    substep<=0; state<=FX_INTERP;
                end
                FX_INTERP: begin
                    interp_q<=(substep==3)?guitar_target:interp_q+interp_step;
                    state<=FX_READ;
                end
                FX_READ: begin
                    shaper_q<=shaper_rom[shaper_address]; shaper_negative<=interp_q[21];
                    state<=FX_MUL1;
                end
                FX_MUL1: begin filter_product<=delta_a*CAB_ALPHA; state<=FX_ADD1; end
                FX_ADD1: begin
                    // Kill sub-LSB fixed-point residue once the input is zero.
                    cabinet_a<=(shaped==0 && next_a<256 && next_a> -256)?25'sd0:next_a[24:0];
                    state<=FX_MUL2;
                end
                FX_MUL2: begin filter_product<=delta_b*CAB_ALPHA; state<=FX_ADD2; end
                FX_ADD2: begin
                    cabinet_b<=(cabinet_a==0 && next_b<256 && next_b> -256)?25'sd0:next_b[24:0];
                    if(substep==3) state<=MASTER_GAIN;
                    else begin substep<=substep+1'b1; state<=FX_INTERP; end
                end

    MASTER_GAIN:begin
     master_product<=scaled_mix*$signed({1'b0,gain_latched});state<=MIX;
    end
    MIX:begin
     sample_data<=(gained_mix>32767)?16'sh7fff:((gained_mix < -32768)?16'sh8000:gained_mix[15:0]);
     sample_clipped<=(gained_mix>32767 || gained_mix < -32768);sample_valid<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
