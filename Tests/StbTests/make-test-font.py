# Makes Resources/squares.ttf, the font StbTrueTypeTests read, with fontTools:
#
#     python3 -m pip install fonttools
#     python3 Tests/StbTests/make-test-font.py
#
# 1000 units to the em, 800 above the baseline and 200 below. "A" is a
# 500-unit square and "B" a 500 x 700 rectangle, each 100 units in and 700
# across, and the space is empty and 500 across. A is kerned 100 units
# closer to B.

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables._k_e_r_n import KernTable_format_0


def rectangle(x0, y0, x1, y1):
    pen = TTGlyphPen(None)
    pen.moveTo((x0, y0))
    pen.lineTo((x0, y1))
    pen.lineTo((x1, y1))
    pen.lineTo((x1, y0))
    pen.closePath()
    return pen.glyph()


builder = FontBuilder(1000, isTTF=True)
builder.setupGlyphOrder([".notdef", "space", "A", "B"])
builder.setupCharacterMap({0x20: "space", 0x41: "A", 0x42: "B"})
builder.setupGlyf({
    ".notdef": TTGlyphPen(None).glyph(),
    "space": TTGlyphPen(None).glyph(),
    "A": rectangle(100, 0, 600, 500),
    "B": rectangle(100, 0, 600, 700),
})
builder.setupHorizontalMetrics({".notdef": (500, 0), "space": (500, 0), "A": (700, 100), "B": (700, 100)})
builder.setupHorizontalHeader(ascent=800, descent=-200)
builder.setupNameTable({"familyName": "Squares", "styleName": "Regular"})
builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
builder.setupPost()

kern = newTable("kern")
kern.version = 0
subtable = KernTable_format_0()
subtable.version = 0
subtable.coverage = 1
subtable.kernTable = {("A", "B"): -100}
kern.kernTables = [subtable]
builder.font["kern"] = kern

builder.save(Path(__file__).parent / "Resources" / "squares.ttf")
