"""Build the current-user installer/portable ZIP and its exact host sources.

Run using the project venv after installing host/build_requirements.txt.
Generated output is confined to build/host-release; no signing, Git writes,
driver installation, COM connection, or FPGA flashing is performed.
"""
import argparse
import hashlib
import importlib.metadata as metadata
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "host"
sys.path.insert(0, str(HOST))
from studio_runtime import VERSION, PRODUCT_NAME


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def source_files():
    allowed = {".py", ".md", ".txt", ".ps1", ".bat", ".cmd"}
    files = [p for p in HOST.rglob("*") if p.is_file() and "__pycache__" not in p.parts
             and (p.suffix in allowed or p.parent.name == "tone_examples" and p.suffix == ".json")]
    # This is a reference fixture used by test_piano.py, not an FPGA release.
    fixture = ROOT / "rtl/rom/piano_1024.mem"
    if fixture.exists():
        files.append(fixture)
    return sorted(files)


def make_icon(path):
    from PySide6.QtCore import QBuffer, QIODevice, QRectF
    from PySide6.QtGui import QColor, QImage, QPainter, QPen
    images = []
    for size in [16, 32, 48, 64, 128, 256]:
        img = QImage(size, size, QImage.Format_ARGB32)
        img.fill(QColor(0, 0, 0, 0))
        painter = QPainter(img)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.scale(size / 256, size / 256)
        painter.setPen(QColor("#d5ed99"))
        painter.setBrush(QColor("#d5ed99"))
        painter.drawRoundedRect(QRectF(4, 4, 248, 248), 57, 57)
        painter.setPen(QPen(QColor("#182821"), 13))
        for x, height in zip([54, 91, 128, 165, 202], [65, 124, 172, 96, 45]):
            painter.drawLine(x, 128 - height // 2, x, 128 + height // 2)
        painter.end()
        buffer = QBuffer()
        buffer.open(QIODevice.WriteOnly)
        img.save(buffer, "PNG")
        images.append((size, bytes(buffer.data())))
    offset = 6 + 16 * len(images)
    header = struct.pack("<HHH", 0, 1, len(images))
    entries = bytearray()
    for size, data in images:
        entries.extend(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    path.write_bytes(header + entries + b"".join(data for _, data in images))


def copy_licenses(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for file in (Path(__file__).parent / "licenses").glob("*.txt"):
        shutil.copy2(file, destination / file.name)
    for package in ["PySide6", "PySide6_Essentials", "PySide6_Addons", "shiboken6", "pyserial"]:
        dist = metadata.distribution(package)
        target = destination / package
        target.mkdir(exist_ok=True)
        (target / "METADATA.txt").write_text(dist.read_text("METADATA") or "", encoding="utf-8")
        for relative in dist.files or []:
            text = str(relative).lower()
            if ("license" in text or "copying" in text or "notice" in text) and ".dist-info" in text:
                file = Path(dist.locate_file(relative))
                if file.is_file():
                    rel = Path(str(relative).split(".dist-info/", 1)[-1])
                    (target / rel).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(file, target / rel)
    for name in ["LICENSE.txt", "LICENSE"]:
        path = Path(sys.base_prefix) / name
        if path.exists():
            shutil.copy2(path, destination / "Python-LICENSE.txt")
            break
    (destination / "README.txt").write_text(
        "Runtime libraries remain under their respective licenses.\n"
        "Qt/PySide 6.8.3 are dynamically linked; do not remove or replace the license notices.\n"
        "An onedir distribution permits replacement of the shared libraries.\n"
        "PySide sources: https://download.qt.io/official_releases/QtForPython/pyside6/\n"
        "Qt sources: https://download.qt.io/archive/qt/6.8/6.8.3/\n"
        "Python: https://www.python.org/ ; pyserial: https://github.com/pyserial/pyserial\n"
        "PyInstaller: https://pyinstaller.org/en/stable/license.html (bootloader distribution exception).\n",
        encoding="utf-8")


def zip_tree(source, destination):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(source.parent))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "build/host-release")
    args = parser.parse_args()
    output = args.output.resolve()
    permitted = (ROOT / "build").resolve()
    if not output.is_relative_to(permitted):
        parser.error("Build output must remain inside this project's build directory")
    output.mkdir(parents=True, exist_ok=True)
    files = source_files()
    if (ROOT / ".git").exists() and shutil.which("git"):
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    elif (ROOT / "release.json").exists():
        revision = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))["base_git_revision"]
    else:
        revision = "unversioned-source"
    info = {"application_id": "org.jingzou.studio", "product": PRODUCT_NAME,
            "version": VERSION, "date": "2026-10-28", "architecture": "Windows x64",
            "base_git_revision": revision, "source_has_local_changes": True,
            "demo": "silent; no physical COM; 32 voices; notes/status only",
            "dependencies": {n: metadata.version(n) for n in ["PySide6", "pyserial", "PyInstaller"]},
            "source_sha256": {p.relative_to(ROOT).as_posix(): sha256(p) for p in files}}
    resources = output / "resources"
    resources.mkdir(exist_ok=True)
    write_json(resources / "release.json", info)
    make_icon(resources / "studio.ico")
    version = tuple(int(x) for x in VERSION.split(".")) + (0,)
    (resources / "version.txt").write_text(
        "VSVersionInfo(ffi=FixedFileInfo(filevers=" + repr(version) + ", prodvers=" + repr(version) +
        ", mask=0x3f, flags=0, OS=0x40004, fileType=0x1, subtype=0, date=(0,0)), "
        "kids=[StringFileInfo([StringTable('080404b0', [StringStruct('FileDescription', '声场上位机'), "
        f"StringStruct('FileVersion', '{VERSION}'), StringStruct('ProductVersion', '{VERSION}'), "
        "StringStruct('ProductName', 'Jingzou Studio'), StringStruct('OriginalFilename', 'JingzouStudio.exe')])]), "
        "VarFileInfo([VarStruct('Translation', [2052, 1200])])])", encoding="utf-8")
    env = os.environ.copy()
    tmp = output / "tmp"
    tmp.mkdir(exist_ok=True)
    env.update({"TEMP": str(tmp), "TMP": str(tmp), "PYINSTALLER_CONFIG_DIR": str(output / "cache")})
    command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--windowed",
               "--noupx", "--name", "JingzouStudio", "--icon", str(resources / "studio.ico"),
               "--version-file", str(resources / "version.txt"), "--distpath", str(output / "dist"),
               "--workpath", str(output / "work"), "--specpath", str(output / "spec"), "--paths", str(HOST),
               "--add-data", f"{resources / 'release.json'}:.",
               "--add-data", f"{HOST / 'tone_examples'}:tone_examples",
               "--exclude-module", "PySide6.QtMultimedia", "--exclude-module", "PySide6.QtWebEngineCore",
               "--exclude-module", "PySide6.QtQml", str(HOST / "studio.py")]
    with (output / "pyinstaller.log").open("w", encoding="utf-8") as log:
        subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    print("Executable built", flush=True)
    # Use a new, versioned staging directory; never recursively clear user paths.
    staging = output / "staging" / f"JingzouStudio-{VERSION}-win64"
    if staging.exists():
        raise RuntimeError("Staging already exists; choose a new --output directory for a rebuild")
    staging.mkdir(parents=True)
    shutil.copytree(output / "dist/JingzouStudio", staging / "app")
    copy_licenses(staging / "app/LICENSES")
    shutil.copy2(resources / "release.json", staging / "release.json")
    for source in Path(__file__).parent.iterdir():
        if source.suffix in {".ps1", ".cmd", ".txt"}:
            text = source.read_text(encoding="utf-8-sig")
            # Windows PowerShell 5.1 needs a BOM for Chinese shortcut names.
            (staging / source.name).write_text(text, encoding="utf-8-sig" if source.suffix == ".ps1" else "utf-8")
    manifest = {"application_id": info["application_id"], "version": VERSION,
                "files": {p.relative_to(staging / "app").as_posix(): sha256(p)
                          for p in sorted((staging / "app").rglob("*")) if p.is_file()}}
    write_json(staging / "package-files.json", manifest)
    source_root = output / "source" / f"JingzouStudio-{VERSION}-source"
    source_root.mkdir(parents=True, exist_ok=True)
    for file in files:
        target = source_root / file.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)
    write_json(source_root / "release.json", info)
    (source_root / "README.txt").write_text(
        "Exact host sources for the accompanying Windows build.\n"
        "Install host/studio_requirements.txt into a Python 3.10-3.13 virtual environment.\n"
        "Run host/studio.py --demo for silent testing.\n"
        "To rebuild: install host/build_requirements.txt; run host/distribution/build_windows.py.\n"
        "rtl/rom/piano_1024.mem is only a fixture for the old single-cycle reference test.\n"
        "This archive is not the full FPGA repository or a bitstream package.\n", encoding="utf-8")
    portable = output / f"JingzouStudio-{VERSION}-win64.zip"
    sources = output / f"JingzouStudio-{VERSION}-source.zip"
    zip_tree(staging, portable)
    zip_tree(source_root, sources)
    (output / "SHA256SUMS.txt").write_text(
        "".join(f"{sha256(p)}  {p.name}\n" for p in [portable, sources]), encoding="ascii")
    write_json(output / "build-summary.json", {"release": info,
               "artifacts": {p.name: {"sha256": sha256(p), "bytes": p.stat().st_size} for p in [portable, sources]}})
    print(json.dumps({"portable": str(portable), "source": str(sources),
                      "portable_mb": round(portable.stat().st_size / 1024**2, 1)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
