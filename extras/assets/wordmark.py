"""Turn a block-character text file into ImageMagick -draw rectangles.

Usage: python3 -I wordmark.py <text-file> <cell-w> <cell-h> <canvas-w> <canvas-h> <dx> <dy> <fill>

Each character cell becomes cell-w x cell-h pixels. The ink is centered on
the canvas and then moved by dx,dy, so a second call with an offset draws a
drop shadow. Standard library only.
"""

import sys

# Quadrants of a cell: top-left, top-right, bottom-left, bottom-right.
GLYPHS = {
    " ": (0, 0, 0, 0),
    "█": (1, 1, 1, 1),
    "▀": (1, 1, 0, 0),
    "▄": (0, 0, 1, 1),
    "▌": (1, 0, 1, 0),
    "▐": (0, 1, 0, 1),
    "▘": (1, 0, 0, 0),
    "▝": (0, 1, 0, 0),
    "▖": (0, 0, 1, 0),
    "▗": (0, 0, 0, 1),
    "▚": (1, 0, 0, 1),
    "▞": (0, 1, 1, 0),
    "▙": (1, 0, 1, 1),
    "▟": (0, 1, 1, 1),
    "▛": (1, 1, 1, 0),
    "▜": (1, 1, 0, 1),
}


def quadrant_grid(lines):
    """Return rows of half-cell pixels: two grid rows and columns per cell."""
    width = max((len(line) for line in lines), default=0)
    grid = [[0] * (2 * width) for _ in range(2 * len(lines))]
    unknown = set()
    for row, line in enumerate(lines):
        for col, char in enumerate(line):
            quads = GLYPHS.get(char)
            if quads is None:
                # Shades and any other visible glyph read as a full block.
                unknown.add(char)
                quads = (0, 0, 0, 0) if char.isspace() else (1, 1, 1, 1)
            for index, on in enumerate(quads):
                if on:
                    grid[2 * row + index // 2][2 * col + index % 2] = 1
    for char in sorted(unknown):
        print(f"wordmark.py: drew {char!r} (U+{ord(char):04X}) as a full block", file=sys.stderr)
    return grid


def runs(grid):
    """Yield (row, first_col, last_col) for each horizontal run of ink."""
    for row, cells in enumerate(grid):
        start = None
        for col, on in enumerate(cells + [0]):
            if on and start is None:
                start = col
            elif not on and start is not None:
                yield row, start, col - 1
                start = None


def main(argv):
    if len(argv) != 9:
        sys.exit(__doc__.strip().splitlines()[2])
    path = argv[1]
    cell_w, cell_h, canvas_w, canvas_h, dx, dy = (int(value) for value in argv[2:8])
    fill = argv[8]
    if cell_w % 2 or cell_h % 2:
        sys.exit("wordmark.py: cell sizes must be even, so half blocks stay whole pixels")

    with open(path, encoding="utf-8") as handle:
        lines = handle.read().rstrip("\n").split("\n")
    grid = quadrant_grid(lines)
    ink = list(runs(grid))
    if not ink:
        sys.exit(f"wordmark.py: {path} has no ink")

    qw, qh = cell_w // 2, cell_h // 2
    left = min(first for _, first, _ in ink) * qw
    right = (max(last for _, _, last in ink) + 1) * qw
    top = min(row for row, _, _ in ink) * qh
    bottom = (max(row for row, _, _ in ink) + 1) * qh
    x0 = (canvas_w - (right - left)) // 2 - left + dx
    y0 = (canvas_h - (bottom - top)) // 2 - top + dy

    out = [f"fill {fill}"]
    for row, first, last in ink:
        y = y0 + row * qh
        out.append(f"rectangle {x0 + first * qw},{y} {x0 + (last + 1) * qw - 1},{y + qh - 1}")
    print(" ".join(out))


if __name__ == "__main__":
    main(sys.argv)
