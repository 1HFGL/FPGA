"""Record source changes against the pre-change local backup; no Git operations."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SUFFIXES = {'.v', '.sv', '.ps1', '.do'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None

changes = []
for project in ['fpga_interaction', 'fpga_a', 'fpga_ab_sim']:
    before = HERE / 'baseline' / project
    after = ROOT / project
    paths = set()
    for folder in ['rtl', 'tb', 'scripts', 'sim']:
        for base in [before, after]:
            for path in (base / folder).rglob('*'):
                if path.is_file() and path.suffix in SUFFIXES and 'work' not in path.parts:
                    paths.add(path.relative_to(base))
    for relative in sorted(paths):
        old, new = digest(before / relative), digest(after / relative)
        if old != new:
            changes.append({'path': (Path(project) / relative).as_posix(),
                            'status': 'added' if old is None else 'deleted' if new is None else 'modified',
                            'before_sha256': old, 'after_sha256': new})
(HERE / 'source_changes.json').write_text(json.dumps(changes, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'Recorded {len(changes)} source changes; backup preserved, no Git upload.')
