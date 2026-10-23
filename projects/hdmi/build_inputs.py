"""正式HDMI构建与隔离PNR共用的输入清单；不修改工程、RTL或约束。"""
from pathlib import Path
import argparse
import hashlib
import re
import xml.etree.ElementTree as ET

PROJECT = Path('projects/hdmi/piano_hdmi.gprj')
SUPPORT_FILES = (
    'projects/hdmi/build_inputs.py', 'projects/hdmi/build.ps1',
    'projects/hdmi/build.tcl', 'projects/hdmi/process_config.json',
    'projects/hdmi/pnr_trial.tcl', 'projects/hdmi/sweep_pnr.ps1',
    'projects/check_modal_rom.tcl', 'projects/piano/read_timing_html.py',
    'verification/scripts/pnr_sweep.py',
    'verification/scripts/check_hdmi_implementation.py',
)
CONSTRAINT_FILES = tuple('boards/tang_mega_60k_31004/' + n for n in
    ('piano.cst', 'piano.sdc', 'hdmi.cst', 'hdmi.sdc', 'ble.cst', 'ble.sdc', 'hdmi_reset_placement.cst'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked(root, paths):
    result = set()
    for path in paths:
        path = path.resolve()
        if not path.is_relative_to(root):
            raise ValueError('Project input outside workspace: ' + str(path))
        if not path.is_file():
            raise ValueError('Missing build input: ' + str(path))
        result.add(path)
    return sorted(result)


def project_files(root, generated, include_disabled=False):
    project = root / PROJECT
    for node in ET.parse(project).findall('.//File'):
        if node.get('enable') == '0' and not include_disabled:
            continue
        is_constraint = node.get('type') in ('file.cst', 'file.sdc')
        if generated == is_constraint:
            yield project.parent / node.attrib['path']


def source_inputs(root, include_disabled=False):
    """原始输入可在prepare之前枚举；派生CST/SDC不当作源码复制。"""
    root = root.resolve()
    paths = [root / PROJECT] + [root / n for n in SUPPORT_FILES + CONSTRAINT_FILES]
    paths += list(project_files(root, False, include_disabled))
    paths += list((root / 'rtl/rom').glob('*.mem'))
    return checked(root, paths)


def write_manifest(root, destination, mode='build'):
    root = root.resolve()
    paths = source_inputs(root, include_disabled=(mode == 'pnr')) + list(project_files(root, True))
    if mode == 'pnr':
        paths += [root / 'projects/hdmi/impl/gwsynthesis/piano_hdmi.vg']
    elif mode != 'build':
        raise ValueError('Unsupported manifest mode: ' + mode)
    paths = checked(root, paths)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text('top=piano_hdmi_top; mode=' + mode + '; common input inventory\n' +
        ''.join(f'{digest(path)}  {path}\n' for path in paths), encoding='utf-8')


def prepare_pnr_project(root):
    """仅用于隔离副本：清单冻结前禁用RTL、启用公共网表，避免Tcl隐式重综合/保存。"""
    project = root / PROJECT
    netlist = 'impl/gwsynthesis/piano_hdmi.vg'
    if not (project.parent / netlist).is_file():
        raise ValueError('Missing common synthesis netlist')
    tree = ET.parse(project)
    files = tree.find('FileList')
    if files is None:
        raise ValueError('Missing project FileList')
    rtl = [node for node in files if node.get('type') in ('file.verilog', 'file.vhdl')]
    if not rtl or any(node.get('type') == 'file.netlist' for node in files):
        raise ValueError('Expected original RTL project before PNR preparation')
    for node in rtl:
        node.set('enable', '0')
    ET.SubElement(files, 'File', path=netlist, type='file.netlist', enable='1')
    ET.indent(tree, space='    ')
    tree.write(project, encoding='utf-8', xml_declaration=True)


def verify_manifest(manifest):
    entries = []
    for line in manifest.read_text(encoding='utf-8-sig').splitlines()[1:]:
        match = re.fullmatch(r'([A-Fa-f0-9]{64})  (.+)', line)
        if not match:
            raise ValueError('Malformed build manifest entry: ' + line)
        expected, name = match.groups()
        path = Path(name)
        if not path.is_file() or digest(path) != expected.lower():
            raise ValueError('Input changed: ' + name)
        entries.append(name)
    if not entries or len(entries) != len(set(entries)):
        raise ValueError('Empty or duplicate input manifest')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--mode', choices=('build', 'pnr'), default='build')
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        verify_manifest(args.verify)
        print('PASS build input hashes unchanged')
    else:
        write_manifest(args.root, args.root / 'build/hdmi/build_inputs.txt', args.mode)
        print('PASS common HDMI input manifest')
