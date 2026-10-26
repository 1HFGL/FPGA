"""Audit direct native-clock STA in a design with identical-edge routing aliases.

Does not add/subtract margins from reported values. Checks original-budget paths,
exceptions, clock identity and PLL propagation in the actual routed report.
"""
import re

NATIVE=('sys_clk','hdmi_pixel','hdmi_serial','usb_clk','usb_pin_clk')
ALIASES={'route_sys':'sys_clk','route_pixel':'hdmi_pixel','route_usb':'usb_clk','route_pin':'usb_pin_clk'}
TARGETS={'Setup':2.0,'Hold':.4,'Recovery':.6,'Removal':.4}

IO_PORTS=('HP_BCK','HP_DIN','HP_WS','PA_EN','ble_tx','knob_scl','knob_sda','uart_tx','usb_touch_dm','usb_touch_dp')
def native_command(kind,exception=False,io_ports=IO_PORTS):
 clocks=' '.join(NATIVE)
 destination=' -to [get_ports {'+' '.join(io_ports)+'}]' if exception=='io' else f' -to_clock [get_clocks {{{clocks}}}]'
 return ('report_exceptions' if exception else 'report_timing')+' -'+kind.lower()+f' -from_clock [get_clocks {{{clocks}}}]'+destination+' -max_paths 25 -max_common_paths 1'

LFSR='u_core/g_modal.u_bank/u_modal/g_dual.u_engine/u_group1/lfsr_lfsr_RAMREG_1_G'
HOLD_PLACEMENT_REPORT='report_timing -hold -from_clock [get_clocks {sys_clk}] -to_clock [get_clocks {sys_clk}] -from [get_regs {'+LFSR+'[113]_s1}] -to [get_regs {'+LFSR+'[114]_s1}] -max_paths 1 -max_common_paths 1'

