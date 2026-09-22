"""TokenMini selected four-slice logo: deterministic vector masters and exports.

This constructs code-native vector paths; it never retouches the reference PNG.
Run: DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 build_assets.py
"""
from pathlib import Path
import math
import json
import hashlib
import xml.etree.ElementTree as ET
import cairosvg

ROOT = Path(__file__).resolve().parent
INK, GREEN, PAPER, WHITE = '#18211C', '#68B45B', '#F5F6EF', '#FFFFFF'
ANGLE = 25
SLOPE = math.tan(math.radians(ANGLE))
WIDTHS = [88, 53, 32, 21]
HEIGHTS = [160, 128, 64, 26]
XS = [0, 104, 173, 221]
GAP = 16
MARK_W, MARK_H = 242, 160 + 88 * SLOPE

def n(v):
    return f'{v:.4f}'.rstrip('0').rstrip('.')

def rounded_polygon(points, radius):
    """Circular corner fillets, with tangents on the unrounded edge lines."""
    before, after = [], []
    for i, p in enumerate(points):
        prev, nxt = points[i-1], points[(i+1) % len(points)]
        a, b = (prev[0]-p[0], prev[1]-p[1]), (nxt[0]-p[0], nxt[1]-p[1])
        la, lb = math.hypot(*a), math.hypot(*b)
        ua, ub = (a[0]/la,a[1]/la), (b[0]/lb,b[1]/lb)
        theta = math.acos(max(-1,min(1,ua[0]*ub[0]+ua[1]*ub[1])))
        d = min(radius/math.tan(theta/2),la*.35,lb*.35)
        before.append((p[0]+ua[0]*d,p[1]+ua[1]*d))
        after.append((p[0]+ub[0]*d,p[1]+ub[1]*d))
    d = f'M{n(after[0][0])},{n(after[0][1])}'
    for i in [1,2,3,0]:
        d += f'L{n(before[i][0])},{n(before[i][1])}A{n(radius)},{n(radius)} 0 0 1 {n(after[i][0])},{n(after[i][1])}'
    return d+'Z'

def slice_path(x, width, height, end_y, radius):
    bottom = end_y + width*SLOPE
    pts = [(x,bottom-height),(x+width,end_y-height),(x+width,end_y),(x,bottom)]
    return rounded_polygon(pts,radius)

def mark(ink=INK, accent=False):
    return ''.join(f'<path data-slice="{i+1}" fill="{GREEN if accent and i==1 else ink}" d="{slice_path(x,w,h,160,w*.06)}"/>' for i,(x,w,h) in enumerate(zip(XS,WIDTHS,HEIGHTS)))

# Redrawn outlines following the chosen squared, light geometric lettering.
# No live font, text node, external font, or raster image is used in logo assets.
GLYPHS = {
 'T': (86,'M0 0H86V10H48V112H38V10H0Z'),
 'o': (78,'M24 32H54Q78 32 78 56V88Q78 112 54 112H24Q0 112 0 88V56Q0 32 24 32ZM24 42Q10 42 10 56V88Q10 102 24 102H54Q68 102 68 88V56Q68 42 54 42Z'),
 'k': (72,'M0 0H10V72L53 32H67L33 65L72 112H59L26 72L10 87V112H0Z'),
 'e': (78,'M74 102V112H24Q0 112 0 88V56Q0 32 24 32H54Q78 32 78 56V78H10V88Q10 102 24 102ZM10 68H68V56Q68 42 54 42H24Q10 42 10 56Z'),
 'n': (72,'M0 32H10V39Q17 32 29 32H48Q72 32 72 57V112H62V57Q62 42 48 42H27Q10 42 10 58V112H0Z'),
 'M': (96,'M0 112V0H12L48 74L84 0H96V112H86V20L53 87H43L10 20V112Z'),
 'i': (10,'M0 0H10V12H0ZM0 32H10V112H0Z'),
}
TRACKING = [4,14,10,14,22,14,16,14]
WORD_W = sum(GLYPHS[c][0] for c in 'TokenMini') + sum(TRACKING)

def wordmark(color=INK):
    x, paths = 0, []
    for i,c in enumerate('TokenMini'):
        w,d=GLYPHS[c]
        paths.append(f'<path data-letter="{c}" transform="translate({x},0)" fill="{color}" fill-rule="evenodd" d="{d}"/>')
        x += w + (TRACKING[i] if i < 8 else 0)
    return ''.join(paths)

