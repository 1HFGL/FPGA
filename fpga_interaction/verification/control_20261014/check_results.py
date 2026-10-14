"""Validate saved regressions/timing and record the exact implementation inputs."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
summary = {}
for key, filename, expected in [('C', 'simulation.log', 17), ('AB', 'ab_simulation.log', 8)]:
    log = (ROOT / filename).read_text(encoding='utf-8-sig')
    passes = len(re.findall(r'PASS:', log))
    assert passes == expected and not re.search(r'FAIL:|\*\* (Error|Fatal):', log), (key, passes)
    summary[key] = {'passes': passes, 'log': filename}

report = ROOT / 'impl/pnr/control_verified_tr_content.html'
timing = report.read_text(encoding='utf-8')
timing_result = {'clock_period_ns': 20.0}
for label, key in [('Setup', 'setup'), ('Hold', 'hold')]:
    violations = int(re.search(r'Numbers of '+label+r' Violated Endpoints</td>\s*<td>(\d+)</td>', timing)[1])
    section = timing.split('name="'+label+'_Slack_Table"', 1)[1]
    slack = float(re.search(r'<td>1</td>\s*<td>([-\d.]+)</td>', section)[1])
    assert violations == 0 and slack >= 0, (label, violations, slack)
    timing_result[key+'_violations'] = violations
    timing_result[key+'_worst_slack_ns'] = slack

build_log = (ROOT / 'gowin_build.log').read_text(encoding='utf-8-sig')
assert 'CONTROL_BUILD_DONE' in build_log
inputs = []
for entry in ET.parse(ROOT / 'control_verified.gprj').findall('./FileList/File'):
    path = (ROOT / entry.attrib['path']).resolve()
    assert path.stat().st_mtime <= report.stat().st_mtime, f'Report predates source: {path}'
    inputs.append({'path': entry.attrib['path'], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
summary['Gowin'] = timing_result
summary['Gowin']['inputs'] = inputs
summary['Gowin']['warnings'] = sorted(set(re.findall(r'WARN\s+\(([^)]+)\)', build_log)))
summary['scope'] = '16 voices, existing two board-key pins and LED outputs; not final 13-key/DAC wiring'
(ROOT / 'verification_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f"PASS: C=17 AB=8; setup={timing_result['setup_worst_slack_ns']:+.3f} ns; hold={timing_result['hold_worst_slack_ns']:+.3f} ns; violations=0")
