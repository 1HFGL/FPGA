"""Independent integer oracle plus frequency-domain acceptance for expression tone.

No audio playback or hardware access. Run 'generate' before ModelSim, 'check' after.
"""
from pathlib import Path
import csv, json, math, random, sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/expression'

def nearest(n, denominator):
    return (1 if n >= 0 else -1) * ((abs(n) + denominator // 2) // denominator)

def reference(x, brightness, previous):
    alpha = 65536 if brightness == 127 else 2048 + 500 * brightness
    updated = previous + nearest((x * 65536 - previous) * alpha, 65536)
    if x == 0 and abs(updated) < 32768:
        updated = 0
    return updated, max(-32768, min(32767, nearest(updated, 65536)))

def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(2601017)
    rows = []
    for t in (127, 0, 32, 64, 96, 126):
        rows += [(x, t, rng.randint(3, 9), int(i == 0))
                 for i, x in enumerate([32767, -32768, 0, 1, -1] * 40)]
        rows += [(0, t, 3, 0)] * 800
    # All brightness values, random sign/size and valid gaps; reset within streams.
    rows += [(rng.randint(-32768, 32767), t, rng.randint(3, 12), int(i % 211 == 0))
             for i in range(8192) for t in [i % 128]]
    rows += [(0, 0, 3, 0)] * 800
    (OUT / 'tone_vectors.txt').write_text(''.join('%d %d %d %d\n' % r for r in rows), encoding='ascii')
    print(f'Generated {len(rows)} tone vectors')

def check_unit():
    vectors = [tuple(map(int, s.split())) for s in (OUT / 'tone_vectors.txt').read_text().splitlines()]
    actual = list(csv.DictReader((OUT / 'tone_actual.csv').open()))
    assert len(actual) == len(vectors), (len(actual), len(vectors))
    state = 0
    for i, ((x, t, _, reset), got) in enumerate(zip(vectors, actual)):
        if reset:
            state = 0
        state, y = reference(x, t, state)
        assert int(got['index']) == i and int(got['y']) == y, (i, x, t, y, got)
        assert int(got['overrun']) == 0, (i, 'overrun')
        assert int(got['tail']) == int(state != 0 or y != 0), (i, 'tail')
        if t == 127:
            assert y == x, (i, 'original tone changed')
    assert state == 0 and int(actual[-1]['tail']) == 0, 'IIR failed to reach exact silence'
    return len(actual)

def harmonic_fit(samples, frequency):
    n = np.arange(len(samples)) / 48000
    cols = [np.ones(len(n))]
    for h in range(1, 9):
        cols += [np.sin(2 * np.pi * frequency * h * n), np.cos(2 * np.pi * frequency * h * n)]
    coeff, *_ = np.linalg.lstsq(np.array(cols).T, samples, rcond=None)
    return np.hypot(coeff[1::2], coeff[2::2])

def check_integration():
    rows = list(csv.DictReader((OUT / 'performance_brightness.csv').open()))
    state = 0
    for i, row in enumerate(rows):
        x, t, got = (int(row[k]) for k in ('raw', 'brightness', 'filtered'))
        state, expected = reference(x, t, state)
        assert got == expected, ('integration oracle', i, expected, got)
    result = {}
    # Actual note-phase LUT rounds frequency to Q0.32; this is below 1mHz from equal temperament.
    base = 440 * 2 ** ((60 - 69) / 12)
    for segment in (1, 2, 3, 4):
        selected = [r for r in rows if int(r['segment']) == segment]
        assert len(selected) >= 1100, (segment, len(selected))
        raw = np.array([int(r['raw']) for r in selected], dtype=float)
        filtered = np.array([int(r['filtered']) for r in selected], dtype=float)
        f = base if segment != 4 else base * 73562 / 65536
        before, after = harmonic_fit(raw, f), harmonic_fit(filtered, f)
        h4ratio = 20 * math.log10((after[3] / after[0]) / (before[3] / before[0]))
        result[segment] = dict(frequency_hz=f, raw_fundamental=float(before[0]),
                               filtered_fundamental=float(after[0]), h4_relative_change_db=h4ratio)
        if segment == 1:
            assert np.array_equal(raw, filtered), 'default brightness not exact bypass'
        else:
            assert h4ratio < -8, ('brightness fails to change spectrum', segment, h4ratio)
        # A filter may alter amplitude/phase, but must retain the note frequency.
        candidates = np.linspace(f - 8, f + 8, 65)
        best = max(candidates, key=lambda fc: harmonic_fit(filtered, fc)[0])
        assert abs(best - f) < 2, ('unexpected pitch shift', segment, best, f)
    ratio = result[3]['raw_fundamental'] / result[2]['raw_fundamental']
    assert 0.48 < ratio < 0.53, ('independent volume', ratio)
    return result, len(rows)

def check_modal():
    rows = list(csv.DictReader((OUT / 'modal_brightness.csv').open()))
    state = 0
    modified = 0
    for i, row in enumerate(rows):
        x, t, got = (int(row[k]) for k in ('raw', 'brightness', 'filtered'))
        state, expected = reference(x, t, state)
        assert got == expected, ('modal oracle', i, expected, got)
        if t == 127:
            assert got == x, ('modal bypass', i)
        elif x != got:
            modified += 1
    assert state == 0 and modified > 500, ('modal tail or ineffective tone', state, modified)
    return len(rows)

if __name__ == '__main__':
    if sys.argv[1:] == ['generate']:
        generate()
    else:
        count = check_unit()
        modal_count = check_modal()
        result, integrated = check_integration()
        summary = dict(unit_exact_samples=count, integration_exact_samples=integrated,
                       modal_exact_samples=modal_count, spectrum=result, default_bypass_exact=True, hardware_verified=False)
        (OUT / 'tone_analysis.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'PASS tone oracle: {count} unit and {integrated} integration samples exact; finite zero tail')
        print(json.dumps(result, indent=2))
