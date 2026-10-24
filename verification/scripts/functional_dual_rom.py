"""Simulation-only ROM view, checked against actual GW5A DPBs before integration tests.

Never included in the Gowin project. Produces the same two synchronous read ports
from canonical coefficients; vendor-vs-model exhaustive checks qualify its use.
"""
from pathlib import Path

def generate(root, output):
    words = [int(x,16) for x in (root/'rtl/rom/piano_v3_modes.mem').read_text().split()]
    packed=[]
    for record in range(256):
        for i in range(48):
            word=words[record*64+i]
            packed.append((((word>>42)&0x7fffffff)<<29)|(((word>>26)&0x1fff)<<16)|((word>>10)&0xffff))
    meta=[(words[p*8192+i]&1023)|((words[p*8192+i]>>74)<<10) for p in range(2) for i in range(48)]
    output.mkdir(parents=True,exist_ok=True)
    data=output/'functional_coefficients.hex';metadata=output/'functional_metadata.hex'
    data.write_text(''.join(f'{x:015x}\n' for x in packed),encoding='ascii')
    metadata.write_text(''.join(f'{x:03x}\n' for x in meta),encoding='ascii')
    model=output/'modal_coeff_rom_dual_functional.v'
    model.write_text('''// SIMULATION ONLY; never a synthesis input.
module modal_coeff_rom_dual(input wire clk,en_a,en_b,
 input wire [13:0] address_a,address_b,input wire [6:0] metadata_a,metadata_b,
 output wire [75:0] data_a,data_b);
 reg [59:0] memory[0:12287];reg [10:0] meta[0:95];
 reg [59:0] a,b;reg [10:0] ma,mb;
 initial begin
 $readmemh("DATA",memory);$readmemh("META",meta);
 end
 always @(posedge clk)begin
 if(en_a)begin a<=memory[address_a];ma<=(metadata_a<96)?meta[metadata_a]:11'd0;end
 if(en_b)begin b<=memory[address_b];mb<=(metadata_b<96)?meta[metadata_b]:11'd0;end
 end
 assign data_a={1'b0,ma[10],1'b0,a[59:29],3'd0,a[28:16],a[15:0],ma[9:0]};
 assign data_b={1'b0,mb[10],1'b0,b[59:29],3'd0,b[28:16],b[15:0],mb[9:0]};
endmodule
'''.replace('DATA',data.relative_to(root).as_posix()).replace('META',metadata.relative_to(root).as_posix()),encoding='ascii')
    return model,[data,metadata]
