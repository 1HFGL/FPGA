"""Verify retained evidence, exact formal inputs, current fs and cleanup boundary."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,zipfile
EV=Path(__file__).resolve().parent;ROOT=EV.parents[2]
p=argparse.ArgumentParser();p.add_argument('--after-cleanup',action='store_true');a=p.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
summary=json.loads((EV/'summary.json').read_text(encoding='utf-8'))
archive=json.loads((EV/'archive.json').read_text(encoding='utf-8'))
path=ROOT/archive['path'];assert sha(path)==archive['sha256']==summary['archive']['sha256']
with zipfile.ZipFile(path) as z:
    assert z.testzip() is None
    manifest=json.loads(z.read('archive_manifest.json'))
    assert len(z.namelist())==archive['entries']
    for name,item in manifest['files'].items():
        h=hashlib.sha256();size=0
        with z.open(name) as f:
            while True:
                chunk=f.read(1024*1024)
                if not chunk:break
                size+=len(chunk);h.update(chunk)
        assert h.hexdigest()==item['sha256'] and size==item['size'],name
    for alias,item in manifest['aliases'].items():assert manifest['files'][item['archive']]['sha256']==item['sha256'],alias
    for rel,item in manifest['cases']['formal'].items():assert sha(ROOT/rel)==item['sha256'],rel
    protected=json.loads(z.read('run/protected_formal.json'))
    allowed=set(summary['protected_files']['authorized_changed_existing_files'])
    changed=[rel for rel,h in protected.items() if not (ROOT/rel).is_file() or sha(ROOT/rel)!=h]
    assert set(changed)==allowed,changed
report=json.loads((ROOT/'build/hdmi/implementation_check.json').read_text(encoding='utf-8-sig'))
assert report['status']=='PASS_CURRENT_CONSTRAINTS_ONLY' and not report['errors']
for item in report['inputs']:assert sha(Path(item['path']))==item['sha256'],item['path']
assert sha(ROOT/summary['formal_bitstream'])==summary['formal_bitstream_sha256']==report['bitstream_sha256']
latest=json.loads((ROOT/'build/hdmi/latest_build.json').read_text(encoding='utf-8'))
assert latest['bitstream_sha256']==report['bitstream_sha256'] and latest['verification_summary']=='verification/evidence/timing_followup/summary.json'
owned=ROOT/'build/timing_followup_20261025'
if a.after_cleanup:assert not owned.exists()
assert (ROOT/'verification/evidence/timing_targets/details.zip').is_file(), 'Prior archive must remain'
record={'status':'PASS','verified_at_utc':datetime.now(timezone.utc).isoformat(),'archive_sha256':archive['sha256'],
 'entries_verified':archive['entries'],'formal_source_files_verified':len(manifest['cases']['formal']),
 'formal_bitstream_sha256':summary['formal_bitstream_sha256'],'protected_original_files':len(protected),
 'changed_existing_files':changed,'owned_tree_absent':not owned.exists(),
 'other_agent_tree_exists':(ROOT/'build/control_features_20261025').exists(),
 'prior_archive_preserved':True,'after_cleanup':a.after_cleanup}
(EV/('cleanup_verification.json' if a.after_cleanup else 'archive_verification.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if a.after_cleanup:
    summary['cleanup'].update({'status':'COMPLETE_ARCHIVE_VERIFIED_AND_OWNED_TREE_REMOVED','backup_removed':True,'candidate_trees_removed':True,
       'verification':'verification/evidence/timing_followup/cleanup_verification.json','finished_at_utc':record['verified_at_utc']})
    (EV/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS archive CRC/SHA256, formal source/build/fs identity'+(' and completed owned-tree cleanup' if a.after_cleanup else ''))
