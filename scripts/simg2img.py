#!/usr/bin/env python3
# Android sparse -> raw (file raw sparso su disco). Uso: simg2img.py IN OUT
import struct, sys
f = open(sys.argv[1], 'rb'); o = open(sys.argv[2], 'wb')
magic, maj, mnr, fhs, chs, bsz, nblk, nchk, csum = struct.unpack('<IHHHHIIII', f.read(28))
assert magic == 0xED26FF3A, 'non è un file sparse'
f.seek(fhs)
for _ in range(nchk):
    ct, _r, csz, tsz = struct.unpack('<HHII', f.read(12)); f.seek(chs - 12, 1)
    n = csz * bsz; data = tsz - chs
    if ct == 0xCAC1:            # raw
        left = n
        while left: b = f.read(min(left, 1 << 24)); o.write(b); left -= len(b)
    elif ct == 0xCAC2:          # fill
        pat = f.read(4)
        if pat == b'\0\0\0\0': o.seek(n, 1)
        else:
            blk = pat * (bsz // 4)
            for _ in range(csz): o.write(blk)
    elif ct == 0xCAC3: o.seek(n, 1)  # don't care
    elif ct == 0xCAC4: f.seek(data, 1)  # crc
    else: raise SystemExit('chunk sconosciuto %x' % ct)
o.truncate(nblk * bsz); o.close()
