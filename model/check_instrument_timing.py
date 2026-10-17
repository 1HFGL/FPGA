"""Audit the default registered four-voice instrument Gowin timing project.

Only same-clock registered module boundaries and internal logic are covered.
There are no board pin assignments or external input/output delay constraints.
"""
from pathlib import Path
import argparse
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, default=ROOT / 'projects/checks/instruments_check')
parser.add_argument('--report', type=Path, default=ROOT / 'build/regression/logs/instrument_timing_audit.json')
args = parser.parse_args()
project = args.project.resolve()
name = 'instruments_check'
s = (project / f'impl/pnr/{name}_tr_content.html').read_text(encoding='utf-8')


def rows(s):
    result = []
    for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>', s, re.S | re.I):
        cells = re.findall(r'<t[dh]\b[^>]*>(.*?)(?=</t[dh]>|<t[dh]\b|</tr>|$)', tr, re.S | re.I)
        result.append([html.unescape(re.sub('<[^>]+>', '', c)).strip() for c in cells])
    return result


def section(name):
    return rows(s.split(f'name="{name}"', 1)[1].split('<table', 1)[1].split('</table>', 1)[0])


summary = {r[0]: r[1] for r in rows(s)[:30] if len(r) == 2}
result = {
    'status': 'PASS', 'created_time': summary['Created Time'],
    'tool': summary['Tool Version'], 'device': summary['Part Number'],
    'physical_constraints': summary['Physical Constraints File'],
    'paths_analyzed': int(summary['Numbers of Paths Analyzed']),
    'endpoints_analyzed': int(summary['Numbers of Endpoints Analyzed']),
    'setup_violated_endpoints': int(summary['Numbers of Setup Violated Endpoints']),
    'hold_violated_endpoints': int(summary['Numbers of Hold Violated Endpoints']),
    'scope': 'Default four-voice instruments core with same-clock registered inputs/outputs; excludes board I/O timing and B/C integration.'
}
for kind in ('Setup', 'Hold'):
    r = section(kind + '_Slack_Table')[1]
    result[kind.lower()] = {'slack_ns': float(r[1]), 'from': r[2], 'to': r[3], 'data_delay_ns': float(r[8])}
result['clock'] = section('Clock_Report')[1]
result['fmax'] = section('Max_Frequency_Report')[1]
result['min_pulse'] = section('MIN_PULSE_WIDTH_TABLE')[1]
result['tns'] = section('Total_Negative_Slack_Report')[1:]
result['active_sdc'] = section('SDC_Report')[1:]
exceptions = s.split('name="Timing_Exceptions_Report"', 1)[1]
result['no_timing_exceptions'] = exceptions.count('No timing exceptions to report!') == 4
assert result['no_timing_exceptions']
assert len(result['active_sdc']) == 1 and result['active_sdc'][0][1] == 'Actived'
assert result['clock'][3:5] == ['20.000', '50.000']
assert result['setup_violated_endpoints'] == 0 and result['hold_violated_endpoints'] == 0
assert result['setup']['slack_ns'] > 0 and result['hold']['slack_ns'] > 0
assert float(result['min_pulse'][1]) >= 0, result['min_pulse']
assert all(float(r[2]) == 0 and int(r[3]) == 0 for r in result['tns'])
rpt = (project / f'impl/pnr/{name}.rpt.txt').read_text()
result['resource_summary'] = rpt.split('3. Resource Usage Summary', 1)[1].split('4. I/O Bank', 1)[0].strip()
assert re.search(r'--pROM\s+\|\s+12\b', result['resource_summary'])
result['warnings'] = {}
for label, rel in [('synthesis', f'impl/gwsynthesis/{name}.log'), ('pnr', f'impl/pnr/{name}.log')]:
    lines = (project / rel).read_text(errors='replace').splitlines()
    errors = [line for line in lines if re.search(r'\bERROR\b|error:', line, re.I)]
    assert not errors, errors
    result['warnings'][label] = [line for line in lines if re.search(r'\bWARN\b|warning:', line, re.I)]
assert not result['warnings']['pnr'], result['warnings']['pnr']
synwarn = result['warnings']['synthesis']
assert len(synwarn) == 4 and all('NL0002' in w and 'u_strings' in w for w in synwarn), synwarn
config = json.loads((project / 'process_config.json').read_text())
assert config['Correct_Hold_Violation'] and config['Run_Timing_Driven']
result['settings'] = {'hold_correction': True, 'timing_driven': True}
result['source_sha256'] = {}
source_paths = []
xml = (project / f'{name}.gprj').read_text()
for source in re.findall(r'<File path="([^"]+)"', xml):
    path = (project / source).resolve()
    source_paths.append(path)
    result['source_sha256'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
for filename in ('process_config.json', 'run.tcl', f'{name}.gprj'):
    path = project / filename
    source_paths.append(path)
    result['source_sha256'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
for filename in ('sine_1024.mem', 'guitar_1024.mem', 'strings_1024.mem'):
    path = ROOT / 'rtl/rom' / filename
    source_paths.append(path)
    result['source_sha256'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
# 修改源文件后必须先重新构建。时间戳只能发现普通的过期报告，
# 不能替代保存构建命令、退出码和本次源码哈希的完整证据。
report_time = (project / f'impl/pnr/{name}_tr_content.html').stat().st_mtime_ns
newer = [str(path) for path in source_paths if path.stat().st_mtime_ns > report_time]
assert not newer, f'Rebuild Gowin before auditing; source newer than timing report: {newer}'
result['no_source_newer_than_report'] = True
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(f"PASS: 50 MHz setup {result['setup']['slack_ns']:+.3f} ns, hold {result['hold']['slack_ns']:+.3f} ns; setup/hold violations 0/0.")
print('PASS: one active 20 ns clock, no false-path/multicycle exceptions, timing-driven and hold correction enabled.')
print('Scope: registered module timing only; board I/O and integrated top still need verification.')
print('Report:', args.report.resolve())
