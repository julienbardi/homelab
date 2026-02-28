#!/usr/bin/env python3
import sys
import unicodedata
from collections import defaultdict

def get_visual_width(s):
	"""Calculates display width, correctly handling VS16 and wide emojis."""
	width = 0
	for char in s:
		# Variation Selectors and non-spacing marks take 0 columns
		if unicodedata.combining(char) or (0xFE00 <= ord(char) <= 0xFE0F):
			continue
		# Emojis and Wide characters take 2 columns
		if unicodedata.east_asian_width(char) in ('W', 'F'):
			width += 2
		else:
			width += 1
	return width

def pad_visual(s, target_width):
	"""Pads a string based on its visual width on screen."""
	v_width = get_visual_width(s)
	return s + (" " * max(0, target_width - v_width))

def get_char_info(glyph):
	"""Parses glyphs into displayable strings and metadata."""
	if not glyph: return "◌", "N/A", "EMPTY"

	codes = []
	names = []
	display_chars = []

	for c in glyph:
		codes.append(f"U+{(ord(c)):04X}")
		# Identify non-breaking space or control chars for visibility
		if c == '\u00A0' or unicodedata.category(c).startswith('C'):
			display_chars.append("◌")
		else:
			display_chars.append(c)

		name = unicodedata.name(c, "UNKNOWN")
		names.append(name.replace("VARIATION SELECTOR-16", "[VS16]"))

	return "".join(display_chars), " ".join(codes), " + ".join(names)

def main():
	usage_map = defaultdict(set)
	for line in sys.stdin:
		line = line.strip()
		if ':' not in line: continue
		filename, glyph = line.split(':', 1)
		usage_map[glyph].add(filename)

	# Sort by frequency
	sorted_usage = sorted(usage_map.items(), key=lambda x: len(x[1]), reverse=True)

	# Column Widths
	W_ICON, W_HEX, W_CNT = 8, 22, 6

	# Header
	print(f"{pad_visual('Icon', W_ICON)} | {pad_visual('Hex Code', W_HEX)} | {pad_visual('Count', W_CNT)} | Description / Scripts")
	print("-" * 110)

	for glyph, scripts in sorted_usage:
		display, hex_code, desc = get_char_info(glyph)
		row = f"{pad_visual(display, W_ICON)} | {pad_visual(hex_code, W_HEX)} | {pad_visual(str(len(scripts)), W_CNT)} | {desc}"
		print(row)

		script_line = ", ".join(sorted(scripts))
		indent = " " * W_ICON + " | " + " " * W_HEX + " | " + " " * W_CNT + " |   ↳ "
		print(f"{indent}{script_line}\n" + " " * W_ICON + " | " + " " * W_HEX + " | " + " " * W_CNT + " |")

if __name__ == "__main__":
	main()