"""מכין חלופות וי״ו קטיעא בגופני Culmus ובמקורות UFO של אוצריא אשורית."""

from __future__ import annotations

import argparse
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace

import pathops
from fontTools.misc import plistlib
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.pointPen import SegmentToPointPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import otTables
from fontTools.ufoLib.glifLib import GlyphSet

ROOT = Path(__file__).resolve().parents[2]
VARIANTS = (
    "small", "yod", "short", "split", "splitDiagonal", "splitHigh",
    "shortTail", "smallTail", "bridge", "bridgeDiagonal", "insetDiagonal",
)
CODES = dict(zip(VARIANTS, range(0xE140, 0xE140 + len(VARIANTS))))
FONTS = (
    "fonts/tikkun_korim/Ashkenazi-Stam.ttf",
    "fonts/tikkun_korim/Sefardi-Stam.ttf",
    "fonts/KeterYG-Medium.ttf",
)


def outline(glyphs, name: str) -> pathops.Path:
    result = pathops.Path()
    glyphs[name].draw(result.getPen(glyphs))
    return result


def polygon(points) -> pathops.Path:
    result = pathops.Path()
    result.moveTo(*points[0])
    for point in points[1:]:
        result.lineTo(*point)
    result.close()
    return result


def rectangle(left, bottom, right, top) -> pathops.Path:
    return polygon(((left, bottom), (right, bottom), (right, top), (left, top)))


def combine(a, b, operation) -> pathops.Path:
    return pathops.op(a, b, operation)


def variants(glyphs, vav: str, yod: str, advance: float, yod_advance: float):
    source = outline(glyphs, vav)
    left, bottom, right, top = source.bounds
    height = top - bottom
    margin = height
    short = combine(source, rectangle(left - margin, bottom + height * .28,
                                      right + margin, top + margin), pathops.PathOp.INTERSECTION)
    small = source.transform(.7, 0, 0, .7, advance * .15, top * .3)

    def band(fraction, diagonal=False):
        middle = bottom + height * fraction
        sample = combine(source, rectangle(left - margin, middle - height * .03,
                                           right + margin, middle + height * .03),
                         pathops.PathOp.INTERSECTION)
        x0, _, x1, _ = sample.bounds
        center = (x0 + x1) / 2
        slope = .35 if diagonal else 0
        xa, xb = left - margin, right + margin
        ya, yb = middle + slope * (xa - center), middle + slope * (xb - center)
        cut = polygon(((xa, ya - height * .03), (xb, yb - height * .03),
                       (xb, yb + height * .03), (xa, ya + height * .03)))
        return cut, x0, x1

    def split(fraction=.48, diagonal=False, bridge=False, inset=False):
        cut, x0, x1 = band(fraction, diagonal)
        hair = max(height * .012, (x1 - x0) * .10)
        if inset:
            cut = combine(cut, rectangle(x0 + hair, bottom - margin, x1 - hair, top + margin),
                          pathops.PathOp.INTERSECTION)
        elif bridge:
            center = (x0 + x1) / 2
            cut = combine(cut, rectangle(center - hair / 2, bottom - margin,
                                         center + hair / 2, top + margin), pathops.PathOp.DIFFERENCE)
        return combine(source, cut, pathops.PathOp.DIFFERENCE)

    tail = combine(source, rectangle(left - margin, bottom - margin,
                                     right + margin, bottom + height * .10), pathops.PathOp.INTERSECTION)
    result = {
        "small": small,
        "yod": outline(glyphs, yod).transform(1, 0, 0, 1, (advance - yod_advance) / 2, 0),
        "short": short,
        "split": split(),
        "splitDiagonal": split(diagonal=True),
        "splitHigh": split(.64),
        "shortTail": split(.15),
        "smallTail": combine(small, tail, pathops.PathOp.UNION),
        "bridge": split(bridge=True),
        "bridgeDiagonal": split(diagonal=True, bridge=True),
        "insetDiagonal": split(diagonal=True, inset=True),
    }
    return {f"vav.ketia.{name}": (CODES[name], result[name]) for name in VARIANTS}


