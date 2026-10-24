`timescale 1ns/1ps
// Serial sixteen-voice scheduler, 48 modes/voice, derived from <=16 path.
// R0 snapshots inputs, R1 advances envelopes, R897 returns instrument buses.
// Group 1 retains global seeds 16..31; nonlinear processing happens only once.
module modal_voice_group16 #(
 parameter integer VOICE_OFFSET=0,
 parameter [31:0] P_RELEASE=4096,G_RELEASE=2048,
 parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem"
)(
 input wire clk,rst_n,sample_request,
 input wire [16:0] pitch_ratio_q16,
 input wire [15:0] voice_gate,voice_retrigger,voice_instrument,
 input wire [111:0] voice_note_flat,voice_velocity_flat,
 input wire [75:0] coefficient_data,
 output wire coefficient_enable,
 output wire [13:0] coefficient_address,
 output wire [6:0] coefficient_metadata,
 output wire [15:0] voice_active,release_done,
 output reg [15:0] instrument_active,
 output wire [271:0] env_level_flat,
 output wire busy,
 output reg sample_valid,overrun,
 output wire signed [21:0] piano_bus,guitar_bus
);
 localparam VOICES=16, IW=4, SW=10;
 localparam IDLE=0,RUN=1,ENV_GAIN=2,VELOCITY_GAIN=3,RAW=4,CROSS=5,VOICE_OUT=6,PREPARE=7;
 reg [3:0] state;
 reg [IW-1:0] voice_index;
 wire [IW-1:0] finish_voice=voice_index;
 reg [5:0] issue_index;
 reg issued_all;
 reg signed [15:0] sine_rom[0:1023];
 reg [31:0] phases[0:VOICES*64-1];
 reg [23:0] amplitudes[0:VOICES*64-1];
 initial begin
  $readmemh(SINE_ROM_FILE,sine_rom);
 end
 reg [VOICES-1:0] gate_previous,pending,pending_preset,starts,initialized;
 reg [VOICES*7-1:0] notes,velocities;
 wire accept=sample_request && !busy;
 reg env_tick;
 always @(posedge clk) if(!rst_n)env_tick<=0;else env_tick<=accept;
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
   .clk(clk),.rst(!rst_n),.sample_tick(env_tick),.gate(gate_previous[v]),
   .note_on(starts[v]),.instrument(instrument_active[v]),.env_level(env_level_flat[v*17 +:17]),
   .active(envelope_active[v]),.state());
  assign voice_active[v]=rst_n && (voice_gate[v] || envelope_active[v] || last_voice[v]!=0);
  assign release_done[v]=!voice_active[v];
 end endgenerate
 assign busy=(state!=IDLE);

 // Tags follow RAM reads across voice boundaries. Each voice still sums in 22 bits.
 reg valid0,valid1,valid2,last0,last1,last2;
 reg [SW-1:0] slot0,slot1;
 wire [IW-1:0] read_voice=slot0[SW-1:6];
 wire [75:0] cfg0=coefficient_data;
 reg [31:0] phase0,phase_next1;
 reg [23:0] amp0,amp1;
 reg signed [15:0] sine1,noise1;
 reg noise_flag1,muted1;
 reg [39:0] loss1;
 reg [48:0] pitch1;
 reg [16:0] ratio_latched;
 reg [33:0] voice_ratio_product;
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
 reg signed [21:0] guitar_sum,piano_sum;
 function [15:0] noise_seed;
 input integer index;reg [31:0] seed_product;
 begin seed_product=index*32'h1234;noise_seed=16'h1ace^seed_product[15:0];end
 endfunction

 reg [13:0] coefficient_base;
 wire [3:0] next_voice=voice_index+4'd1;
 wire issuing=(state==RUN) && !issued_all;
 wire [SW-1:0] issue_slot={voice_index,issue_index};
 assign coefficient_enable=issuing;
 assign coefficient_address=coefficient_base+{8'd0,issue_index};
 assign coefficient_metadata=(instrument_active[voice_index]?7'd48:7'd0)+{1'b0,issue_index};
 assign piano_bus=piano_sum;
 assign guitar_bus=guitar_sum;
 integer k;
 always @(posedge clk) begin
  if(!rst_n) begin
   state<=IDLE;voice_index<=0;issue_index<=0;issued_all<=0;
   gate_previous<=0;pending<=0;pending_preset<=0;instrument_active<=0;starts<=0;initialized<=0;notes<=0;velocities<=0;
   sample_valid<=0;overrun<=0;
   valid0<=0;valid1<=0;valid2<=0;last0<=0;last1<=0;last2<=0;
   slot0<=0;slot1<=0;phase0<=0;amp0<=0;phase_next1<=0;amp1<=0;
   ratio_latched<=65536;voice_ratio_product<=0;coefficient_base<=0;
   sine1<=0;noise1<=0;noise_flag1<=0;muted1<=0;loss1<=0;pitch1<=0;product2<=0;
   mode_sum<=0;guitar_sum<=0;piano_sum<=0;
   env_product<=0;velocity_product<=0;raw_sample<=0;cross_product<=0;
   for(k=0;k<VOICES;k=k+1)begin
    last_voice[k]<=0;correction[k]<=0;fade_left[k]<=0;
    lfsr[k]<=noise_seed(k+VOICE_OFFSET);noise_sample[k]<=0;bend[k]<=0;
   end
   // No bulk reset of state RAM; initialized masks locations until first note.
  end else begin
   sample_valid<=0;
   if(sample_request && busy)overrun<=1;
   if(accept) begin
    ratio_latched<=pitch_ratio_q16;
    pending<=0;gate_previous<=voice_gate;starts<=note_on;initialized<=initialized|note_on;
    notes<=voice_note_flat;velocities<=voice_velocity_flat;instrument_active<=requested_preset;
   end else begin
    pending<=pending|voice_retrigger;
    for(k=0;k<VOICES;k=k+1)if(voice_retrigger[k])pending_preset[k]<=voice_instrument[k];
   end

   // R1: fanout and state arithmetic start at a registered enable.
   // Inputs below are the complete R0 snapshot, never the live controls.
   if(env_tick)begin
    for(k=0;k<VOICES;k=k+1)begin
     noise_sample[k]<=lfsr[k];
     if(starts[k])bend[k]<=instrument_active[k]?16'd0:16'd512;
     else bend[k]<=(bend[k]==0)?16'd0:bend[k]-(bend[k]>>9)-1'b1;
     lfsr[k]<={lfsr[k][14:0],lfsr[k][15]^lfsr[k][13]^lfsr[k][12]^lfsr[k][10]};
    end
   end

   valid0<=0;valid1<=valid0;valid2<=valid1;
   if(issuing)begin
    // Compute one combined frequency ratio per voice, overlapping the first ROM read.
    // Center ratio reproduces inc + floor(inc*pluck_bend/65536) exactly.
    if(issue_index==0)voice_ratio_product<=ratio_latched*(17'd65536+{1'b0,bend[voice_index]});
    phase0<=phases[issue_slot];amp0<=amplitudes[issue_slot];
    slot0<=issue_slot;valid0<=1;last0<=(issue_index==47);
    if(issue_index==47)begin
     issued_all<=1;
    end else issue_index<=issue_index+6'd1;
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
    last2<=last1;
   end
   if(valid2)begin
    mode_sum<=mode_sum+modal_sample;
    if(last2)state<=ENV_GAIN;
   end
   case(state)
    IDLE:if(accept)state<=PREPARE;
    // Clear the frame accumulators from a registered state, not from the
    // sample-clock carry chain. RAM issue starts one cycle later, as before.
    PREPARE:begin
     voice_index<=0;issue_index<=0;issued_all<=0;
     mode_sum<=0;guitar_sum<=0;piano_sum<=0;
     coefficient_base<={instrument_active[0],notes[0+:7]}*14'd48;state<=RUN;
    end
    RUN:begin end
    ENV_GAIN:begin env_product<=mode_sum*$signed({1'b0,env_level_flat[finish_voice*17 +:17]});
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
     if(finish_voice==VOICES-1)begin sample_valid<=1;state<=IDLE;end
     else begin voice_index<=next_voice;issue_index<=0;issued_all<=0;mode_sum<=0;state<=RUN;
      coefficient_base<={instrument_active[next_voice],notes[next_voice*7+:7]}*14'd48;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
