"""Collect the verified HDMI dual-16 release without overwriting prior releases."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'verification/evidence/dual16'
PKG = ROOT / 'build/audition/dual16x2_j13_20261024'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return Path(path).read_text(encoding='utf-8-sig')


def timing(path):
    text = read(path)
    slacks = {}
    for section in ('3.1.1 Setup Paths Table', '3.1.2 Hold Paths Table',
                    '3.1.3 Recovery Paths Table', '3.1.4 Removal Paths Table', '3.2 Minimum Pulse Width Table'):
        table = text.split(section, 1)[1].strip().split('\n\n', 1)[0]
        slacks[section] = min(float(x) for x in re.findall(r'(?m)^\s*\d+\s+(-?\d+\.\d+)\s+', table))
        assert slacks[section] >= 0, (section, slacks[section])
    return slacks, len(re.findall(r'(?m)^TC_\w+ Actived ', text))


def resources(path):
    text = read(path)
    result = {}
    for name in ('Logic', 'Register', 'BSRAM', 'DSP'):
        match = re.search(r'(?m)^\s*' + name + r'\s*\|\s*([\d.]+)/(\d+)', text)
        assert match, name
        result[name] = {'used': float(match[1]), 'available': int(match[2])}
        assert float(match[1]) <= int(match[2])
    return result


def main():
    hd = json.loads(read(ROOT / 'build/hdmi/implementation_check.json'))
    assert hd['status'] == 'PASS_CURRENT_CONSTRAINTS_ONLY', hd['errors']
    # Exact bytes of the previous 10/23 release must survive this optimization.
    old_manifest = json.loads(read(ROOT / 'verification/evidence/poly32/files_sha256.json'))
    for path, digest in old_manifest.items():
        assert sha(ROOT / path) == digest, path
    OUT.mkdir(parents=True, exist_ok=True)
    PKG.mkdir(parents=True, exist_ok=True)
    # This release is HDMI-only. Local retired files are not release inputs.
    builds = {}
    for name, folder, stem, normalized in (
        ('hdmi', 'build/hdmi', 'piano_hdmi', 'timing.txt'),):
        source_dir = ROOT / folder
        for line in read(source_dir / 'build_inputs.txt').splitlines():
            match = re.fullmatch(r'([a-fA-F0-9]{64})  (.+)', line)
            if match:
                assert sha(match[2]) == match[1].lower(), match[2]
        assert 'Bitstream generation completed' in read(source_dir / 'build.log')
        slacks, constraints = timing(source_dir / normalized)
        assert constraints == 17
        usage = resources(source_dir / f'{stem}.rpt.txt')
        # A merely nonnegative setup result is not an optimization of 0.000ns.
        assert slacks['3.1.1 Setup Paths Table'] > 0
        assert usage['BSRAM']['used'] < 117
        source = ROOT / f'projects/{name}/impl/pnr/{stem}.fs'
        target = PKG / f'{name}_dual16x2_j13.fs'
        if target.exists():
            assert sha(target) == sha(source), 'Use a new release directory for a different bitstream'
        else:
            shutil.copy2(source, target)
        builds[name] = {'file': target.relative_to(ROOT).as_posix(), 'sha256': sha(target),
                        'resources': usage, 'slacks_ns': slacks, 'active_constraints': constraints,
                        'sample_cache_cycles': 955}
        for original, dest in [('build_inputs.txt', 'inputs.txt'), ('build.log', 'build.log'),
                               (normalized, 'timing.txt'), (f'{stem}.rpt.txt', 'pnr.txt')]:
            shutil.copy2(source_dir / original, OUT / f'{name}_{dest}')
        shutil.copy2(ROOT / f'projects/{name}/impl/gwsynthesis/{stem}_syn_rsc.xml', OUT / f'{name}_synthesis_resources.xml')
    shutil.copy2(ROOT / 'build/hdmi/implementation_check.json', OUT / 'hdmi_implementation_check.json')
    tests = {}
    for tag in ('tb_dual16_rom', 'tb_dual16_core', 'tb_dual16_snapshot', 'tb_dual16_hdmi', 'tb_dual16_uart',
                'tb_event_encoder_equivalence', 'tb_final_modal_adapter', 'tb_final_env_alignment'):
        directory = ROOT / 'build/regression/final'
        text = read(directory / f'{tag}_console.log')
        assert 'PASS ' + tag in text and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):', text), tag
        tests[tag] = [line.strip('# ') for line in text.splitlines() if 'PASS' in line]
        inputs = json.loads(read(directory / f'{tag}_inputs.json'))
        for name, digest in inputs['sha256'].items():
            source = Path(name)
            if not source.is_absolute():
                source = ROOT / source
            assert sha(source) == digest, (tag, name)
        for source, dest in [(f'{tag}_console.log', f'{tag}.log'), (f'{tag}_inputs.json', f'{tag}_inputs.json')]:
            shutil.copy2(directory / source, OUT / dest)
    for filename in ('strict_inputs.txt', 'strict_compile.log'):
        shutil.copy2(ROOT / 'build/regression/strict' / filename, OUT / filename)
    effect_reference = json.loads(read(ROOT / 'build/regression/dual16/integration_reference.json'))
    shutil.copy2(ROOT / 'build/regression/dual16/integration_reference.json', OUT / 'integration_reference.json')
    shutil.copy2(ROOT / 'build/dual16_preservation.json', OUT / 'preservation.json')
    manifest = {'date': '2026-10-24', 'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'branch': 'cleanup/expression-brightness', 'published': False, 'programmed': False,
                'delivery_targets': ['hdmi'],
                'publication_note': 'Pre-push build snapshot; published=false is not live GitHub branch status',
                'architecture': 'two independent serial 16-voice engines; physical dual-port ROM; one shared output/FX chain',
                'voices': 32, 'sample_rate': 48000, 'core_cycles': 925, 'minimum_prepare_cycles': 976,
                'coefficient_rom_bsram': 45, 'coefficient_words_exact': 12288,
                'fixed_effects': ['chorus', 'delay', 'reverb'], 'runtime_fx_and_diagnostics': False,
                'builds': builds, 'tests': tests, 'effect_reference': effect_reference,
                'prior_release_files_preserved': len(old_manifest),
                'source_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in
                                  [*ROOT.glob('rtl/**/*.v'), ROOT / 'model/pack_dual16_rom.py', Path(__file__).resolve()]},
                'strict_verilog_2001_files': len(re.findall(r'(?m)^[A-F0-9]{64}  ', read(ROOT / 'build/regression/strict/strict_inputs.txt'))),
                'limits': ['Current constraints only; PR1014 and full DAC external timing remain open',
                           'No board programming, physical listening or analog end-to-end latency verification',
                           'USB touch input remains unconnected'],
                'vendor_simulation_warnings': 'DPB BIT_WIDTH=4 triggers four vopt-2697 warnings per primitive in inactive 8/16-bit vendor branches; full real-primitive ROM reads passed; vendor library unchanged'}
    for path in (OUT / 'summary.json', PKG / 'manifest.json'):
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    shutil.copy2(ROOT / 'docs/polyphony32.md', PKG / '试听说明.md')
    release_files = [p for p in OUT.glob('*') if not p.name.startswith('piano_')]
    release_files += [PKG / 'hdmi_dual16x2_j13.fs', PKG / 'manifest.json', PKG / '试听说明.md']
    files = {p.relative_to(ROOT).as_posix(): sha(p) for p in release_files
             if p.is_file() and p.name != 'files_sha256.json'}
    (OUT / 'files_sha256.json').write_text(json.dumps(files, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(builds, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
