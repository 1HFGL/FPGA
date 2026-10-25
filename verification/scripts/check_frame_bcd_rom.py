"""从实际综合网表提取帧BCD的pROM，检查全部表项与真实CE保持行为。"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--netlist',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--bin',type=Path,default=Path('C:/Library/modelsim/win64'))
p.add_argument('--simlib',type=Path,default=Path('D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v'))
p.add_argument('--mutate',action='store_true')
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
netlist=a.netlist.resolve();text=netlist.read_text(encoding='utf-8')
instance=re.search(r'  pROM (\\g_frame_bend\.bend_bcd_rom\S+)\s+\([\s\S]*?\n\);',text)
if not instance:raise SystemExit('Expected inferred frame BCD pROM')
params=re.findall(r'(?m)^defparam '+re.escape(instance[1])+r' \.[^\n]+;',text)
body=instance[0]+'\n'+'\n'.join(params)
for required in ('.BIT_WIDTH=16;',".READ_MODE=1'b0;",'.CLK(pixel_clk)',
                 '.CE(commit)','.OCE(GND)','.RESET(GND)',
                 '.AD({GND,GND,bend_scaled[19:12],GND,GND,VCC,VCC})'):
    if required not in body:raise SystemExit('Unexpected inferred port/mode: '+required)
pages={int(i,16):int(v,16) for i,v in re.findall(r'\.INIT_RAM_([0-9A-F]{2})=256\x27h([0-9a-fA-F]+);',body)}
if not set(range(16)).issubset(pages):raise SystemExit('Incomplete initialized BCD range')
for value in range(256):
    actual=(pages[value//16]>>(16*(value%16)))&0xffff
    expected=((value//100)<<8)|(((value//10)%10)<<4)|(value%10)
    if actual!=expected:raise SystemExit('Bad synthesized INIT word '+str(value))
if a.mutate:
    old=re.search(r'\.INIT_RAM_0C=256\x27h([0-9a-fA-F]+);',body)[1]
    damaged=int(old,16)^(1<<(16*8))  # 只损坏第200项，检查器必须在该项拒绝。
    body=body.replace(".INIT_RAM_0C=256'h"+old+';',".INIT_RAM_0C=256'h"+format(damaged,'064x')+';')
tb=out/'tb_frame_bcd_physical.v'
tb.write_text('''`timescale 1ns/1ps
module tb_frame_bcd_physical;
reg pixel_clk=0,commit=0;
reg [19:0] bend_scaled=0;
wire GND=1'b0,VCC=1'b1;
wire [31:0] DO;
wire [9:0] \\g_frame_bend.digits_q ;
GSR GSR(.GSRI(1'b1));
always #5 pixel_clk=~pixel_clk;
'''+body+'''
integer i,reads=0,holds=0;
reg [9:0] expected;
function [9:0] model;
input integer n;
reg [3:0] h,t,o;
begin h=n/100;t=(n/10)%10;o=n%10;model={h[1:0],t,o};end
endfunction
initial begin
    repeat(3)@(negedge pixel_clk);
    for(i=0;i<256;i=i+1)begin
        @(negedge pixel_clk);bend_scaled={i[7:0],12'd0};commit=1;
        @(posedge pixel_clk);#1;expected=model(i);
        if(\\g_frame_bend.digits_q !==expected)begin
            $display("FAIL physical BCD index=%0d actual=%h expected=%h",i,\\g_frame_bend.digits_q ,expected);$stop;end
        reads=reads+1;
        @(negedge pixel_clk);commit=0;bend_scaled=~bend_scaled;
        repeat(2)begin
            @(posedge pixel_clk);#1;
            if(\\g_frame_bend.digits_q !==expected)begin $display("FAIL physical BCD CE hold");$stop;end
            holds=holds+1;
        end
    end
    $display("PASS tb_frame_bcd_physical: actual synthesized pROM reads=%0d CE holds=%0d",reads,holds);$finish;
end
initial begin #20000;$display("FAIL physical BCD timeout");$stop;end
endmodule
''',encoding='utf-8')
lib=out/'rom_work'
def run(exe,args,log):
    with log.open('w',encoding='utf-8') as f:
        result=subprocess.run([str(a.bin/(exe+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],
                              stdout=f,stderr=subprocess.STDOUT,timeout=120)
    return result.returncode,log.read_text(errors='replace')
for exe,args in [('vlib',[lib]),('vlog',['-work',lib,a.simlib]),
                 ('vlog',['-vlog01compat','-pedanticerrors','-work',lib,tb])]:
    code,log=run(exe,args,out/(exe+'.log'))
    if code or '** Error:' in log:raise SystemExit(log[-5000:])
macro=out/'run.do';macro.write_text('onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\nrun -all\nquit -code 0 -f\n')
code,log=run('vsim',['-c','-lib',lib,'tb_frame_bcd_physical','-l',out/'simulation.log',
                     '-wlf',out/'simulation.wlf','-do','do {'+macro.as_posix()+'}'],out/'console.log')
if a.mutate:
    if 'FAIL physical BCD index=200' not in log or 'PASS tb_frame_bcd_physical' in log:raise SystemExit('ROM mutation escaped checker')
else:
    if code or re.search(r'\bFAIL\b|\*\* (Error|Fatal):',log) or 'PASS tb_frame_bcd_physical' not in log:raise SystemExit(log[-5000:])
inputs={str(f.resolve()):hashlib.sha256(f.read_bytes()).hexdigest() for f in [netlist,a.simlib,tb,Path(__file__)]}
(out/'summary.json').write_text(json.dumps({'status':'MUTATION_REJECTED' if a.mutate else 'PASS',
    'initialized_words_checked':256,'physical_reads':256 if not a.mutate else None,
    'physical_ce_holds':512 if not a.mutate else None,'inputs':inputs},indent=2)+'\n')
print('PASS physical BCD ROM mutation rejected at index 200' if a.mutate else 'PASS physical BCD ROM: 256 INIT words, 256 vendor pROM reads, 512 CE holds')
