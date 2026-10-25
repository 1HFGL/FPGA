"""隔离候选的严格差分测试；旧实现从固定Git提交读取，不在源码树保留副本。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = 'df0e894009e613dbf34011e63bc05653eb92843e'
REFERENCES = {
    'instrument_panel_ui': 'rtl/display/instrument_panel_ui.v',
    'instrument_display': 'rtl/display/instrument_display.v',
    'instrument_ui_map': 'rtl/display/instrument_ui_map.v',
    'touch_contact_tracker': 'rtl/control/touch_contact_tracker.v',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('tops', nargs='+')
parser.add_argument('--source-root', type=Path, default=ROOT)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--bin', type=Path, default=Path('C:/Library/modelsim/win64'))
parser.add_argument('--timeout', type=int, default=1200)
parser.add_argument('--mutation', choices=('none', 'digits_hold', 'frame_lag', 'touch_slot', 'map_edge'), default='none')
args = parser.parse_args()
source = args.source_root.resolve()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
references = []
original_hashes = {}
for module, relative in REFERENCES.items():
    original = subprocess.check_output(['git', 'show', BASE + ':' + relative], cwd=ROOT)
    original_hashes[relative] = hashlib.sha256(original).hexdigest()
    body = original.decode('utf-8')
    body = re.sub(r'\b' + module + r'\b', module + '_reference', body)
    if module in ('instrument_panel_ui', 'touch_contact_tracker'):
        body = re.sub(r'\binstrument_ui_map\b', 'instrument_ui_map_reference', body)
    if module == 'instrument_display':
        body = re.sub(r'\binstrument_panel_ui\b', 'instrument_panel_ui_reference', body)
    destination = out / (module + '_reference.v')
    destination.write_text(body, encoding='utf-8')
    references.append(destination)

sources = sorted(source.glob('rtl/**/*.v'))
if args.mutation != 'none':
    spec = {
        'digits_hold': ('rtl/display/instrument_panel_ui.v',
                        'else if(frame_commit)digits_q<=bend_digits_next;',
                        'else digits_q<=bend_digits_next;', 'FAIL frame bend hold'),
        'frame_lag': ('rtl/display/instrument_display.v',
                      '.pitch_bend_latest(state_latest[35:20])',
                      '.pitch_bend_latest(state_frame[35:20])', 'FAIL display frame digits'),
        'touch_slot': ('rtl/control/touch_contact_tracker.v',
                       'assign index_select[slot]=(index==slot);',
                       'assign index_select[slot]=(index==slot && slot!=0);', 'FAIL touch mux'),
        'map_edge': ('rtl/display/instrument_ui_map.v',
                     "x>=LEFT && x<RIGHT;\n            assign black_words",
                     "x>LEFT && x<RIGHT;\n            assign black_words", 'FAIL ui map'),
    }[args.mutation]
    relative, before, after, expected_failure = spec
    original = source / relative
    body = original.read_text(encoding='utf-8')
    if body.count(before) != 1:
        raise SystemExit('Mutation anchor not unique: ' + relative)
    mutant = out / ('mutation_' + original.name)
    mutant.write_text(body.replace(before, after), encoding='utf-8')
    sources = [mutant if f == original else f for f in sources]

def execute(exe, arguments, log):
    with log.open('w', encoding='utf-8') as stream:
        # ModelSim的Tcl/vopt会把Windows反斜杠当转义；库和文件路径统一用正斜杠。
        converted = [item.as_posix() if isinstance(item, Path) else str(item) for item in arguments]
        result = subprocess.run([str(args.bin / (exe + '.exe')), *converted],
                                cwd=source, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=args.timeout)
    return result.returncode, log.read_text(errors='replace')

for top in args.tops:
    matches = list((ROOT / 'verification/tb').rglob(top + '.v'))
    if len(matches) != 1:
        raise SystemExit('Expected unique test: ' + top)
    tb = matches[0]
    lib = out / (top + '_work')
    code, body = execute('vlib', [lib], out / (top + '_vlib.log'))
    if code:
        raise SystemExit(body[-3000:])
    manifest = {'base_commit': BASE, 'base_source_sha256': original_hashes,
                'top': top, 'mutation': args.mutation, 'flags': '-vlog01compat -pedanticerrors',
                'sha256': {str(f): hashlib.sha256(f.read_bytes()).hexdigest()
                           for f in [*sources, *references, tb, Path(__file__).resolve()]}}
    (out / (top + '_inputs.json')).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    flags = ['+define+UI_MAP_REFERENCE'] if top == 'tb_ui_map_equivalence' else []
    code, body = execute('vlog', ['-vlog01compat', '-pedanticerrors', '-work', lib,
                                 *flags, *sources, *references, tb], out / (top + '_compile.log'))
    if code or '** Error:' in body:
        raise SystemExit(body[-5000:])
    macro = out / (top + '.do')
    macro.write_text('onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\nrun -all\nquit -code 0 -f\n')
    code, body = execute('vsim', ['-c', '-lib', lib, top, '-l', out / (top + '.log'),
                                '-wlf', out / (top + '.wlf'), '-do', 'do {' + macro.as_posix() + '}'],
                         out / (top + '_console.log'))
    if args.mutation != 'none':
        if expected_failure not in body or 'PASS ' + top in body:
            raise SystemExit('Mutation not rejected by intended checker:\n' + body[-5000:])
        print('PASS negative ' + args.mutation + ': ' + expected_failure, flush=True)
    else:
        if code or re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body) or 'PASS ' + top not in body:
            raise SystemExit(body[-5000:])
        print('\n'.join(line.lstrip('# ') for line in body.splitlines() if 'PASS ' + top in line), flush=True)
