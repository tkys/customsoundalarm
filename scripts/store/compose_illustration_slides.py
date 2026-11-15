from PIL import Image, ImageDraw, ImageFilter
from collections import deque
SC='/private/tmp/claude-501/-Users-m1macmini-playground-CustomSoundAlarm/749669ab-6a01-4667-a34c-d867b37fc3e3/scratchpad/'
SH='/private/tmp/claude-501/shots/'
EX=SH+'export218/ios/iphone/1320x2868/'
OUT=SH+'final218/'
import os; os.makedirs(OUT,exist_ok=True)

def knockout(path):
    im=Image.open(path).convert('RGBA'); w,h=im.size; px=im.load()
    isbg=lambda p: min(p[:3])>=251 and max(p[:3])-min(p[:3])<=3
    seen=bytearray(w*h); q=deque()
    for x in range(w): q.extend([(x,0),(x,h-1)])
    for y in range(h): q.extend([(0,y),(w-1,y)])
    while q:
        x,y=q.popleft()
        if x<0 or y<0 or x>=w or y>=h or seen[y*w+x]: continue
        seen[y*w+x]=1
        if not isbg(px[x,y]): continue
        px[x,y]=(255,255,255,0)
        q.extend([(x+1,y),(x-1,y),(x,y+1),(x,y-1)])
    a=im.getchannel('A').filter(ImageFilter.GaussianBlur(1.2)); im.putalpha(a)
    # remove the white fringe: un-blend semi-transparent edge pixels from white
    px=im.load()
    for y in range(h):
        for x in range(w):
            r,g,b,al=px[x,y]
            if 0<al<255:
                f=al/255
                px[x,y]=tuple(max(0,min(255,int((c-(1-f)*255)/f))) for c in (r,g,b))+(al,)
    return im

def card(path, box, width, radius=44):
    im=Image.open(path).convert('RGB').crop(box)
    s=width/im.width; im=im.resize((width,int(im.height*s)),Image.LANCZOS)
    m=Image.new('L',im.size,0); ImageDraw.Draw(m).rounded_rectangle((0,0,im.width-1,im.height-1),radius=radius,fill=255)
    c=Image.new('RGBA',im.size,(0,0,0,0)); c.paste(im,(0,0),m)
    pad=60; sh=Image.new('RGBA',(im.width+pad*2,im.height+pad*2),(0,0,0,0))
    sm=Image.new('L',sh.size,0); ImageDraw.Draw(sm).rounded_rectangle((pad,pad+14,pad+im.width,pad+im.height+14),radius=radius,fill=70)
    sh=Image.new('RGBA',sh.size,(90,55,30,0)); sh.putalpha(sm.filter(ImageFilter.GaussianBlur(26)))
    sh.alpha_composite(c,(pad,pad)); return sh

def place(bg,img,x,y): bg.alpha_composite(img,(int(x),int(y)))

hero=knockout(SC+'onboarding_hero.png'); silent=knockout(SC+'onboarding_silent.png')
pl=Image.open(SC+'msa-playlist-illust-v2.png').convert('RGBA'); pl=pl.crop(pl.getchannel('A').point(lambda a:255 if a>20 else 0).getbbox())
for l in ['ja','en']:
    # 1
    bg=Image.open(EX+f'{l}/01-no-device.png').convert('RGBA'); W,H=bg.size
    h=hero.resize((W,int(hero.height*W/hero.width)),Image.LANCZOS); place(bg,h,0,H-h.height)
    c=card(SH+f'{l}-alarms.png',(59,510,1146,1290),980); place(bg,c,(W-c.width)/2,640)
    bg.convert('RGB').save(OUT+f'{l}-01.png')
    # 3
    bg=Image.open(EX+f'{l}/03-no-device.png').convert('RGBA')
    c=card(SH+f'{l}-playlist-order.png',(48,1100,1156,1712),960); place(bg,c,(W-c.width)/2,640)
    ph=H-1330; p=pl.resize((int(pl.width*ph/pl.height),ph),Image.LANCZOS); place(bg,p,(W-p.width)/2,H-ph-40)
    bg.convert('RGB').save(OUT+f'{l}-03.png')
    # 4
    bg=Image.open(EX+f'{l}/04-no-device.png').convert('RGBA')
    S=int(1254*1.32); s=silent.resize((S,S),Image.LANCZOS); place(bg,s,(W-S)/2,H-S)
    bg.convert('RGB').save(OUT+f'{l}-04.png')
    for n,src in [('02','02-device-bottom'),('05','05-device-bottom')]:
        Image.open(EX+f'{l}/{src}.png').convert('RGB').save(OUT+f'{l}-{n}.png')
# contact sheet
for l in ['ja','en']:
    ims=[Image.open(OUT+f'{l}-0{i}.png') for i in range(1,6)]
    tw=440; th=int(2868*tw/1320); sheet=Image.new('RGB',(tw*5+40*6,th+80),(255,255,255))
    for i,im in enumerate(ims): sheet.paste(im.resize((tw,th),Image.LANCZOS),(40+i*(tw+40),40))
    sheet.save(OUT+f'sheet-{l}.jpg',quality=88)
print('ok')
