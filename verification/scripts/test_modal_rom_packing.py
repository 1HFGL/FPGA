"""检查派生ROM缺失、过期与非法原表都被拒绝；不触碰发布ROM。"""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'model'))
from pack_modal_rom import SOURCE, check, packed_tables


class PackingTests(unittest.TestCase):
    def test_checked_in_banks_match_canonical(self):
        self.assertEqual(check()['words'], 12288)

    def test_missing_stale_and_invalid_source_rejected(self):
        folder=ROOT/'build/regression/rom_packing'
        folder.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=folder) as directory:
            source=Path(directory)/'parameters.mem'
            shutil.copy2(SOURCE, source)
            with self.assertRaisesRegex(ValueError, 'Missing/stale'):
                check(source)
            for path, body in packed_tables(source):
                path.write_bytes(body.encode('ascii'))
            check(source)
            path=Path(str(source)+'.bank1.mem')
            path.write_text('0000000000000000000\n'+path.read_text().split('\n',1)[1], encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'Missing/stale'):
                check(source)
            words=source.read_text().split();words[63]='0000000000000000000'
            source.write_text('\n'.join(words)+'\n', encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'Unused modal slots'):
                packed_tables(source)
            source.write_text('000\n', encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'Expected 2 presets'):
                packed_tables(source)


if __name__=='__main__':
    unittest.main()