def svg(w,h,body,title,background=None):
    bg = f'<rect width="{n(w)}" height="{n(h)}" fill="{background}"/>' if background else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{n(w)}" height="{n(h)}" viewBox="0 0 {n(w)} {n(h)}" role="img"><title>{title}</title>{bg}{body}</svg>'

def group(body,x=0,y=0,scale=1):
    return f'<g transform="translate({n(x)} {n(y)}) scale({n(scale)})">{body}</g>'

ASSETS = {}
def add_asset(name,w,h,body,title,bg=None):
    data = svg(w,h,body,title,bg)
    p=ROOT/'svg'/f'{name}.svg'
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(data)
    ASSETS[name]={'path':p,'width':w,'height':h}
    return data

for variant,ink,accent in [('black',INK,False),('white',WHITE,False),('color',INK,True),('color-reverse',WHITE,True)]:
    add_asset(f'mark-{variant}',MARK_W+32,MARK_H+32,group(mark(ink,accent),16,16),f'TokenMini symbol, {variant}')
    w=32+MARK_W+40+WORD_W+32; h=MARK_H+64
    body=group(mark(ink,accent),32,32)+group(wordmark(ink),32+MARK_W+40,32+(MARK_H-112)/2)
    add_asset(f'logo-horizontal-{variant}',w,h,body,f'TokenMini horizontal logo, {variant}')

for variant,ink in [('black',INK),('white',WHITE)]:
    add_asset(f'wordmark-{variant}',WORD_W+64,176,group(wordmark(ink),32,32),f'TokenMini wordmark, {variant}')
    w=WORD_W+64; h=32+MARK_H*1.2+40+112+32
    body=group(mark(ink), (w-MARK_W*1.2)/2,32,1.2)+group(wordmark(ink),32,32+MARK_H*1.2+40)
    add_asset(f'logo-stacked-{variant}',w,h,body,f'TokenMini stacked logo, {variant}')

# The right endpoint of every lower edge shares one baseline in each version.
# Dedicated optical masters keep the fourth slice >= 2 CSS pixels wide at 16–24px.
SMALL={
 16:([1,6,10,13],[4,3,2,2],[10.5,8.3,4.5,2.5],12),
 20:([1,7.5,12.5,16.5],[5,3.5,2.5,2],[14,11,6,3],16),
 22:([1,8.5,14,18.5],[6,4,3,2],[15,12,6.5,3.5],17.5),
 24:([1.5,9.5,15.5,20],[6.5,4.5,3,2.5],[16.5,13,7,3.75],19),
}
for size,(xs,ws,hs,base) in SMALL.items():
    for variant,color in [('black',INK),('white',WHITE)]:
        body=''.join(f'<path data-slice="{i+1}" fill="{color}" d="{slice_path(x,w,h,base,min(.45,w*.12))}"/>' for i,(x,w,h) in enumerate(zip(xs,ws,hs)))
        add_asset(f'mark-optical-{size}-{variant}',size,size,body,f'TokenMini optical symbol, {size}px, {variant}')

# Clear-space convention x=16. This guide includes editable annotation text,
# while every logo master remains pure filled paths.
construction=group(mark(),60,54)
for x,w,h in zip(XS,WIDTHS,HEIGHTS):
    y=160+w*SLOPE-h
    construction+=f'<path d="M{n(60+x)} {n(54+y)}l{w} {n(-w*SLOPE)}" fill="none" stroke="#70876B" stroke-width=".6"/>'
construction+=f'<path d="M44 214H320" stroke="#7E9872" stroke-width="1" stroke-dasharray="4 4"/>'
construction+='<g font-family="Arial,sans-serif" font-size="12" fill="#52624C"><text x="350" y="80">4 slices / 25°</text><text x="350" y="108">Equal gaps: 16u</text><text x="350" y="136">Widths: 88 / 53 / 32 / 21u</text><text x="350" y="164">Corner radius: width × 0.06</text><text x="350" y="192">Lower-right endpoints aligned</text></g>'
add_asset('construction-guide',650,310,construction,'TokenMini construction guide',PAPER)

