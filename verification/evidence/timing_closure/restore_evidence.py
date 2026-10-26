"""Materialize a content-addressed evidence archive into a NEW directory."""
from pathlib import Path
import argparse,hashlib,json,zipfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('destination',type=Path)
p.add_argument('--archive',type=Path,default=Path(__file__).with_name('details.zip'))
a=p.parse_args();destination=a.destination.resolve()
if destination.exists():raise SystemExit('Choose a new destination; existing paths are never overwritten.')
with zipfile.ZipFile(a.archive) as z:
    manifest=json.loads(z.read('manifest.json'))
    assert manifest['format']=='sha256-object-archive-v1'
    for row in manifest['files']:
        target=(destination/row['path']).resolve()
        assert target.is_relative_to(destination) and target!=destination
        b=z.read(row['object']);assert hashlib.sha256(b).hexdigest()==row['sha256'] and len(b)==row['bytes']
        target.parent.mkdir(parents=True,exist_ok=True)
        with target.open('xb') as f:f.write(b)
print('Restored and verified',len(manifest['files']),'evidence files to',destination)
