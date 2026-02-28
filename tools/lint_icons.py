#!/usr/bin/env python3
import sys
import re
import os

def is_binary(file_path):
    """Check if a file is binary by looking for a NULL byte in the first 1024 bytes."""
    try:
        with open(file_path, 'rb') as f:
            chunk = f.read(1024)
            return b'\x00' in chunk
    except:
        return True

def process_icons(approved_file, paths, fix=False):
	with open(approved_file, 'r', encoding='utf-8') as f:
		approved = f.read().strip()

	# Compiled pattern for illegal chars
	illegal_pattern = re.compile(f'[^\x00-\x7F{re.escape(approved)}]')

	# Fix mapping
	replacements = {
		'\xc2\xa0': ' ', '─': '—', '‘': "'", '’': "'",
		'“': '"', '”': '"', '–': '-', '◌': '—'
	}

	errors = 0
	# Walk the paths directly in Python to avoid spawning 'find'
	for path in paths:
		for root, _, files in os.walk(path):
			for file in files:
				full_path = os.path.join(root, file)
				if is_binary(full_path):
					continue
				try:
					with open(full_path, 'r', encoding='utf-8') as f:
						content = f.read()

					# 1. Handle Autocorrect
					if fix:
						new_content = content
						for old, new in replacements.items():
							new_content = new_content.replace(old, new)
						if new_content != content:
							with open(full_path, 'w', encoding='utf-8') as f:
								f.write(new_content)
							content = new_content

					# 2. Handle Linting
					found = illegal_pattern.search(content)
					if found:
						# Extract only unique illegal chars for this file
						illegals = set(illegal_pattern.findall(content))
						for char in illegals:
							print(f"❌ ILLEGAL ICON: '{char}' (U+{ord(char):04X}) in {full_path}")
							errors += 1
				except (UnicodeDecodeError, PermissionError):
					continue

	if errors > 0:
		sys.exit(1)

if __name__ == "__main__":
	is_fix = "--fix" in sys.argv
	# Filter out flags to get the approved file and search paths
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	if len(args) < 2:
		sys.exit(0)
	process_icons(args[0], args[1:], fix=is_fix)