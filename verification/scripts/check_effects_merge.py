"""汇总本轮实际执行证据，不运行/修改队友TB，不生成硬件验收结论。"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'build/merge_effects_20261022'
FINAL = ROOT / 'build/regression/final'
OUT = ROOT / 'verification/evidence/merge_effects'
UPSTREAM = 'f314bc066a428b7f43b19c0c8fa1586e6a98dc24'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text(encoding='utf-8-sig')


def check_manifest(manifest):
    for name, expected in manifest.items():
        path = Path(name)
        if not path.is_absolute():
            path = ROOT / path
        assert digest(path) == expected.lower(), ('stale input', name)


cases = ['tb_effects_hdmi', 'tb_effects_pa', 'tb_touch_brightness',
         'tb_simple_ui_map', 'tb_simple_ui_states', 'tb_display_feedback',
         'tb_simple_display_frames', 'tb_final_wave_envelope', 'tb_touch_contact_tracker',
         'tb_delay_chorus', 'tb_room_reverb', 'tb_final_env_alignment', 'tb_final_modal_adapter',
         'tb_touch_hdmi_audio_dry', 'tb_hdmi_octaves_dry', 'tb_performance_octaves_dry']
passed = {}
artifacts = {}
for case in cases:
    log = FINAL / (case + '_console.log')
    text = read(log)
    marker = 'PASS ' + case.removesuffix('_dry') + ':'
    lines = [line for line in text.splitlines() if marker in line]
    assert len(lines) == 1 and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):', text), case
    manifest_path = FINAL / (case + '_inputs.json')
    manifest = json.loads(read(manifest_path))
    check_manifest(manifest['sha256'])
    passed[case] = {'result': lines[0].removeprefix('# '), 'mode': manifest['mode']}
    for path in (log, manifest_path):
        artifacts[path.relative_to(ROOT).as_posix()] = digest(path)

strict = ROOT / 'build/regression/strict'
assert 'Errors: 0, Warnings: 0' in read(strict / 'strict_compile.log')
strict_inputs = dict((m[2], m[1]) for line in read(strict / 'strict_inputs.txt').splitlines()
                     if (m := re.fullmatch(r'([A-Fa-f0-9]{64})  (.+)', line)))
check_manifest(strict_inputs)
baseline = json.loads(read(WORK / 'baseline_inputs.json'))
protected = [item for item in baseline if re.match(
    r'^(verification/tb/|upstream/|boards/|rtl/rom/|rtl/synth/|rtl/audio/|rtl/control/|'
    r'projects/hdmi/process_config.json$|\.vscode/config.json$)', item['path'])]
check_manifest({item['path']: item['sha256'] for item in protected})

# Git文本可能按平台转换换行；所有队友TB及新增效果器与原提交比较规范化文本，
# 另用上面的合并前清单验证本地既有受保护文件逐字节未变。
names = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', UPSTREAM,
    'verification/tb', 'upstream/fpga_interaction/tb', 'rtl/audio/chorus_effect.v',
    'rtl/audio/echo_delay.v', 'rtl/audio/room_reverb.v'], cwd=ROOT).decode().splitlines()
for name in names:
    original = subprocess.check_output(['git', 'show', UPSTREAM + ':' + name], cwd=ROOT)
    assert (ROOT / name).read_bytes().replace(b'\r\n', b'\n') == original.replace(b'\r\n', b'\n'), name
for ref in ('origin/master', 'origin/cleanup/expression-brightness'):
    subprocess.run(['git', 'merge-base', '--is-ancestor', ref, 'HEAD'], cwd=ROOT, check=True)

negative = read(WORK / 'negative_console.log')
assert 'FAIL PA muted inside wet tail' in negative and 'PASS tb_effects_pa' not in negative
reset = ROOT / 'build/regression/hdmi_reset'
assert 'PASS tb_review_hdmi_reset_recovery' in read(reset / 'normal_console.log')
assert 'FAIL HDMI reset word alignment epoch=1' in read(reset / 'negative_console.log')
implementation = json.loads(read(ROOT / 'build/hdmi/implementation_check.json'))
assert implementation['status'] == 'PASS_CURRENT_CONSTRAINTS_ONLY' and not implementation['errors']
check_manifest({item['path']: item['sha256'] for item in implementation['inputs']})
bitstream = ROOT / 'projects/hdmi/impl/pnr/piano_hdmi.fs'
assert digest(bitstream) == implementation['bitstream_sha256']
pins = json.loads(read(WORK / 'pins.json'))
assert pins['status'] == 'PASS_PIN_CONTRACT_ONLY' and len(pins['negative_controls']) == 4
for path in (WORK/'negative_console.log', reset/'normal_console.log', reset/'negative_console.log',
             ROOT/'build/hdmi/implementation_check.json', WORK/'pins.json',
             strict/'strict_inputs.txt', strict/'strict_compile.log',
             WORK/'mutant_instrument_uart_top.v', WORK/'negative_compile.log', WORK/'negative.do',
             ROOT/'model/check_delay_chorus.py', ROOT/'model/check_room_reverb.py',
             ROOT/'build/regression/effects/reference.json',
             ROOT/'build/regression/reverb/reference.json', Path(__file__)):
    artifacts[path.relative_to(ROOT).as_posix()] = digest(path)

summary = {
    'status': 'PASS_LOCAL_MERGE_CURRENT_CONSTRAINTS_ONLY', 'date': '2026-10-22',
    'merge_commits': ['a36a780', '301da9d'], 'upstream_effects': UPSTREAM,
    'worktree_has_preserved_uncommitted_changes': True,
    'preservation_stash': 'f49f1206adf7df1f2f155a1eb508ec89a0dc36c1',
    'strict_verilog_files': len(strict_inputs), 'functional_cases': passed,
    'protected_byte_identical_files': len(protected), 'upstream_unchanged_sources': len(names),
    'negative_controls': ['effects PA tail omitted', 'HDMI post-recovery lane corruption',
                          'J13 wrong pin', 'old black-key pin', 'wrong I/O voltage', 'wrong placed pin'],
    'cascade_reference': json.loads(read(ROOT/'build/regression/effects/integration_reference.json')),
    'audio_contract': {'sample_hz': 48000, 'voices': 16, 'raw_valid_cycle': 923,
                       'cache_cycle': 953, 'minimum_prepare_cycles': 976, 'spare_cycles': 23},
    'resources': implementation['resources'],
    'worst_reported_slack_ns': implementation['worst_reported_slack_ns'],
    'bitstream': bitstream.relative_to(ROOT).as_posix(), 'bitstream_sha256': digest(bitstream),
    'source_inputs': implementation['inputs'], 'artifacts': artifacts,
    'limitations': implementation['limitations'] + [
        'Simple UI intentionally excludes historical dark-layout touch slider; USB host remains absent.',
        'Original dark UI visual tests are not current-layout acceptance tests.',
        'Physical sound, wiring continuity and end-to-end latency not tested; no push/programming.',
        'Existing dry tests use explicit effects-disabled parameters, not full-wet evidence.']}
OUT.mkdir(parents=True, exist_ok=True)
(OUT/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'PASS merged evidence: {len(cases)} cases, {len(strict_inputs)} strict files, '
      f'{len(protected)} byte-identical protected files, {len(names)} original teammate sources')
