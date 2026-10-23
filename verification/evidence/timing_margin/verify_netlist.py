"""Gowin结构网表的保守、逐token双射重命名检查；不是通用HDL等价求解器。"""
from pathlib import Path
import hashlib
import json
import re
import sys

WORK=Path(__file__).resolve().parent
ROOT=WORK.parents[1]
ID=r'(?:\\[^\s]+|[A-Za-z_$][A-Za-z0-9_$]*)'
IDENT=re.compile(ID+r'\Z')
TOKEN=re.compile(r'"(?:\\.|[^"\\])*"|(?:\d+)?\'[sS]?[bBoOdDhH][0-9a-fA-F_xzXZ?]+|'+ID+r'|\d+|[^\s]')
KEYWORDS=set('module endmodule input output inout wire reg signed unsigned supply0 supply1 defparam parameter localparam assign tri wand wor'.split())
INSTANCE=re.compile(r'(?m)^\s*('+ID+r')\s+('+ID+r')\s*\((.*?)\)\s*;',re.S)
COMMENT_OR_STRING=re.compile(r'\\[^\s]+|"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',re.S)

def strip_comments(text):
    def replace(m):
        s=m[0]
        return ('\n'*s.count('\n')+' ') if s.startswith(('//','/*')) else s
    return COMMENT_OR_STRING.sub(replace,text)

def modules(text):
    # 本工具只接受Gowin实际产出的无行为、非ANSI声明网表，拒绝扩展语言猜测。
    text=strip_comments(text)
    text=re.sub(r'(?m)^`timescale[^\n]*$','',text)
    entries=list(re.finditer(r'(?ms)^module\s+('+ID+r')\s*\((.*?)\)\s*;(.*?)^endmodule\s*',text))
    assert entries
    assert not re.sub(r'\s+','',re.sub(r'(?ms)^module\s+('+ID+r')\s*\((.*?)\)\s*;(.*?)^endmodule\s*','',text))
    result={}
    for m in entries:
        name=m[1];ports=re.findall(ID,m[2])
        assert name not in result and len(ports)==len(set(ports))
        result[name]=(m[0],ports)
    return result

def pin_roles(body,known):
    result={};instances=[]
    for m in INSTANCE.finditer(body):
        kind,name=m[1],m[2]
        if kind=='module':continue
        instances.append(kind)
        for pin in re.finditer(r'\.('+ID+r')\s*\(',m[3]):
            result[m.start(3)+pin.start(1)]=(kind,pin[1])
    return result,instances

def equivalent(before,after,top='piano_hdmi_top'):
    # 块注释可能携带综合属性，必须原样相同，不能作为“无意义文本”吞掉。
    blocks=lambda text:[m[0] for m in COMMENT_OR_STRING.finditer(text) if m[0].startswith('/*')]
    assert blocks(before)==blocks(after),'Block-comment attributes differ'
    directives=lambda text:re.findall(r'(?m)^`timescale[^\n]*$',strip_comments(text))
    assert directives(before)==directives(after),'Timescale directive changed'
    a,b=modules(before),modules(after)
    assert list(a)==list(b),'Module list/order differs'
    ports={}
    for name in a:
        x,y=a[name][1],b[name][1]
        assert len(x)==len(y),'Interface width/count changed: '+name
        ports[name]=dict(zip(x,y))
        assert len(set(ports[name].values()))==len(x)
        if name==top:assert x==y,'Top-level port names/order must stay fixed'
    evidence={};total=0
    for name in a:
        x,y=a[name][0],b[name][0]
        px,ix=pin_roles(x,a);py,iy=pin_roles(y,b)
        assert ix==iy,'Instance type/order changed: '+name
        tx,ty=list(TOKEN.finditer(x)),list(TOKEN.finditer(y))
        assert len(tx)==len(ty),'Token count changed: '+name
        mapping={};reverse={};changed={}
        for index,(u,v) in enumerate(zip(tx,ty)):
            us,vs=u[0],v[0]
            rx,ry=px.get(u.start()),py.get(v.start())
            if rx or ry:
                assert rx and ry and rx[0]==ry[0],'Pin role/type changed'
                expected=ports[rx[0]].get(us) if rx[0] in ports else us
                assert expected==vs,'Named pin mismatch: '+name+' '+us+' -> '+vs
                continue
            if IDENT.fullmatch(us) and IDENT.fullmatch(vs) and us not in KEYWORDS and vs not in KEYWORDS:
                # 字段/原语参数不是本地网络名称，必须原样保留。
                if index>0 and tx[index-1][0]=='.':
                    assert us==vs,'Primitive/defparam field changed'
                    continue
                assert mapping.get(us,vs)==vs,'Inconsistent forward renaming: '+name+' '+us
                assert reverse.get(vs,us)==us,'Two old names merged: '+name+' '+vs
                mapping[us]=vs;reverse[vs]=us
                if us!=vs:changed[us]=vs
            else:
                assert us==vs,'Literal/operator/keyword changed: '+name+' '+us+' -> '+vs
        for old,new in ports[name].items():
            assert mapping.get(old)==new,'Interface/local net mismatch'
        evidence[name]=changed;total+=len(tx)
    return dict(status='PASS_ALPHA_RENAMING_ONLY',modules=len(a),token_pairs_checked=total,
                renamed_identifiers={k:v for k,v in evidence.items() if v})