def copy_anchors(font: TTFont, vav: str, names: list[str]) -> None:
    """חלופה היא אות בסיס עם אותם עוגני ניקוד, ולא תו פרטי חסר סיווג."""
    def classes(node):
        if isinstance(node, list):
            for child in node:
                classes(child)
        elif hasattr(node, "__dict__"):
            definitions = getattr(node, "classDefs", None)
            if definitions is not None and vav in definitions:
                definitions.update({name: definitions[vav] for name in names})
            for child in vars(node).values():
                if isinstance(child, list) or hasattr(child, "__dict__"):
                    classes(child)

    for tag in ("GDEF", "GPOS"):
        if tag in font:
            classes(font[tag].table)
    if "GPOS" not in font:
        return
    for lookup in font["GPOS"].table.LookupList.Lookup:
        for subtable in lookup.SubTable:
            subtable = getattr(subtable, "ExtSubTable", subtable)
            if lookup.LookupType in (7, 8) and subtable.Format == 3:
                for attribute in ("Coverage", "BacktrackCoverage", "InputCoverage", "LookAheadCoverage"):
                    for context in getattr(subtable, attribute, []):
                        if vav in context.glyphs:
                            context.glyphs = sorted(set(context.glyphs) | set(names), key=font.getGlyphID)
            coverage = getattr(subtable, "BaseCoverage", None)
            if coverage is None or vav not in coverage.glyphs:
                continue
            records = dict(zip(coverage.glyphs, subtable.BaseArray.BaseRecord))
            for name in names:
                records[name] = deepcopy(records[vav])
            coverage.glyphs = sorted(records, key=font.getGlyphID)
            subtable.BaseArray.BaseRecord = [records[name] for name in coverage.glyphs]
            subtable.BaseArray.BaseCount = len(records)


def copy_compositions(font: TTFont, vav: str, names: list[str]) -> None:
    """כתר מאחד וי״ו וחולם/שורוק; החלופות צריכות את אותו צירוף ומידותיו."""
    if "GSUB" not in font:
        return
    ligatures = {name: [] for name in names}
    compositions = {
        (item.LigGlyph, tuple(item.Component))
        for lookup in font["GSUB"].table.LookupList.Lookup
        for table in lookup.SubTable
        for item in getattr(table, "ligatures", {}).get(vav, [])
    }
    for original, components in sorted(compositions):
        glyph = font["glyf"][original]
        if not glyph.isComposite() or not any(c.glyphName == vav for c in glyph.components):
            continue
        new_names = [f"{name}.{original}" for name in names]
        order = font.getGlyphOrder()
        font.setGlyphOrder(order + [name for name in new_names if name not in order])
        for base, name in zip(names, new_names):
            alternate = deepcopy(glyph)
            for component in alternate.components:
                if component.glyphName == vav:
                    component.glyphName = base
            alternate.recalcBounds(font["glyf"])
            font["glyf"][name] = alternate
            font["hmtx"][name] = (font["hmtx"][original][0], alternate.xMin)
            ligature = otTables.Ligature()
            ligature.LigGlyph, ligature.Component, ligature.CompCount = name, list(components), len(components) + 1
            ligatures[base].append(ligature)
        copy_anchors(font, original, new_names)
    if not any(ligatures.values()):
        return
    table = otTables.LigatureSubst()
    table.ligatures = ligatures
    lookup = otTables.Lookup()
    lookup.LookupType, lookup.LookupFlag, lookup.SubTableCount = 4, 0, 1
    lookup.SubTable = [table]
    gsub = font["GSUB"].table
    lookups = gsub.LookupList.Lookup
    index = next((i for i, item in enumerate(lookups) if item.LookupType == 4
                  and any(getattr(s, "ligatures", {}) == ligatures for s in item.SubTable)), None)
    if index is None:
        index = len(lookups)
        lookups.append(lookup)
    gsub.LookupList.LookupCount = len(lookups)
    for record in gsub.FeatureList.FeatureRecord:
        if record.FeatureTag == "ccmp" and index not in record.Feature.LookupListIndex:
            record.Feature.LookupListIndex.append(index)
            record.Feature.LookupCount = len(record.Feature.LookupListIndex)


