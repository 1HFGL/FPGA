"""PNR批跑的输入隔离、策略白名单、时序淘汰/排名和失败行为，不需要Gowin。"""
from pathlib import Path
from types import SimpleNamespace
import csv
import json
import sys
import tempfile
import tkinter
import unittest

from pnr_sweep import ROOT, TABLES, combinations, variant_config, rank_key, snapshot, save_results, command, publish_best, digest, check_pnr_only
sys.path.insert(0, str(ROOT/'projects/hdmi'))
from build_inputs import source_inputs, write_manifest, verify_manifest, prepare_pnr_project, SUPPORT_FILES, CONSTRAINT_FILES

TEMP = ROOT/'build/pnr_sweep_tests'


def result(name, setup, hold, status='PASS_CURRENT_CONSTRAINTS_ONLY'):
    return dict(name=name, strategy=dict(place=2,route=1,clock_order=0), status=status,
                seconds=1,slack_ns=dict(zip(TABLES,(setup,hold,.8,.143,5.8))))


class SweepTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        TEMP.mkdir(parents=True,exist_ok=True)

    def test_legal_strategies_and_baseline(self):
        self.assertEqual(combinations(['2:1','2:1'],[0,1]),[(0,0,0),(2,1,0),(2,1,1)])
        for rule in ('5:0','1:3','-1:0','2','2:1:0','seed:2'):
            with self.subTest(rule=rule),self.assertRaises(ValueError):
                combinations([rule],[0])
        with self.assertRaises(ValueError):
            combinations(['2:1'],[2])

    def test_netlist_log_without_skip_message(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            root=Path(d);project=root/'projects/hdmi';project.mkdir(parents=True)
            gprj=project/'piano_hdmi.gprj'
            gprj.write_text('<Project><FileList><File type="file.verilog" path="old.v" enable="0"/>'
                '<File type="file.netlist" path="impl/gwsynthesis/piano_hdmi.vg"/></FileList></Project>')
            log='Reading netlist file: "'+str(project/'impl/gwsynthesis/piano_hdmi.vg')+'"\n'
            check_pnr_only(root,log)
            for bad in ('Skip synthesis\n',log+'GowinSynthesis start\n',log.replace('piano_hdmi.vg','other.vg')):
                with self.assertRaises(RuntimeError):check_pnr_only(root,bad)
            gprj.write_text(gprj.read_text().replace('enable="0"','enable="1"'))
            with self.assertRaises(RuntimeError):check_pnr_only(root,log)

    def run_worker_stub(self, directory, netlist, active_rtl=False):
        """真实Tcl解释器执行worker，只替换EDA命令，不启动综合/布局。"""
        project=directory/'projects/hdmi';project.mkdir(parents=True)
        rom_check=directory/'verification/scripts/check_modal_rom.tcl'
        rom_check.parent.mkdir(parents=True)
        rom_check.write_text('')
        (project/'process_config.json').write_text('{}')
        gprj='<Project><FileList><File type="file.verilog" path="a.v"/>'
        gprj+='<File path="b.v" enable="1" type="file.verilog"/>'
        gprj+='<File path="timing.sdc" type="file.sdc"/></FileList></Project>'
        (project/'piano_hdmi.gprj').write_text(gprj)
        script=project/'pnr_trial.tcl'
        script.write_bytes((ROOT/'projects/hdmi/pnr_trial.tcl').read_bytes())
        if netlist:
            vg=project/'impl/gwsynthesis/piano_hdmi.vg'
            vg.parent.mkdir(parents=True);vg.write_text('frozen netlist')
            if not active_rtl:
                prepare_pnr_project(directory)
                gprj=(project/'piano_hdmi.gprj').read_text()
                self.assertEqual(gprj.count('enable="0"'),2)
                self.assertEqual(gprj.count('file.netlist'),1)
                with self.assertRaisesRegex(ValueError,'Expected original RTL project'):
                    prepare_pnr_project(directory)
        interp=tkinter.Tcl()
        interp.eval(r'''
            set calls {}
            foreach cmd {open_project set_option set_file_enable add_file saveto run} {
                proc $cmd {args} "lappend ::calls \[linsert \$args 0 $cmd\]"
            }
            proc exit {code} {error "EXIT:$code"}
            set argv {pnr 0 0 0}
        ''')
        old=Path.cwd()
        try:
            with self.assertRaisesRegex(tkinter.TclError,'EXIT:0' if netlist and not active_rtl else 'EXIT:1'):
                interp.call('source',str(script))
        finally:
            interp.call('cd',str(old))
        self.assertEqual((project/'piano_hdmi.gprj').read_text(),gprj)
        return [tuple(map(str,interp.splitlist(c))) for c in interp.splitlist(interp.getvar('calls'))]

    def test_pnr_worker_uses_frozen_netlist_without_saving_project(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            calls=self.run_worker_stub(Path(d),True)
            self.assertFalse(any(c[0] in ('set_file_enable','add_file') for c in calls))
            self.assertEqual([c for c in calls if c[0]=='run'],[('run','pnr')])

    def test_pnr_worker_refuses_missing_netlist(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            calls=self.run_worker_stub(Path(d),False)
            self.assertFalse(any(c[0] in ('run','add_file') for c in calls))

    def test_pnr_worker_refuses_active_rtl(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            calls=self.run_worker_stub(Path(d),True,active_rtl=True)
            self.assertFalse(any(c[0] in ('run','add_file') for c in calls))

    def test_only_three_options_change(self):
        base={'Place_Option':'0','Route_Option':'0','Clock_Route_Order':0,
              'Correct_Hold_Violation':True,'Run_Timing_Driven':True,'IncludePath':[]}
        changed=variant_config(base,(4,1,1))
        self.assertEqual({k for k in base if base[k]!=changed[k]},
                         {'Place_Option','Route_Option','Clock_Route_Order'})
        changed['IncludePath'].append('probe')
        self.assertEqual(base['IncludePath'],[])
        self.assertTrue(changed['Correct_Hold_Violation'])

    def test_balanced_and_setup_ranking(self):
        setup_best=result('fast',1.3,.12)
        margin_best=result('balanced',.9,.14)
        self.assertGreater(rank_key(margin_best),rank_key(setup_best))
        self.assertGreater(rank_key(setup_best,'setup'),rank_key(margin_best,'setup'))

    def test_bad_constraints_and_negative_slacks_excluded(self):
        self.assertIsNone(rank_key(result('failed',99,99,'FAILED')))
        for table in TABLES:
            for value in (-.001,float('nan'),float('inf')):
                bad=result('bad',2,.2);bad['slack_ns'][table]=value
                self.assertIsNone(rank_key(bad))
        bad=result('thin reset',2,.2);bad['slack_ns'][TABLES[3]]=.099
        self.assertIsNone(rank_key(bad))
        missing=result('missing',2,.2);missing['slack_ns'].pop(TABLES[0])
        self.assertIsNone(rank_key(missing))

    def test_outputs_keep_failed_candidates_and_csv_shape(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            out=Path(d)
            failed={'name':'prepare failed','strategy':{},'status':'FAILED','seconds':0}
            best=save_results(out,[failed,result('good',1,.14)],SimpleNamespace(rank='balanced'))
            self.assertEqual(best['name'],'good')
            with (out/'results.csv').open(encoding='utf-8-sig',newline='') as stream:
                rows=list(csv.reader(stream))
            self.assertTrue(all(len(row)==len(rows[0]) for row in rows))
            self.assertEqual(len(json.loads((out/'results.json').read_text())),2)

    def test_snapshot_preserves_relative_inputs_and_isolates_writes(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            root=Path(d)/'repo';target=Path(d)/'snapshot'
            paths=['projects/hdmi/piano_hdmi.gprj','rtl/top.v','rtl/rom/test.mem']
            paths += list(SUPPORT_FILES) + list(CONSTRAINT_FILES)
            for p in paths:
                f=root/p;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('original')
            project=root/paths[0]
            project.write_text('<Project><FileList><File path="../../rtl/top.v" type="file.verilog"/>'
                '<File path="../../build/hdmi/piano_hdmi.cst" type="file.cst"/></FileList></Project>')
            hashes=snapshot(root,target)
            self.assertIn('rtl/rom/test.mem',hashes)
            self.assertIn('verification/scripts/read_timing_html.py',hashes)
            self.assertIn('projects/hdmi/build_inputs.py',hashes)
            self.assertEqual((target/'rtl/top.v').read_text(),'original')
            # 构建与快照必须使用同一份源清单；生成CST另行纳入build/PNR清单。
            self.assertEqual(set(hashes),{p.relative_to(root).as_posix() for p in source_inputs(root)})
            generated=root/'build/hdmi/piano_hdmi.cst'
            generated.parent.mkdir(parents=True);generated.write_text('generated constraints')
            manifest=root/'build/hdmi/build_inputs.txt'
            write_manifest(root,manifest,'build')
            verify_manifest(manifest)
            parser=root/'verification/scripts/read_timing_html.py'
            parser.write_text('changed parser')
            with self.assertRaisesRegex(ValueError,'Input changed'):
                verify_manifest(manifest)
            parser.write_text('original')
            rom=root/'rtl/rom/test.mem';rom.unlink()
            with self.assertRaisesRegex(ValueError,'Input changed'):
                verify_manifest(manifest)
            rom.write_text('original')
            constraint=root/CONSTRAINT_FILES[0];constraint.write_text('weakened constraint')
            with self.assertRaisesRegex(ValueError,'Input changed'):
                verify_manifest(manifest)
            constraint.write_text('original')
            vg=root/'projects/hdmi/impl/gwsynthesis/piano_hdmi.vg'
            vg.parent.mkdir(parents=True);vg.write_text('frozen netlist')
            prepare_pnr_project(root)
            write_manifest(root,manifest,'pnr')
            verify_manifest(manifest)
            self.assertIn(str(root/'rtl/top.v'),manifest.read_text())
            vg.write_text('changed netlist')
            with self.assertRaisesRegex(ValueError,'Input changed'):
                verify_manifest(manifest)
            vg.write_text('frozen netlist')
            (root/'rtl/top.v').write_text('changed disabled RTL')
            with self.assertRaisesRegex(ValueError,'Input changed'):
                verify_manifest(manifest)
            (root/'rtl/top.v').write_text('original')
            (target/'rtl/top.v').write_text('changed')
            self.assertEqual((root/'rtl/top.v').read_text(),'original')
            project.write_text('<Project><FileList><File path="../../../outside.v" type="file.verilog"/>'
                               '</FileList></Project>')
            with self.assertRaises(ValueError):
                snapshot(root,Path(d)/'unsafe')

    def test_process_failure_propagates_with_log(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            log=Path(d)/'failure.log'
            with self.assertRaisesRegex(RuntimeError,'Exit 7'):
                command([sys.executable,'-c','import sys; print("diagnostic"); sys.exit(7)'],Path(d),log,10)
            self.assertIn('diagnostic',log.read_text())

    def test_confirmation_is_required_before_publishing(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            batch=Path(d)
            best=result('good',2,.14)
            args=SimpleNamespace(rank='balanced',confirm_best=True)
            for confirmation in (None,result('timeout',2,.14,'FAILED'),
                                 result('negative hold',2,-.001)):
                with self.subTest(confirmation=confirmation),self.assertRaisesRegex(RuntimeError,'Confirmation failed'):
                    publish_best(batch,best,confirmation,{},args,'netlist',[best])
                self.assertFalse((batch/'best').exists())
                self.assertFalse((batch/'best_pending').exists())

    def test_missing_or_changed_artifact_is_not_published(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            batch=Path(d);source=batch/'trial';source.mkdir()
            best=result('good',2,.14)
            best.update(directory=str(source),fs=str(source/'design.fs'),fs_sha256='missing')
            args=SimpleNamespace(rank='balanced',confirm_best=False)
            with self.assertRaisesRegex(RuntimeError,'artifacts missing'):
                publish_best(batch,best,None,{},args,'netlist',[best])
            self.assertFalse((batch/'best').exists())
            for path in ('design.fs','build/hdmi/implementation_check.json','build/hdmi/timing.txt',
                         'projects/hdmi/process_config.json','projects/hdmi/effective_options.tcl'):
                file=source/path;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('test')
            with self.assertRaisesRegex(RuntimeError,'bitstream changed'):
                publish_best(batch,best,None,{},args,'netlist',[best])
            best['fs_sha256']=digest(Path(best['fs']))
            artifact=publish_best(batch,best,None,{},args,'netlist',[best])
            self.assertTrue(artifact.is_file())
            self.assertFalse((batch/'best_pending').exists())

    def test_source_changed_blocks_publication(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as d:
            batch=Path(d);best=result('good',2,.14)
            args=SimpleNamespace(rank='balanced',confirm_best=False)
            with self.assertRaisesRegex(RuntimeError,'Source changed'):
                publish_best(batch,best,None,{'rtl/nonexistent.v':'0'},args,'netlist',[best])
            self.assertFalse((batch/'best').exists())


if __name__=='__main__':
    unittest.main()