def self_test():
    a='''module leaf (a,z);\ninput a; output z;\nwire n;\nLUT1 g (\n.I0(a), .F(n)\n);\ndefparam g.INIT=2'h2;\nassign z=n;\nendmodule
module piano_hdmi_top (i,o);\ninput i; output o;\nleaf u (\n.a(i), .z(o)\n);\nendmodule\n'''
    b=a.replace('leaf (a,z)','leaf (a_Z,z)').replace('input a;','input a_Z;').replace('.I0(a)', '.I0(a_Z)').replace('.a(i)','.a_Z(i)')
    equivalent(a,b)
    equivalent(a.replace(');',')\n;'),b.replace(');',')\n;'))
    equivalent(a+'`timescale 100 ps/100 ps\n',b+'`timescale 100 ps/100 ps\n')
    assert strip_comments('"a//b/*c*/" /* comment */ z')=='"a//b/*c*/"   z'
    equivalent(a.replace('input a;','/* syn_keep */ input a;'),b.replace('input a_Z;','/* syn_keep */ input a_Z;'))
    bad=(b.replace('.I0(a_Z)', '.I0(z)'),b.replace("2'h2","2'h3"),
         b.replace('.I0(a_Z)', '.F(a_Z)'),b.replace('LUT1 g','DFF g'),
         b.replace('piano_hdmi_top (i,o)','piano_hdmi_top (j,o)').replace('input i;','input j;').replace('.a_Z(i)','.a_Z(j)'),
         b.replace('input a_Z;','/* syn_keep */ input a_Z;'),b+'`timescale 1 ns/1 ps\n')
    for mutant in bad:
        try:equivalent(a,mutant)
        except AssertionError:continue
        raise AssertionError('Negative control was not rejected')
    return len(bad)

if __name__=='__main__':
    negatives=self_test()
    old=WORK/'base/projects/hdmi/impl/gwsynthesis/piano_hdmi.vg'
    new=ROOT/'projects/hdmi/impl/gwsynthesis/piano_hdmi.vg'
    result=equivalent(old.read_text(encoding='utf-8-sig'),new.read_text(encoding='utf-8-sig'))
    result.update(original_sha256=hashlib.sha256(old.read_bytes()).hexdigest(),
        formal_sha256=hashlib.sha256(new.read_bytes()).hexdigest(),plain_text_matches=False,
        negative_controls_rejected=negatives,only_source_change='Place_Option 4 -> 3',
        limitation='Conservative structural token/namespace bijection for these generated netlists; not arbitrary behavioral formal equivalence')
    (WORK/'netlist_identity.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ('status','modules','token_pairs_checked','negative_controls_rejected')},ensure_ascii=False))
