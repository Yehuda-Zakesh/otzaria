"""בדיקות למיפוי, לצורה, למידות ולניקוד של חלופות וי״ו קטיעא."""

import argparse
import hashlib
import json
from pathlib import Path
import unittest
import unicodedata

import pathops
import uharfbuzz as hb
from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont

from prepare_vav_ketia import CODES, FONTS, ROOT, outline, rectangle

ORIGINAL = {
    FONTS[0]: "ebf53d1db56f73af761fdfc26c633b48b31418b63c89ca1b2592de2743de4170",
    FONTS[1]: "3c6c8b10cba5f086190981eb317b4e9f0e482e5beb99a16c0620a3d4f3cd6d2e",
    FONTS[2]: "3bcd62824a547d0b707f58616412fa41a618f01a67508315ad19fcd933e1305d",
}
PATHS = [ROOT / name for name in FONTS]


def shaped(path, codes):
    font = hb.Font(hb.Face(path.read_bytes()))
    buffer = hb.Buffer()
    buffer.add_codepoints(codes)
    buffer.direction, buffer.script, buffer.language = "rtl", "Hebr", "he"
    hb.shape(font, buffer)
    return [(p.x_advance, p.y_advance, p.x_offset, p.y_offset) for p in buffer.glyph_positions]


class VavKetiaTest(unittest.TestCase):
    def test_original_glyphs_unchanged(self):
        for relative, expected in ORIGINAL.items():
            with self.subTest(font=relative):
                font = TTFont(ROOT / relative)
                glyphs = font.getGlyphSet()
                records = []
                for name in font.getGlyphOrder():
                    if name.startswith("vav.ketia."):
                        continue
                    pen = RecordingPen()
                    glyphs[name].draw(pen)
                    records.append((name, font["hmtx"][name], pen.value))
                self.assertEqual(hashlib.sha256(json.dumps(records).encode()).hexdigest(), expected)

    def test_mapping_width_and_visible_distinct_outlines(self):
        for path in PATHS:
            font = TTFont(path)
            glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
            signatures = set()
            for variant, code in CODES.items():
                with self.subTest(font=path.name, variant=variant):
                    name = cmap[code]
                    self.assertEqual(font["hmtx"][name][0], font["hmtx"][cmap[0x05D5]][0])
                    shape = outline(glyphs, name)
                    self.assertGreater(abs(shape.area), 0)
                    self.assertLessEqual(shape.bounds[3], font["OS/2"].usWinAscent)
                    self.assertGreaterEqual(shape.bounds[1], -font["OS/2"].usWinDescent)
                    pen = RecordingPen()
                    shape.draw(pen)
                    signatures.add(repr(pen.value))
            self.assertEqual(len(signatures), len(CODES), path.name)

    def test_cut_and_connected_forms_differ_in_stem(self):
        for path in PATHS:
            font = TTFont(path)
            glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
            left, bottom, right, top = outline(glyphs, cmap[0x05D5]).bounds
            height = top - bottom
            band = rectangle(left - height, bottom + .478 * height,
                             right + height, bottom + .482 * height)
            for name, connected in (("split", False), ("bridge", True)):
                with self.subTest(font=path.name, variant=name):
                    shape = outline(glyphs, cmap[CODES[name]])
                    area = abs(pathops.op(shape, band, pathops.PathOp.INTERSECTION).area)
                    self.assertEqual(area > 0, connected)
            small = outline(glyphs, cmap[CODES["small"]])
            self.assertAlmostEqual((small.bounds[3] - small.bounds[1]) / height, .7, delta=.003)
            short = outline(glyphs, cmap[CODES["short"]])
            self.assertGreater(short.bounds[1], bottom + .25 * height)

    def test_marks_keep_vav_position_and_word_advance(self):
        for path in PATHS:
            font = TTFont(path)
            cmap = font.getBestCmap()
            glyphs = font.getGlyphSet()
            marks = [code for code in range(0x0591, 0x05C8)
                     if unicodedata.category(chr(code)) == "Mn" and code in cmap
                     and outline(glyphs, cmap[code]).area]
            for code in CODES.values():
                for mark in marks:
                    with self.subTest(font=path.name, code=hex(code), mark=hex(mark)):
                        normal = [0x05E9, 0x05DC, 0x05D5, mark, 0x05DD]
                        alternate = [0x05E9, 0x05DC, code, mark, 0x05DD]
                        self.assertEqual(shaped(path, alternate), shaped(path, normal))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ashurit-fonts", type=Path)
    options, rest = parser.parse_known_args()
    if options.ashurit_fonts:
        PATHS.extend(sorted(options.ashurit_fonts.glob("*.otf")))
    unittest.main(argv=[__file__] + rest)
