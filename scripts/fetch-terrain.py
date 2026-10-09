#!/usr/bin/env python3
"""Download GSI DEM10B PNG tiles and produce a local height grid (requires Pillow)."""
from pathlib import Path
import hashlib
import json
import math
import urllib.request
from datetime import datetime, timezone
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'public' / 'terrain'
RAW = OUT / 'tiles'
Z = 14
X0, X1 = 14459, 14465
Y0, Y1 = 6394, 6398
STRIDE = 8  # ~61m spacing at this latitude, sampled from DEM10B tiles

def decode(r, g, b):
    value = (r << 16) + (g << 8) + b
    if value == 1 << 23:
        return None
    return (value if value < 1 << 23 else value - (1 << 24)) / 100

def latitude(y):
    return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / 2**Z))))

def main():
    RAW.mkdir(parents=True, exist_ok=True)
    tiles, sources = {}, []
    for y in range(Y0, Y1+1):
        for x in range(X0, X1+1):
            url = f'https://cyberjapandata.gsi.go.jp/xyz/dem_png/{Z}/{x}/{y}.png'
            dest = RAW / f'{Z}-{x}-{y}.png'
            if not dest.exists():
                req = urllib.request.Request(url, headers={'User-Agent':'WatchClimberPrototype/0.1'})
                with urllib.request.urlopen(req, timeout=30) as response:
                    data = response.read()
                with Image.open(__import__('io').BytesIO(data)) as im:
                    assert im.size == (256,256), f'Unexpected tile dimensions: {url}'
                dest.write_bytes(data)
            data = dest.read_bytes()
            im = Image.open(dest).convert('RGB')
            assert im.size == (256,256)
            tiles[(x,y)] = im
            sources.append({'url':url,'file':f'tiles/{dest.name}','sha256':hashlib.sha256(data).hexdigest()})
            print(f'{x}/{y}: {len(data)} bytes', flush=True)
    columns = (X1-X0+1)*256//STRIDE
    rows = (Y1-Y0+1)*256//STRIDE
    heights = []
    for row in range(rows):
        py = row*STRIDE
        for col in range(columns):
            px = col*STRIDE
            rgb = tiles[(X0+px//256,Y0+py//256)].getpixel((px%256,py%256))
            h = decode(*rgb)
            heights.append(None if h is None else round(h,1))
    valid = [h for h in heights if h is not None]
    # Grid bounds refer to sampled pixel centers, not tile edges.
    west = (X0*256+.5)/(2**Z*256)*360-180
    east = (X0*256+(columns-1)*STRIDE+.5)/(2**Z*256)*360-180
    north = latitude(Y0+.5/256)
    south = latitude(Y0+((rows-1)*STRIDE+.5)/256)
    payload = {'name':'五竜岳周辺','source':'国土地理院 DEM10B PNG標高タイル',
        'sourceUrl':'https://maps.gsi.go.jp/development/ichiran.html',
        'specUrl':'https://maps.gsi.go.jp/development/demtile.html',
        'fetchedAt':datetime.now(timezone.utc).isoformat(),
        'zoom':Z,'tileOrigin':[X0,Y0],'pixelStride':STRIDE,
        'columns':columns,'rows':rows,'bounds':{'west':west,'east':east,'north':north,'south':south},
        'heightRange':[min(valid),max(valid)],'missingCells':len(heights)-len(valid),
        'processing':'PNG標高値を復号し8画素間隔で抽出。欠損値はnull。水平間隔は約61m。',
        'heights':heights}
    (OUT/'goryu.json').write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n')
    (OUT/'sources.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in payload.items() if k!='heights'},ensure_ascii=False))

if __name__ == '__main__':
    main()
