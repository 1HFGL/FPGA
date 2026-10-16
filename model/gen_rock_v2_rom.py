"""Analytic bridge-pickup electric guitar and classic amp curve; no recorded PCM.

Mode word: noise flag[74], phase increment[73:42], amplitude[41:26],
loss Q0.24[25:10], initial sine phase[9:0]. 32 modes / MIDI note.
The extra ROM is a memoryless amp transfer function, not a sound recording.
"""
import math

FS=48000
CAB_ALPHA=round((1-math.exp(-2*math.pi*5500/(4*FS)))*65536)

def guitar_modes(note):
    f=440*2**((note-69)/12)
    pitch=(261.625565/f)**.25
    result=[]
    for h in range(1,32):
        hz=f*h*math.sqrt((1+.000010*h*h)/1.000010)
        # Displacement pluck comb * bridge-position velocity pickup comb.
        # Preserve the fundamental but emphasize the upper string modes.
        a=math.sin(math.pi*.16*h)*math.sin(math.pi*.055*h)/h**1.08
        resonance=1+.7*math.exp(-((hz-3200)/1600)**2)
        a*=resonance
        tau=2.20*pitch/(1+.016*h*h)
        result.append((hz,a,tau,256 if a>=0 else 768,0))
    result.append((0,.020,.0055,0,1)) # Short procedural pick excitation.
    scale=15000/sum(abs(m[1]) for m in result)
    packed=[]
    for hz,a,tau,phase,noise in result:
        amp=round(abs(a)*scale) if hz<20000 else 0
        inc=round(hz*2**32/FS) if hz<20000 else 0
        loss=min(65535,max(1,round((1-math.exp(-1/(FS*tau)))*2**24)))
        packed.append((inc,amp,loss,phase,noise))
    assert len(packed)==32 and sum(m[1] for m in packed)<=15032
    return packed

# Classic-rock candidate: reduced drive, C3..C6 single-note RMS compensation.
# The modal excitation and cabinet remain unchanged for an isolated A/B trial.
ROCK_DRIVE_DENOMINATOR=1400
ROCK_SHAPER_LEVEL=16100

def shaper():
    return [round(ROCK_SHAPER_LEVEL*math.tanh(i*32/ROCK_DRIVE_DENOMINATOR)) for i in range(1024)]
