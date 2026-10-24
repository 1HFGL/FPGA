`timescale 1ns/1ps
// Shared original guitar distortion/cabinet and master gain AFTER both sums.
module modal_shared_output #(
 parameter integer MIX_SHIFT=3,
 parameter SHAPER_ROM_FILE="rtl/rom/rock_v2_shaper.mem"
)(
 input wire clk,rst_n,start,voices_sounding,
 input wire [16:0] gain_latched,
 input wire signed [21:0] piano_sum,guitar_sum,
 output wire sounding,
 output reg signed [15:0] sample_data,
 output reg sample_valid,sample_clipped
);
 localparam IDLE=0,FX_INTERP=8,FX_READ=9,FX_MUL1=10,FX_ADD1=11,FX_MUL2=12,FX_ADD2=13,MASTER_GAIN=14,MIX=15;
 reg [3:0] state;
 reg [15:0] shaper_rom[0:1023];
 initial $readmemh(SHAPER_ROM_FILE,shaper_rom);
 reg signed [39:0] master_product;
 wire signed [21:0] gained_mix=master_product[37:16];
 reg signed [21:0] piano_hold;
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
 assign sounding=rst_n && (voices_sounding || cabinet_a!=0 || cabinet_b!=0 || sample_data!=0);
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;sample_data<=0;sample_valid<=0;sample_clipped<=0;
   master_product<=0;piano_hold<=0;previous_input<=0;guitar_target<=0;interp_q<=0;interp_step<=0;
   substep<=0;shaper_q<=0;shaper_negative<=0;cabinet_a<=0;cabinet_b<=0;filter_product<=0;
  end else begin
   sample_valid<=0;
   case(state)
                IDLE: if(start) begin
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
