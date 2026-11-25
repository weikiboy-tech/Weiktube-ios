#!/usr/bin/env python3
"""Render the original Android vector exactly; no generated or substituted branding.
Requires Pillow only to regenerate; checked-in PNGs are normal Xcode assets.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
assets=ROOT/'Weiktube/Assets.xcassets'
icons=assets/'AppIcon.appiconset'
icons.mkdir(parents=True,exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2)+'\n')
entries=[]
slots=[('iphone',20,[2,3]),('iphone',29,[2,3]),('iphone',40,[2,3]),('iphone',60,[2,3]),
       ('ipad',20,[1,2]),('ipad',29,[1,2]),('ipad',40,[1,2]),('ipad',76,[1,2]),('ipad',83.5,[2]),('ios-marketing',1024,[1])]
for idiom,size,scales in slots:
    for scale in scales:
        pixels=int(size*scale); filename=f'Icon-{pixels}.png'
        canvas=Image.new('RGB',(pixels*4,pixels*4),'#10151D')
        draw=ImageDraw.Draw(canvas)
        for polygon in [[(27,28),(44,38),(44,70),(27,80)],[(49,28),(83,54),(49,80)]]:
            draw.polygon([(x*pixels*4/108,y*pixels*4/108) for x,y in polygon],fill='#65D8C8')
        canvas.resize((pixels,pixels),Image.Resampling.LANCZOS).save(icons/filename)
        entries.append({'idiom':idiom,'size':f'{size:g}x{size:g}','scale':f'{scale}x','filename':filename})
(icons/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2)+'\n')
accent=assets/'AccentColor.colorset';accent.mkdir(exist_ok=True)
def components(r,g,b):return {'color-space':'srgb','components':{'alpha':'1.000','red':f'{r/255:.5f}','green':f'{g/255:.5f}','blue':f'{b/255:.5f}'}}
(accent/'Contents.json').write_text(json.dumps({'colors':[{'idiom':'universal','color':components(0,107,96)}, {'idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}],'color':components(101,216,200)}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
print(f'Generated {len(entries)} icon slots from the original 108×108 Android paths.')