# Opaque presentation board: generated directly from the exact SVG masters.
board=f'<rect x="56" y="64" width="1424" height="1" fill="#BDC4B8"/>'
board+='<g font-family="Arial,sans-serif" fill="#58624F" font-size="17" letter-spacing="2"><text x="56" y="45">TOKENMINI / LOGO STANDARD 01</text><text x="1160" y="45">SELECTED DIRECTION</text></g>'
scale=1.18
body=mark()+group(wordmark(),MARK_W+40,(MARK_H-112)/2)
board+=group(body,(1536-(MARK_W+40+WORD_W)*scale)/2,155,scale)
board+='<path d="M56 484H1480" stroke="#BDC4B8"/>'
board+=group(mark(),157,548,.90)
board+='<rect x="598" y="524" width="340" height="250" rx="18" fill="#18211C"/>'
board+=group(mark(WHITE),660,559,.9)
board+=group(mark(INK,True),1160,548,.9)
board+='<g font-family="Arial,sans-serif" font-size="15" fill="#58624F"><text x="157" y="808">MONO / LIGHT</text><text x="660" y="808">MONO / DARK</text><text x="1160" y="808">BRAND ACCENT</text></g>'
board+='<path d="M56 846H1480" stroke="#BDC4B8"/><g font-family="Arial,sans-serif" font-size="15" fill="#58624F"><text x="56" y="886">One master geometry. Four slices. Fixed proportions.</text><text x="56" y="918">16 / 20 / 22 / 24 px optical versions supplied separately.</text></g>'
for i,size in enumerate([16,20,22,24]):
    xs,ws,hs,base=SMALL[size]
    body=''.join(f'<path fill="{INK}" d="{slice_path(x,w,h,base,min(.45,w*.12))}"/>' for x,w,h in zip(xs,ws,hs))
    board+=group(body,1030+i*110,866,2)
    board+=f'<text x="{1030+i*110}" y="945" font-family="Arial,sans-serif" font-size="13" fill="#58624F">{size}px ×2</text>'
add_asset('brand-preview',1536,984,board,'TokenMini normalized logo presentation',PAPER)

pngdir=ROOT/'png'; pdfdir=ROOT/'pdf'
pngdir.mkdir(exist_ok=True);pdfdir.mkdir(exist_ok=True)
for name,meta in ASSETS.items():
    data=meta['path'].read_bytes()
    if name.startswith('mark-optical-'):
        for factor in [1,2,3]:
            size=round(meta['width']*factor)
            out=pngdir/f'{name}@{factor}x.png'
            cairosvg.svg2png(bytestring=data,write_to=str(out),output_width=size,output_height=size)
    else:
        width=1536 if name=='brand-preview' else (2048 if name.startswith('logo-') else 1024)
        cairosvg.svg2png(bytestring=data,write_to=str(pngdir/f'{name}.png'),output_width=width)
        if name.startswith('logo-') or name in ['mark-black','mark-color','wordmark-black','brand-preview']:
            cairosvg.svg2pdf(bytestring=data,write_to=str(pdfdir/f'{name}.pdf'))

selection={
 'selectedSource':'reference/selected-original.png',
 'selectedSourceOriginalFilename':'exec-814a4e2f-b9f8-48e6-a32e-56ea79a3fffe.png',
 'selectedSourceSHA256':hashlib.sha256((ROOT/'reference/selected-original.png').read_bytes()).hexdigest(),
 'status':'direction-selected-by-user; normalized-assets-delivered',
 'selectedDescription':'Four descending upright slices with slanted top and bottom edges',
 'brandName':'TokenMini','businessScope':['Token monitoring','Token sales'],
 'angleDegrees':ANGLE,'sliceWidths':WIDTHS,'sliceHeights':HEIGHTS,'gap':GAP,
 'roundingRadiusRule':'width * 0.06, circular tangent fillets',
 'lowerRightBaseline':160,'clearSpaceRecommended':32,
 'colors':{'ink':INK,'green':GREEN,'paper':PAPER,'white':WHITE},
 'greenSliceIndexOneBased':2,'wordmarkOutlines':'redrawn geometric paths; no font dependency',
 'smallOpticalSizes':list(SMALL),'minimumRecommendedSymbolCSSPixels':16,
 'minimumRecommendedHorizontalWidthCSSPixels':180,
 'productionAppAssetsChanged':False
}
(ROOT/'specification.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2)+'\n')

# Structural checks guard asset portability; visual checks are recorded separately.
for name,meta in ASSETS.items():
    root=ET.fromstring(meta['path'].read_text())
    if name not in ['brand-preview','construction-guide']:
        assert not root.findall('.//{http://www.w3.org/2000/svg}text'),name
        assert not root.findall('.//{http://www.w3.org/2000/svg}image'),name
        assert not root.findall('.//{http://www.w3.org/2000/svg}filter'),name
        slices=root.findall('.//*[@data-slice]')
        assert len(slices) in [0,4],(name,len(slices))
print(json.dumps({'svg':len(ASSETS),'png':len(list(pngdir.glob('*.png'))),'pdf':len(list(pdfdir.glob('*.pdf'))),'wordmarkWidth':WORD_W,'masterBounds':[MARK_W,MARK_H]},indent=2))