def patch_ttf(path: Path) -> None:
    font = TTFont(path, recalcTimestamp=False, recalcBBoxes=False)
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    vav, yod = cmap[0x05D5], cmap[0x05D9]
    width = font["hmtx"][vav][0]
    shapes = variants(glyphs, vav, yod, width, font["hmtx"][yod][0])
    order = font.getGlyphOrder()
    font.setGlyphOrder(order + [name for name in shapes if name not in order])
    for name, (code, shape) in shapes.items():
        pen = TTGlyphPen(None)
        shape.draw(Cu2QuPen(pen, max_err=font["head"].unitsPerEm / 4096))
        glyph = pen.glyph()
        glyph.recalcBounds(font["glyf"])
        font["glyf"][name] = glyph
        font["hmtx"][name] = (width, glyph.xMin)
        for table in font["cmap"].tables:
            if table.isUnicode() and table.format in (4, 12):
                if code in table.cmap and table.cmap[code] != name:
                    raise ValueError(f"מיפוי תפוס: {path} U+{code:04X}")
                table.cmap[code] = name
    copy_anchors(font, vav, list(shapes))
    copy_compositions(font, vav, list(shapes))
    notice = "\nVav ketia alternates: Otzaria Project, 2026; same license and embedding exception."
    for record in font["name"].names:
        if record.nameID == 0 and notice.strip() not in record.toUnicode():
            record.string = (record.toUnicode() + notice).encode(record.getEncoding())
        if record.nameID == 5 and "Otzaria ketia" not in record.toUnicode():
            record.string = (record.toUnicode().strip() + "; Otzaria ketia 1").encode(record.getEncoding())
    font.save(path)
    print("נוספו חלופות:", path)


def patch_ashurit(root: Path) -> None:
    for ufo in sorted((root / "sources").glob("*.ufo")):
        glyphs = GlyphSet(ufo / "glyphs", ufoFormatVersion=3)
        unicodes = glyphs.getUnicodes()
        vav = next(name for name, codes in unicodes.items() if 0x05D5 in codes)
        yod = next(name for name, codes in unicodes.items() if 0x05D9 in codes)
        original, yod_data = SimpleNamespace(), SimpleNamespace()
        glyphs.readGlyph(vav, original)
        glyphs.readGlyph(yod, yod_data)
        shapes = variants(glyphs, vav, yod, original.width, yod_data.width)
        for name, (code, shape) in shapes.items():
            if any(code in codes and other != name for other, codes in unicodes.items()):
                raise ValueError(f"מיפוי תפוס: {ufo} U+{code:04X}")
            glyph = SimpleNamespace(width=original.width, unicodes=[code])
            glyphs.writeGlyph(name, glyph, lambda pen, p=shape: p.draw(SegmentToPointPen(pen)))
        glyphs.writeContents()
        lib_path = ufo / "lib.plist"
        lib = plistlib.loads(lib_path.read_bytes())
        order = lib["public.glyphOrder"]
        order.extend(name for name in shapes if name not in order)
        lib_path.write_bytes(plistlib.dumps(lib, sort_keys=False))
        layout = ufo.with_name(ufo.stem + "-layout.ttx")
        if layout.exists():
            font = TTFont(root / "package" / "lib" / (ufo.stem + ".otf"))
            font.setGlyphOrder(font.getGlyphOrder() + [name for name in shapes if name not in font.getGlyphOrder()])
            font.importXML(layout)
            copy_anchors(font, vav, list(shapes))
            font.saveXML(layout, tables=[tag for tag in ("GSUB", "GPOS", "GDEF") if tag in font])
        print("נוספו מקורות:", ufo.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ashurit-source", type=Path)
    options = parser.parse_args()
    for relative in FONTS:
        patch_ttf(ROOT / relative)
    if options.ashurit_source:
        patch_ashurit(options.ashurit_source)
