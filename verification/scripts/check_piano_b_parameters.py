"""核验试听确认的B版常量、不可变字段及生成器，不写RTL或ROM。"""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'model'))
from gen_piano_v3_rom import modes

def validate(words, tuning):
    if len(words)!=16384:raise ValueError('Expected 16384 canonical words')
    normalized='\n'.join(f'{w:019x}' for w in words)+'\n'
    if hashlib.sha256(normalized.encode()).hexdigest()!=tuning['normalized_table_sha256']:
        raise ValueError('Not the exact audition-selected B coefficients')
    mask=((1<<32)-1)<<10
    frozen='\n'.join(f'{(w&~mask) if 176<=i//64<=212 and i%64<48 else w:019x}' for i,w in enumerate(words))+'\n'
    if hashlib.sha256(frozen.encode()).hexdigest()!=tuning['immutable_fields_sha256']:
        raise ValueError('Frequency/phase/noise/guitar or out-of-range piano changed')
    for n in range(48,85):
        pairs=tuning['notes'][str(n)]
        if sum(a for a,l in pairs)>tuning['baseline_amplitude_budgets'][str(n)]:
            raise ValueError('Amplitude budget increased')
    expected=[]
    for preset in range(2):
        for note in range(128):
            for inc,amp,loss,phase,noise in modes(preset,note)+[(0,0,1,0,0)]*16:
                expected.append((noise<<74)|(inc<<42)|(amp<<26)|(loss<<10)|phase)
    if expected!=words:raise ValueError('Generator does not reproduce selected table')

if __name__=='__main__':
    tuning=json.loads((ROOT/'model/piano_b_envelopes.json').read_text())
    words=[int(w,16) for w in (ROOT/'rtl/rom/piano_v3_modes.mem').read_text().split()]
    validate(words,tuning)
    # 错一个钢琴系数或误改一个吉他系数都必须被拒绝。
    for index,bit in ((176*64,26),(176*64,42),(0,26)):
        bad=list(words);bad[index]^=1<<bit
        try:validate(bad,tuning)
        except ValueError:pass
        else:raise AssertionError('Coefficient mutation escaped verification')
    print('PASS candidate B: 16384 exact words; immutable frequency/phase/noise/guitar; amplitude budgets; generator; 3 rejected mutations')
