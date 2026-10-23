"""DAC发射端回归与板外预算门禁；不改RTL/SDC，不把未知参数默认为零。

python verification/scripts/check_dac_timing.py --run --allow-incomplete
默认退出2表示外部证据不完整；退出1表示测试/身份/预算失败。
--allow-incomplete只允许收集部分证据，JSON仍明确signoff=false。
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOP = 'tb_dac_launch_timing'
OUT = ROOT / 'build/regression/dac_timing'
FINAL = ROOT / 'build/regression/final'
CONTRACT = ROOT / 'verification/data/dac_timing_contract.json'


def read(path):
    return path.read_text(encoding='utf-8-sig')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def budgets(unknown, half_ns=320.0):
    """0..20ns来自原本地约束，只是保守预算前提，并非所有边沿已签核。

    setup=half+Bmin-Dmax-skew-U-tSU
    hold =half+Dmin-Bmax-skew-U-tHOLD
    每路板线项是相对BCK的绝对偏差上界，包含两个方向。
    """
    keys = ('din_setup', 'din_hold', 'ws_setup', 'ws_hold',
            'board_skew_din', 'board_skew_ws', 'clock_uncertainty')
    require(set(unknown) == set(keys), 'Missing/extra external budget fields')
    require(math.isfinite(half_ns) and half_ns > 0, 'Invalid half period')
    for key, value in unknown.items():
        require(value is None or (type(value) in (int, float) and
                math.isfinite(value) and value >= 0), 'Invalid ns: ' + key)
    slack = {}
    for signal in ('din', 'ws'):
        for check in ('setup', 'hold'):
            key = signal + '_' + check
            terms = [unknown[key], unknown['board_skew_' + signal], unknown['clock_uncertainty']]
            slack[key] = None if None in terms else round(half_ns - 20 - sum(terms), 6)
    return slack


def printed_paths(body):
    """保留每一条已打印路径，不以字典覆盖/默认值掩盖缺少路径或负余量。
    默认报告仅打印部分路径/边沿，不能将这些数当成全部转换的min/max包络。
    """
    found = {p: {'max': [], 'min': []} for p in ('HP_BCK', 'HP_WS', 'HP_DIN')}
    for heading, end, kind in (
        ('3.7.1 Setup Analysis Report', '3.7.2 Hold Analysis Report', 'max'),
        ('3.7.2 Hold Analysis Report', '3.7.3 Recovery Analysis Report', 'min')):
        require(heading in body and end in body, 'Missing timing section: ' + heading)
        section = body.rsplit(heading, 1)[1].split(end, 1)[0]
        for block in re.split(r'\s+Path\d+\s+', section):
            target = re.search(r'(?m)^To\s*:\s*(HP_BCK|HP_WS|HP_DIN)_obuf\s*$', block)
            if not target:
                continue
            arrival = re.search(r'Data Arrival Time\s*:\s*(-?[\d.]+)', block)
            slack = re.search(r'(?m)^Slack\s*:\s*(-?[\d.]+)', block)
            edge = re.search(r'tINS\s+([RF]{2})[^\n]*' + target[1] + r'_obuf/O', block)
            require(arrival and slack and edge, 'Malformed DAC path')
            value = float(arrival[1])
            require(float(slack[1]) >= 0 and 0 <= value <= 20, 'Local port budget violated')
            found[target[1]][kind].append({'arrival_ns': value, 'slack_ns': float(slack[1]), 'transition': edge[1]})
    require(all(v['min'] and v['max'] for v in found.values()), 'Missing DAC min/max port path')
    return found


def verified_inputs(manifest):
    for path, expected in manifest.items():
        require(sha(ROOT / path) == expected.lower(), 'Stale input: ' + path)
    return len(manifest)


def run_tests(bin_path):
    # 复用既有正常测试入口；负向只改变新TB的观测端，不改原RTL。
    subprocess.run([sys.executable, str(ROOT / 'verification/scripts/run_final_tests.py'),
                    TOP, '--bin', str(bin_path)], cwd=ROOT, check=True)
    negatives = {}
    for number, name in ((1, 'DIN'), (2, 'WS')):
        log = OUT / ('negative_' + name + '.log')
        command = [str(bin_path / 'vsim.exe'), '-c', '-lib', (FINAL / (TOP + '_work')).relative_to(ROOT).as_posix(),
                   '-gINJECT=' + str(number), TOP, '-wlf', str(OUT / ('negative_' + name + '.wlf')),
                   '-l', str(OUT / ('negative_' + name + '_transcript.log')),
                   '-do', 'onerror {quit -code 1 -f}; run -all; quit -code 0 -f']
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
        log.write_text(result.stdout, encoding='utf-8')
        marker = 'FAIL DAC ' + name + ' changed outside falling BCK'
        require(result.returncode == 0 and marker in result.stdout and 'PASS ' + TOP not in result.stdout,
                'Negative control did not fail as intended: ' + name)
        negatives[name] = {'result': 'EXPECTED_FAULT_REJECTED', 'sha256': sha(log)}
    (OUT / 'negative_results.json').write_text(json.dumps({
        'input_manifest_sha256': sha(FINAL / (TOP + '_inputs.json')),
        'cases': negatives}, indent=2)+'\n', encoding='utf-8')


class BudgetTests(unittest.TestCase):
    def values(self):
        return dict.fromkeys(json.loads(read(CONTRACT))['unknown_ns'], 0.0)

    def test_unknown_is_not_zero(self):
        self.assertTrue(all(v is None for v in budgets(dict.fromkeys(self.values())).values()))

    def test_arithmetic_and_boundaries(self):
        # 下面是测试夹具，不是PT8211参数。
        data = self.values(); data.update(din_setup=40, din_hold=10, board_skew_din=3, clock_uncertainty=2)
        self.assertEqual(budgets(data)['din_setup'], 255)
        self.assertEqual(budgets(data)['din_hold'], 285)
        data['din_setup'] = 295
        self.assertEqual(budgets(data)['din_setup'], 0)
        data['din_setup'] = 296
        self.assertEqual(budgets(data)['din_setup'], -1)

    def test_invalid_inputs(self):
        for value in (-1, float('nan'), float('inf'), True, '0'):
            data = self.values(); data['din_setup'] = value
            with self.assertRaises(ValueError): budgets(data)
        with self.assertRaises(ValueError): budgets({})

    def test_missing_paths_rejected(self):
        with self.assertRaises(ValueError): printed_paths('')

    def test_report_coverage_and_failure(self):
        def section():
            return ''.join('\nPath%d\nSlack : 1.0\nData Arrival Time : 5.0\nTo : %s_obuf\n'
                           'tINS RR 0 IOB %s_obuf/O\n' % (i, p, p)
                           for i, p in enumerate(('HP_BCK', 'HP_WS', 'HP_DIN')))
        body = ('3.7.1 Setup Analysis Report' + section() +
                '3.7.2 Hold Analysis Report' + section() + '3.7.3 Recovery Analysis Report')
        self.assertEqual(len(printed_paths(body)['HP_DIN']['min']), 1)
        with self.assertRaises(ValueError): printed_paths(body.replace('HP_WS', 'missing'))
        with self.assertRaises(ValueError): printed_paths(body.replace('Slack : 1.0', 'Slack : -0.1', 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true', help='Run normal and injected-fault RTL tests')
    parser.add_argument('--bin', type=Path, default=Path('C:/Library/modelsim/win64'))
    parser.add_argument('--allow-incomplete', action='store_true', help='Evidence collection only; never changes signoff')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BudgetTests))
        return 0 if result.wasSuccessful() else 1
    OUT.mkdir(parents=True, exist_ok=True)
    if args.run:
        run_tests(args.bin)
    tb_manifest = json.loads(read(FINAL / (TOP + '_inputs.json')))['sha256']
    sim_count = verified_inputs(tb_manifest)
    log = read(FINAL / (TOP + '_console.log'))
    require('PASS '+TOP in log and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):', log), 'RTL test not passed')
    window = re.search(r'DAC_WINDOWS_NS DIN_SETUP=(\d+) DIN_HOLD=(\d+) WS_SETUP=(\d+) WS_HOLD=(\d+)', log)
    require(window and all(int(v) == 320 for v in window.groups()), 'Missing/changed nominal boundary')
    negative_record = json.loads(read(OUT / 'negative_results.json'))
    require(negative_record['input_manifest_sha256'] == sha(FINAL / (TOP + '_inputs.json')),
            'Negative tests used different inputs')
    negatives = negative_record['cases']
    require(set(negatives) == {'DIN', 'WS'}, 'Missing negative checks')
    for name, item in negatives.items():
        require(item['result'] == 'EXPECTED_FAULT_REJECTED' and
                sha(OUT / ('negative_'+name+'.log')) == item['sha256'], 'Negative log identity mismatch')

    # 固定默认HDMI实现，绝不混用优选布局的位流/报告。
    impl = json.loads(read(ROOT / 'build/hdmi/implementation_check.json'))
    build_manifest = {}
    for line in read(ROOT / 'build/hdmi/build_inputs.txt').splitlines():
        match = re.fullmatch(r'([A-Fa-f0-9]{64})  (.+)', line)
        if match: build_manifest[match[2]] = match[1]
    require(len(build_manifest) > 20, 'Build manifest incomplete')
    build_count = verified_inputs(build_manifest)
    fs = ROOT / 'projects/hdmi/impl/pnr/piano_hdmi.fs'
    require(sha(fs) == impl['bitstream_sha256'], 'Wrong bitstream for implementation check')
    require(impl['status'] == 'PASS_CURRENT_CONSTRAINTS_ONLY', 'Implementation check not passed')
    report = ROOT / 'projects/hdmi/impl/pnr/piano_hdmi.tr'
    require(sha(report) == sha(ROOT / 'build/hdmi/piano_hdmi.tr'), 'Report differs from retained build copy')
    paths = printed_paths(read(report))
    sdc = read(ROOT / 'boards/tang_mega_60k_31004/piano.sdc')
    for kind, value in (('max', '20.000'), ('min', '0.000')):
        require('set_'+kind+'_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN uart_tx}] '+value in sdc,
                'Local delay contract changed; re-review budget')
    contract = json.loads(read(CONTRACT))
    slack = budgets(contract['unknown_ns'])
    bad = any(v is not None and v < 0 for v in slack.values())
    # 即使手填参数令算术为正，默认路径摘要仍不足以证明所有边沿和电气条件。
    result = {
        'status': 'FAIL_BUDGET' if bad else 'INCOMPLETE_EXTERNAL_EVIDENCE',
        'signoff': False, 'new_pnr_run': False, 'hardware_measured': False,
        'rtl_test': 'PASS', 'sim_inputs_verified': sim_count, 'build_inputs_verified': build_count,
        'negative_controls': negatives, 'nominal_digital_window_ns': 320,
        'provisional_port_window_ns': 300,
        'provisional_window_assumption': 'All BCK/WS/DIN launch-to-pad delays in existing 0..20ns window; no board/jitter/edge allowance yet',
        'conditional_slack_ns': slack, 'unknown_ns': contract['unknown_ns'],
        'unresolved_evidence': contract['unresolved_evidence'], 'printed_paths_only': paths,
        'bitstream_sha256': sha(fs), 'report_sha256': sha(report),
        'sha256': {str(p.relative_to(ROOT)): sha(p) for p in
                   (CONTRACT, Path(__file__), ROOT/'verification/tb/audio'/ (TOP+'.v'),
                    ROOT/'build/hdmi/build_inputs.txt', ROOT/'build/hdmi/implementation_check.json',
                    FINAL/(TOP+'_console.log'), FINAL/(TOP+'_inputs.json'))}
    }
    (OUT / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(result['status'] + ': digital tests PASS; signoff=false; ' + str(OUT/'summary.json'))
    return 1 if bad else (0 if args.allow_incomplete else 2)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print('FAIL DAC audit: '+str(error), file=sys.stderr)
        sys.exit(1)