def audit(text,board_sdc,objectives_sdc,full_design=True):
 errors=[]
 def check(ok,message):
  if not ok:errors.append(message)
 clock_section=text.split('2.2 Clock Summary')[-1].split('2.3 Max Frequency Summary')[0]
 clocks={}
 for m in re.finditer(r'(?m)^\s*\d+\s+(\w+)\s+(Base|Generated)\s+([\d.]+)\s+([\d.]+)MHz\s+([\d.]+)\s+([\d.]+)\s+(.+)$',clock_section):
  clocks[m[1]]={'type':m[2],'period':float(m[3]),'frequency':float(m[4]),'rise':float(m[5]),'fall':float(m[6]),'source_master_object':m[7].split()}
 check(set(clocks)==set(NATIVE)|set(ALIASES),'Native/alias clock inventory differs')
 freqs={'sys_clk':50.,'hdmi_pixel':49.,'hdmi_serial':245.,'usb_clk':48.,'usb_pin_clk':48.}
 for name,freq in freqs.items():
  c=clocks.get(name,{})
  check(c.get('frequency')==freq and abs(c.get('period',-999)-1000/freq)<=.001 and c.get('rise')==0 and abs(c.get('fall',-999)-500/freq)<=.001,'Native clock period/phase differs: '+name)
 for alias,native in ALIASES.items():
  check(clocks.get(alias)==clocks.get(native),'Alias does not exactly match native edges/source: '+alias)
 active=[]
 for m in re.finditer(r'(?m)^\s*TC_\w+\s+Actived\s+(.+)$',text):active.append(' '.join(m[1].split()))
 def commands(source):return [' '.join(x.split()) for x in source.splitlines() if x.strip() and not x.lstrip().startswith(('#','//'))]
 expected=commands(board_sdc)+commands(objectives_sdc)
 check(len(active)==len(expected) and sorted(active)==sorted(expected),'Active constraints do not exactly match original constraints plus documented objectives/reports')
 check(not any('set_clock_uncertainty' in x for x in commands(board_sdc)),'Unexpected native uncertainty in board contract')
 check(not any(x.startswith(('set_false_path','set_multicycle_path','set_clock_groups')) for x in commands(objectives_sdc)),'Routing objectives introduce a timing exception')
 check(all('route_' in x for x in commands(objectives_sdc) if x.startswith('set_clock_uncertainty')),'Uncertainty applied to a native clock')
 for command in commands(objectives_sdc):
  if command.startswith(('set_max_delay','set_min_delay')):
   m=re.search(r'-from \[get_clocks \{([^}]+)\}\]',command)
   check(bool(m) and all(name in ALIASES for name in m[1].split()),'Additional min/max delay is not confined to routing alias launch clocks')
 parts={}
 for part in text.split('Report Command:')[1:]:
  command=part.splitlines()[0].strip()
  if command.startswith(('report_timing','report_exceptions')):
   check(command not in parts,'Duplicate or ambiguous timing report command: '+command)
   parts[command]=part
 io_ports=tuple(sorted({port for line in commands(board_sdc) if line.startswith(('set_max_delay','set_min_delay')) for group in re.findall(r'-to \[get_ports \{([^}]+)\}\]',line) for port in group.split()}))
 check(bool(io_ports),'Missing original I/O timing budgets')
 expected_report_commands={native_command(k,e,io_ports) for k in TARGETS for e in (False,True,'io')}
 if HOLD_PLACEMENT_REPORT in commands(objectives_sdc):expected_report_commands.add(HOLD_PLACEMENT_REPORT)
 check(set(parts)==expected_report_commands,'Native report coverage command set differs')
 for command,part in parts.items():
  if command.startswith('report_exceptions'):
   for constraint in re.split(r'Timing Path Constraint\[\d+\]:',part)[1:]:
    if 'route_' in constraint.splitlines()[0]:
     check(not re.search(r'(?m)^Slack\s*:',constraint),'Routing-only min/max delay leaked into native exception coverage')
 if HOLD_PLACEMENT_REPORT in expected_report_commands:
  target=parts.get(HOLD_PLACEMENT_REPORT,'')
  check(bool(re.search(r'(?m)^From\s*:\s*'+re.escape(LFSR+'[113]_s1')+r'\s*$',target)) and bool(re.search(r'(?m)^To\s*:\s*'+re.escape(LFSR+'[114]_s1')+r'\s*$',target)),'Targeted short-path report missing or changed')
 result={};paths={}
 for kind,target in TARGETS.items():
  entries=[]
  for is_exception in (False,True,'io'):
   part=parts.get(native_command(kind,is_exception,io_ports),'')
   values=re.findall(r'(?m)^Slack\s*:\s*(-?[\d.]+)',part)
   if not is_exception:check(bool(values),'Missing native '+kind+' paths')
   for block in part.split('Path Summary:')[1:]:
    fields={k:m[1].strip() for k in ('Slack','From','To','Launch Clk','Latch Clk') if (m:=re.search(r'(?m)^'+k+r'\s*:\s*(.+)$',block))}
    canonical_clocks={}
    for ck in ('Launch Clk','Latch Clk'):
     name=fields.get(ck,'').split(':')[0]
     # Separate native clock-to-clock and native-to-I/O reports retain every
     # original budget while excluding aliases at either clock endpoint.
     check(name in NATIVE or (is_exception=='io' and ck=='Latch Clk' and name=='N/A'),
           'Filtered report contains an omitted/alias clock: '+str(fields))
     canonical_clocks[ck]=name
    fields['equivalent_native_clocks']=canonical_clocks
    # Gowin already charges 35ps between related PLL outputs in the native
    # baseline (e.g. pixel -> serializer). Preserve that native charge. Reject
    # leakage of the additional 2.1ns/.5ns routing objectives into this report.
    uncertainty=[float(v) for v in re.findall(r'(?m)^\s*[-\d.]+\s+([-\d.]+)\s+tUnc(?:\s|$)',block)]
    same_clock=canonical_clocks['Launch Clk']==canonical_clocks['Latch Clk']
    check(all(abs(v)<=.035001 and (not same_clock or abs(v)<.000001) for v in uncertainty),'Native path unexpectedly contains routing uncertainty')
    fields['native_tool_uncertainty_ns']=uncertainty
    if any(canonical_clocks[ck] in NATIVE[1:] for ck in ('Launch Clk','Latch Clk')):
     pll_delays=[float(v) for v in re.findall(r'(?m)^\s*[-\d.]+\s+([-\d.]+)\s+tCL\s+.*u_pll/CLKOUT[01]',block)]
     check(bool(pll_delays) and all(v>0 for v in pll_delays),'Generated-clock path omits positive PLL propagation: '+str(fields))
    fields['exception']=is_exception;entries.append(fields)
  numeric=[float(x['Slack']) for x in entries if 'Slack' in x]
  result[kind]=min(numeric) if numeric else None
  check(result[kind] is not None and result[kind]>=target,f'Native {kind} below {target:.3f} ns: {result[kind]}')
  paths[kind]=entries
 pulse=text.split('3.2 Minimum Pulse Width Table')[-1].split('3.3 Timing Report')[0]
 values=[float(x) for x in re.findall(r'(?m)^\s*\d+\s+(-?[\d.]+)\s',pulse)]
 result['Pulse']=min(values) if values else None
 check(bool(values) and min(values)>=0,'Missing or negative pulse width margin')
 return {'status':'FAIL' if errors else 'PASS_NATIVE_TARGETS','errors':errors,'native_slacks_ns':result,
         'targets_ns':TARGETS,'clocks':clocks,'active_constraints':len(active),'native_report_paths':paths,
         'method':'Direct vendor STA under the original native clock and I/O budgets, no arithmetic margin reconstruction',
         'extra_models':'Identical edges on the same physical clock nodes, used only to apply stricter routing objectives'}
