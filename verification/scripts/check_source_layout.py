"""Check active project paths, module uniqueness and Python imports without hardware."""
from pathlib import Path
import ast,json,re,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
modules={}
for path in sorted((ROOT/'rtl').rglob('*.v')):
    body=re.sub(r'/\*.*?\*/|//[^\n]*','',path.read_text(encoding='utf-8-sig'),flags=re.S)
    for name in re.findall(r'\bmodule\s+(\w+)',body):
        assert name not in modules, f'Duplicate module: {name}'
        modules[name]=path
    for rom in re.findall(r'"(rtl/rom/[^"\n]+\.mem)"',body):
        assert (ROOT/rom).is_file(), f'Missing ROM: {rom}'
projects={}
for project in [ROOT/'projects/piano/uart_piano.gprj',ROOT/'projects/display/display_rgb.gprj']:
    files=[]
    for node in ET.parse(project).findall('.//File'):
        source=(project.parent/node.attrib['path']).resolve()
        assert source.is_relative_to(ROOT) and source.is_file(), f'Missing/outside project input: {source}'
        files.append(source.relative_to(ROOT).as_posix())
    assert len(files)==len(set(files)), f'Duplicate GPRJ source: {project}'
    projects[project.relative_to(ROOT).as_posix()]=files
for path in (ROOT/'model').glob('*.py'):
    tree=ast.parse(path.read_text(encoding='utf-8-sig'))
    for node in ast.walk(tree):
        if isinstance(node,ast.ImportFrom) and node.module and node.module.startswith(('gen_','check_')):
            assert (ROOT/'model'/(node.module+'.py')).is_file(), f'Missing local Python import: {path}: {node.module}'
assert set(p.name for p in (ROOT/'rtl/synth').glob('*.v'))=={'instrument_env.v','voice_bank_music_pipe.v'}
assert set(p.name for p in (ROOT/'rtl/rom').glob('*.mem'))=={'sine_1024.mem','piano_v3_modes.mem','rock_v2_shaper.mem','pitch_bend_1025.mem'}
report=dict(active_modules=len(modules),synthesis_modules=2,rom_tables=4,projects=projects)
out=ROOT/'build/cleanup_a';out.mkdir(parents=True,exist_ok=True)
(out/'source_layout.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(f'PASS source layout: {len(modules)} active modules; 2 synthesis modules; 4 ROMs; 2 valid GPRJs')
