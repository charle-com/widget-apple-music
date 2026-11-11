"""Pochettes fictives et état d'exemple pour la bannière du dépôt : formes abstraites, aucun visuel d'album réel.

Usage : covers.py <dossier des pochettes> <chemin de state.json>
"""
import json
import sys
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1800  # dessin en 3x, réduit à 600 px
OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vgrad(top, bottom):
    img = Image.new("RGB", (1, 256))
    a, b = rgb(top), rgb(bottom)
    for y in range(256):
        t = y / 255
        img.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    return img.resize((S, S), Image.BICUBIC)


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def over(base, top, blur=0):
    if blur:
        top = top.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(base.convert("RGBA"), top)


def finish(img, name, grain=9):
    img = img.convert("RGB").resize((600, 600), Image.LANCZOS)
    noise = Image.effect_noise((600, 600), grain).convert("RGB")
    img = ImageChops.add(img, noise, 1, -128)
    img.save(OUT / f"{name}.png")


def persiennes():
    img = vgrad("#2A0C09", "#5C1B10")
    glow = layer()
    ImageDraw.Draw(glow).ellipse((-300, 500, 1500, 2200), fill=(*rgb("#E86A1F"), 120))
    img = over(img, glow, 260)
    slats = layer()
    d = ImageDraw.Draw(slats)
    colors = ["#E27A26", "#E8862B", "#EE9432", "#F2A23A", "#F5AF48", "#F7BC58", "#F9C96C", "#FBD480", "#FDDF96"]
    for i, c in enumerate(colors):
        y = 330 + i * 138
        left, right, shear, h = 300, 1560, -190, 74
        d.polygon([(left, y), (right, y + shear), (right, y + shear + h), (left, y + h)], fill=(*rgb(c), 255))
    img = over(img, slats, 5)
    finish(img, "persiennes")


def vignes():
    img = vgrad("#17362A", "#254A33")
    l = layer()
    d = ImageDraw.Draw(l)
    d.ellipse((1050, 250, 1450, 650), fill=(*rgb("#F3E6C0"), 255))
    for box, c in [((-500, 900, 1500, 2600), "#2F6B3F"), ((500, 1050, 2600, 2700), "#4F8A46"),
                   ((-700, 1300, 1300, 2900), "#9DB556"), ((300, 1520, 2500, 3100), "#DCCB7C")]:
        d.ellipse(box, fill=(*rgb(c), 255))
    finish(over(img, l), "vignes")


def minuit():
    img = Image.new("RGB", (S, S), rgb("#0B1838"))
    l = layer()
    d = ImageDraw.Draw(l)
    d.ellipse((380, 300, 1420, 1340), fill=(*rgb("#F1EBDD"), 255))
    d.line((900, 820, 870, 400), fill=(*rgb("#0B1838"), 255), width=16)
    d.line((900, 820, 1130, 690), fill=(*rgb("#0B1838"), 255), width=16)
    d.ellipse((876, 796, 924, 844), fill=(*rgb("#0B1838"), 255))
    img = over(img, l)
    sea = layer()
    ImageDraw.Draw(sea).rectangle((0, 1040, S, S), fill=(*rgb("#2447D6"), 232))
    finish(over(img, sea), "minuit")


def paralleles():
    big = Image.new("RGB", (S * 2, S * 2), rgb("#E9E2D4"))
    d = ImageDraw.Draw(big)
    x, i = 0, 0
    while x < S * 2:
        d.rectangle((x, 0, x + 120, S * 2), fill=rgb("#E2452B") if i == 7 else rgb("#17130F"))
        x += 300
        i += 1
    big = big.rotate(34, resample=Image.BICUBIC)
    finish(big.crop((S // 2, S // 2, S // 2 + S, S // 2 + S)), "paralleles")


def soirs():
    img = Image.new("RGB", (S, S), rgb("#A80F45")).convert("RGBA")
    for box, c, a in [((-250, 420, 1050, 1720), "#FF6B3D", 235), ((560, 60, 1700, 1200), "#FFC145", 225),
                      ((820, 900, 1980, 2060), "#FF9FB5", 225)]:
        l = layer()
        ImageDraw.Draw(l).ellipse(box, fill=(*rgb(c), a))
        img = Image.alpha_composite(img, l)
    finish(img, "soirs")


def port():
    img = Image.new("RGB", (S, S), rgb("#F3DBBC"))
    d = ImageDraw.Draw(img)
    d.ellipse((560, 330, 1240, 1010), fill=rgb("#F26B4E"))
    for y, c in [(700, "#22868F"), (960, "#17707B"), (1220, "#115A65"), (1480, "#0C4650")]:
        d.rectangle((0, y, S, S), fill=rgb(c))
    d.rectangle((0, 1680, S, S), fill=rgb("#E8B982"))
    finish(img, "port")


def doux():
    img = Image.new("RGB", (S, S), rgb("#F6C9B0")).convert("RGBA")
    for box, c in [((-200, -100, 1000, 1100), "#C9B6E8"), ((800, 300, 2000, 1500), "#F9E7A6"),
                   ((200, 1000, 1400, 2200), "#F08A7B")]:
        l = layer()
        ImageDraw.Draw(l).ellipse(box, fill=(*rgb(c), 255))
        img = Image.alpha_composite(img, l.filter(ImageFilter.GaussianBlur(170)))
    finish(img, "doux", grain=12)


def phare():
    img = Image.new("RGB", (S, S), rgb("#0F0F12"))
    beam = layer()
    ImageDraw.Draw(beam).polygon([(360, 1440), (S + 100, 250), (S + 100, 1150)], fill=(*rgb("#F7D24A"), 255))
    img = over(img, beam, 3)
    l = layer()
    d = ImageDraw.Draw(l)
    d.rectangle((300, 1380, 420, S), fill=(*rgb("#F1EBDD"), 255))
    d.ellipse((280, 1360, 440, 1520), fill=(*rgb("#F1EBDD"), 255))
    finish(over(img, l), "phare")


for f in (persiennes, vignes, minuit, paralleles, soirs, port, doux, phare):
    f()

# Pistes fictives : la première est en lecture depuis 74 s, les autres forment la file d'attente.
TRACKS = [
    ("Lumière d'été", "Les Persiennes", "Volets clos", 201, "persiennes"),
    ("Rue des Vignes", "Mona Vale", "Coteaux", 187, "vignes"),
    ("Minuit moins une", "Cargo Bleu", "Quai 9", 224, "minuit"),
    ("Parallèles", "Hôtel Minéral", "Lignes", 176, "paralleles"),
    ("Les Grands Soirs", "Vitrine", "Néons", 243, "soirs"),
    ("Avenue du Port", "Mona Vale", "Marée basse", 198, "port"),
    ("Tout doux", "Cargo Bleu", "Sieste", 165, "doux"),
    ("Le Phare", "Vitrine", "Veilleuse", 233, "phare"),
    ("Septembre", "Les Persiennes", "Volets clos", 212, "persiennes"),
]
state = {
    "anchor": time.time(), "elapsed": 74, "isPlaying": True,
    "tracks": [dict(title=t, artist=a, album=al, duration=d, artKey=k) for t, a, al, d, k in TRACKS],
}
Path(sys.argv[2]).parent.mkdir(parents=True, exist_ok=True)
Path(sys.argv[2]).write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
