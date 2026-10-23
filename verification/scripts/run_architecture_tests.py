"""本轮局部架构修改的差分测试；旧参考仅由Git临时还原到build。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/regression/architecture'
BIN = Path('C:/Library/modelsim/win64')
VENDOR = Path('D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v')
BASELINE_REVISION = '922e059d14fdf09c07c80f3562ffd678fd23dac8'
REFERENCES = {'rtl/synth/voice_bank_music_pipe.v': 'voice_bank_music_pipe',
              'rtl/display/instrument_panel_ui.v': 'instrument_panel_ui'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(revision=BASELINE_REVISION):
    target = OUT / 'baseline.json'
    if target.exists():
        raise SystemExit('Baseline already exists; refusing to replace the comparison source')
    OUT.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', revision+'^{commit}'], cwd=ROOT, text=True).strip()
    protected = [p for folder in ('verification/tb', 'upstream', 'boards')
                 for p in (ROOT / folder).rglob('*') if p.is_file()]
    protected += list((ROOT / 'projects').glob('*/process_config.json'))
    protected += [ROOT / '.vscode/config.json']
    data = dict(revision=revision,
                protected_sha256={p.relative_to(ROOT).as_posix(): sha(p) for p in protected},
                rtl_sha256={p.relative_to(ROOT).as_posix(): sha(p) for p in (ROOT / 'rtl').rglob('*.v')})
    for name, module in REFERENCES.items():
        original = subprocess.check_output(['git', 'show', revision + ':' + name], cwd=ROOT)
        text = original.decode('utf-8-sig')
        text, count = re.subn(r'\bmodule\s+' + module + r'\b',
                             'module ' + module + '_original', text, count=1)
        if count != 1:
            raise SystemExit('Reference module declaration missing')
        (OUT / (module + '_original.v')).write_text(text, encoding='utf-8')
    # 仅在工作区仍为旧RTL时保存旧实现报告，不能把优化后的报告当作旧基线。
    old_rtl = all((ROOT/name).read_bytes().replace(b'\r\n',b'\n') ==
                  subprocess.check_output(['git','show',revision+':'+name],cwd=ROOT).replace(b'\r\n',b'\n')
                  for name in REFERENCES)
    if old_rtl:
        for project, base in [('hdmi', 'piano_hdmi'), ('piano', 'piano_performance')]:
            for suffix in ('.rpt.txt', '_tr_content.html', '.fs'):
                path = ROOT / 'projects' / project / 'impl/pnr' / (base + suffix)
                if path.exists():
                    shutil.copy2(path, OUT / ('baseline_' + base + suffix))
    target.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    print('PASS architecture baseline saved: ' + revision)


def run(top, mutation=False):
    OUT.mkdir(parents=True, exist_ok=True)
    tag = top + ('_mutation' if mutation else '')
    lib = (OUT / (tag + '_work')).relative_to(ROOT).as_posix()
    sources = sorted((ROOT / 'rtl').rglob('*.v'))
    if mutation:
        if top != 'tb_modal_parameter_rom':
            raise SystemExit('ROM mutation requires tb_modal_parameter_rom')
        original = ROOT / 'rtl/synth/modal_parameter_rom.v'
        body = original.read_text(encoding='utf-8')
        before = 'address[3:0]'
        if body.count(before) != 1:
            raise SystemExit('Ambiguous ROM mutation')
        changed = OUT / 'modal_parameter_rom_mutation.v'
        changed.write_text(body.replace(before, "(address[3:0] ^ 4'd1)"), encoding='utf-8')
        sources = [changed if p == original else p for p in sources]
    tb = ROOT / 'verification/tb/integration' / (top + '.v')
    extra = [OUT / (name + '_original.v') for name in REFERENCES.values()]
    if top == 'tb_architecture_startup':
        extra.append(VENDOR)
    inputs = [*sources, *extra, tb, *ROOT.glob('rtl/rom/*.mem'), Path(__file__).resolve(),
              OUT/'baseline.json', ROOT/'model/pack_modal_rom.py']
    (OUT / (tag + '_inputs.json')).write_text(json.dumps({
        'flags': '-vlog01compat -pedanticerrors',
        'sha256': {str(p): sha(p) for p in inputs}}, indent=2), encoding='utf-8')

    def command(exe, args, name, expected_failure=False):
        log = OUT / (tag + '_' + name + '.log')
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run([str(BIN / (exe + '.exe')), *args], cwd=ROOT,
                                    stdout=stream, stderr=subprocess.STDOUT)
        body = log.read_text(errors='replace')
        if not expected_failure and (result.returncode or re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body)):
            raise SystemExit(body[-5000:])
        return body

    if not (ROOT / lib / '_info').exists():
        command('vlib', [lib], 'vlib')
    # 厂商库单独按厂商语言选项编译，手写RTL始终使用严格Verilog-2001。
    command('vlog', ['-vlog01compat', '-pedanticerrors', '-work', lib,
                     *map(str, [*sources, *[p for p in extra if p != VENDOR], tb])], 'compile')
    if VENDOR in extra:
        command('vlog', ['-work', lib, str(VENDOR)], 'vendor')
    body = command('vsim', ['-c', '-lib', lib, top, '-wlf', str(OUT / (tag + '.wlf')),
                            '-do', 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f'],
                   'console', mutation)
    marker = 'FAIL modal ROM value' if mutation else 'PASS ' + top
    if marker not in body or (mutation and 'PASS ' + top in body):
        raise SystemExit('Missing expected checker: ' + marker + '\n' + body[-2000:])
    print('\n'.join(line for line in body.splitlines() if marker in line), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tops', nargs='*')
    parser.add_argument('--snapshot', action='store_true')
    parser.add_argument('--baseline-revision', default=BASELINE_REVISION)
    parser.add_argument('--mutation', action='store_true')
    args = parser.parse_args()
    if args.snapshot:
        snapshot(args.baseline_revision)
    for top in args.tops:
        run(top, args.mutation)
