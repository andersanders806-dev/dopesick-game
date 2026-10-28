#!/usr/bin/env python3
"""Tileable ocean normal maps + foam: band-limited periodic spectral height fields (seamless by construction)."""
import numpy as np, pathlib
from PIL import Image
OUT = pathlib.Path("/home/anders/dopesick-game/.claude/worktrees/assets-harbour/assets/_incoming/sea")
OUT.mkdir(parents=True, exist_ok=True)
N = 1024
def grid():
    k1 = 2*np.pi*np.fft.fftfreq(N); kx, ky = np.meshgrid(k1, k1)  # radians per texel
    return kx, ky, np.hypot(kx, ky)
def field(seed, kmin, kmax, slope, wdir=None, spread=1.0):
    rng = np.random.default_rng(seed)
    kx, ky, k = grid(); k[0,0] = 1
    amp = k**(-slope/2.0)
    amp[(k < kmin) | (k > kmax)] = 0
    # band edges rolled off smoothly
    amp *= np.clip((k-kmin)/(kmin*0.4+1e-9),0,1)*np.clip((kmax-k)/(kmax*0.3+1e-9),0,1)
    if wdir is not None:
        c = (kx*np.cos(wdir)+ky*np.sin(wdir))/k
        amp *= (np.abs(c)**spread)  # standing + travelling, elongated crests perpendicular to wind
    W = np.fft.fft2(rng.normal(size=(N,N)))
    h = np.fft.ifft2(W*amp).real
    return h/ h.std()
def normal(h, strength):
    dx = (np.roll(h,-1,1)-np.roll(h,1,1))*0.5; dy = (np.roll(h,-1,0)-np.roll(h,1,0))*0.5
    sc = strength/np.sqrt(0.5*(dx.var()+dy.var()))
    n = np.stack([-dx*sc, -dy*sc, np.ones_like(h)], -1)
    return n/np.linalg.norm(n,axis=-1,keepdims=True)
def save_n(n, name):
    Image.fromarray(((n*0.5+0.5)*255).round().astype(np.uint8)).save(OUT/name, optimize=True)
# 1 tile ~ 64 m: long swell, kmin ~ 2 cycles, kmax ~ 24 cycles
twopi = 2*np.pi/N
save_n(normal(field(11, 2*twopi, 28*twopi, 3.0, 0.6, 1.5), 0.35), "water_normal_swell_1k.png")
# 1 tile ~ 8 m: chop
save_n(normal(field(23, 4*twopi, 50*twopi, 3.2, 0.9, 1.2), 0.55), "water_normal_chop_1k.png")
# fine ripples, different direction (1 tile ~ 3 m)
save_n(normal(field(37, 8*twopi, 90*twopi, 3.2, 2.2, 1.0), 0.45), "water_normal_ripple_1k.png")
# foam: ridged multi-octave periodic noise thresholded into lacy streaks
def ridged(seed, kmin, kmax, slope):
    r = 1 - np.abs(field(seed, kmin, kmax, slope)/2.2)
    return np.clip(r,0,1)**3
base = field(61, 2*twopi, 12*twopi, 2.0); base = (base-base.min())/(base.max()-base.min())
lace = 0.55*ridged(62, 10*twopi, 80*twopi, 1.6) + 0.45*ridged(63, 30*twopi, 200*twopi, 1.2)
lace = (lace-lace.min())/(lace.max()-lace.min())
mask = np.clip((base-0.42)/0.25, 0, 1)
foam = np.clip(lace*1.6 - 0.35, 0, 1) * (0.25 + 0.75*mask)
foam = np.clip((foam-0.18)*2.2, 0, 1)
Image.fromarray((foam*255).astype(np.uint8),"L").save(OUT/"foam_1k.png", optimize=True)
print("foam mean", foam.mean().round(3))
c = Image.new('RGB',(1024,512))
for i,f in enumerate(['water_normal_swell_1k.png','water_normal_chop_1k.png','water_normal_ripple_1k.png','foam_1k.png']):
    im = Image.open(OUT/f).convert('RGB'); a = im.resize((256,256)); c.paste(a,(i*256,0))
    s = im.resize((128,128)); t = Image.new('RGB',(256,256))
    for x in (0,1):
        for y in (0,1): t.paste(s,(x*128,y*128))
    c.paste(t,(i*256,256))
c.save("/tmp/claude-1000/-home-anders/8e26354a-0e6b-4ea7-a9b9-d7d943c4019c/scratchpad/sea_preview.png")
