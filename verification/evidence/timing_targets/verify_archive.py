"""Verify the archived source/evidence and the narrow temporary cleanup boundary."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,zipfile
p=argparse.ArgumentParser();p.add_argument('--post-cleanup',action='store_true');a=p.parse_args()
DEST=Path(__file__).resolve().parent;ROOT=DEST.parents[2]
temporary=ROOT/'build/timing_targets_20261025';other=ROOT/'build/control_features_20261025'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
archive=read(DEST/'archive.json');zpath=ROOT/archive['archive'];assert sha(zpath)==archive['sha256']
with zipfile.ZipFile(zpath) as z:
    assert z.testzip() is None
    index=json.loads(z.read('archive_manifest.json'))
    assert not any(n.lower().endswith('.fs') for n in z.namelist())
    for name,r in index['entries'].items():assert hashlib.sha256(z.read(name)).hexdigest()==r['sha256'],name
    for case,records in index['cases'].items():
        for rel,r in records.items():assert hashlib.sha256(z.read(r['member'])).hexdigest()==r['sha256'],(case,rel)
    for rel,r in index['cases']['formal'].items():assert sha(ROOT/rel)==r['sha256'],rel
summary=read(DEST/'summary.json');assert sha(ROOT/summary['formal_bitstream'])==summary['formal_bitstream_sha256']
assert read(ROOT/'build/hdmi/latest_build.json')['bitstream_sha256']==summary['formal_bitstream_sha256']
assert other.is_dir()
other_manifest=other/'evidence/source_manifest.json'
result={'status':'PASS_ARCHIVE_AND_FINAL_SOURCE_IDENTITY','checked_at':datetime.now(timezone.utc).isoformat(),
 'archive_sha256':sha(zpath),'archive_entries_verified':len(index['entries']),
 'source_cases_verified':len(index['cases']),'formal_source_files_verified':len(index['cases']['formal']),
 'formal_fs_sha256':summary['formal_bitstream_sha256'],'temporary_root':str(temporary),
 'other_agent_root':str(other),'other_agent_source_manifest_sha256':sha(other_manifest),
 'verifier_sha256':sha(Path(__file__))}
if not a.post_cleanup:
    assert temporary.is_dir();save(DEST/'cleanup_ready.json',result)
else:
    ready=read(DEST/'cleanup_ready.json')
    assert ready['archive_sha256']==result['archive_sha256']
    assert ready['other_agent_source_manifest_sha256']==result['other_agent_source_manifest_sha256']
    assert not temporary.exists()
    result['status']='PASS_CLEANUP_FINAL_SOURCE_AND_OTHER_AGENT_PRESERVED'
    save(DEST/'cleanup_verification.json',result)
    cleanup={'completed':True,'removed':[str(temporary)],'temporary_backups_removed':True,
      'other_agent_directory_preserved':True,'verification':'verification/evidence/timing_targets/cleanup_verification.json'}
    archive['cleanup']=cleanup;save(DEST/'archive.json',archive)
    summary['cleanup']=cleanup;summary['archive']=archive;save(DEST/'summary.json',summary)
print(result['status'],result['source_cases_verified'],'source cases;',result['formal_source_files_verified'],'formal files')
