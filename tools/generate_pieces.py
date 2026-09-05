"""
Generate 12 high-quality vector chess piece SVGs (White & Black).
Standard tournament/modern style, clean strokes, clear silhouettes.
"""
import os

PIECES_DIR = r"c:\Dev\RodChessXD\assets\pieces"
os.makedirs(PIECES_DIR, exist_ok=True)

# Standard piece geometry definitions
PAWN_PATH = """
  <path d="M 22 9 C 19.79 9 18 10.79 18 13 C 18 13.89 18.29 14.71 18.78 15.38 C 16.83 16.5 15.5 18.59 15.5 21 C 15.5 23.03 16.44 24.84 17.91 26.03 C 14.5 27.5 12 30.5 11 38.5 L 34 38.5 C 33 30.5 30.5 27.5 27.09 26.03 C 28.56 24.84 29.5 23.03 29.5 21 C 29.5 18.59 28.17 16.5 26.22 15.38 C 26.71 14.71 27 13.89 27 13 C 27 10.79 25.21 9 23 9 L 22 9 z" />
"""

KNIGHT_PATH = """
  <path d="M 22 10 C 32.5 11 38.5 18 38 39 L 15 39 C 15 30 14 27.5 12 26 C 9 23.5 6 22.5 9 18 C 11.5 14 15 10.5 22 10 z" />
  <path d="M 24 18 C 24.38 20.91 18.45 22.6 16 24.5 C 13 27 13 29 13 29 C 17 27 23 26 23 26 C 25.96 27.76 27.56 31.81 29 35 C 31 35 34 35 36 35 C 36 29 33 21 24 18 z" />
  <circle cx="15" cy="17" r="1.5" />
"""

BISHOP_PATH = """
  <path d="M 9 36 C 12.39 35.03 19.11 36.43 22.5 34 C 25.89 36.43 32.61 35.03 36 36 C 36 36 37.65 36.54 39 38 C 38.32 38.97 37.35 38.99 36 38.5 C 32.61 37.53 25.89 38.96 22.5 37.5 C 19.11 38.96 12.39 37.53 9 38.5 C 7.646 38.99 6.677 38.97 6 38 C 7.354 36.54 9 36 9 36 z" />
  <path d="M 15 32 C 17.5 34.5 27.5 34.5 30 32 C 30.5 30.5 30 30 30 30 C 30 27.5 27.5 26 27.5 26 C 31.5 24.5 31 20 31 20 C 31 16 28 12 22.5 10 C 17 12 14 16 14 20 C 14 20 13.5 24.5 17.5 26 C 17.5 26 15 27.5 15 30 C 15 30 14.5 30.5 15 32 z" />
  <path d="M 25 8 A 2.5 2.5 0 1 1 20 8 A 2.5 2.5 0 1 1 25 8 z" />
  <path d="M 17.5 26 L 27.5 26" stroke-width="1.5" />
  <path d="M 22.5 14 L 22.5 24" stroke-width="1.5" />
  <path d="M 20 18 L 25 18" stroke-width="1.5" />
"""

ROOK_PATH = """
  <path d="M 9 39 L 36 39 L 36 36 L 9 36 z" />
  <path d="M 12 36 L 12 32 L 33 32 L 33 36 z" />
  <path d="M 11 14 L 11 9 L 15 9 L 15 11 L 20 11 L 20 9 L 25 9 L 25 11 L 30 11 L 30 9 L 34 9 L 34 14 L 31 17 L 31 29 L 34 32 L 11 32 L 14 29 L 14 17 z" />
  <path d="M 14 17 L 31 17" stroke-width="1.5" />
  <path d="M 14 29 L 31 29" stroke-width="1.5" />
"""

QUEEN_PATH = """
  <path d="M 9 26 C 17.5 24.5 30 24.5 36 26 L 38 14 L 31 25 L 22.5 12 L 14 25 L 7 14 z" />
  <path d="M 9 26 C 9 28 10.5 28 11.5 30 C 12.5 31.5 12.5 31 12 33.5 C 10.5 34.5 10.5 36 10 36 C 9.5 37.5 11 38.5 11 38.5 L 34 38.5 C 34 38.5 35.5 37.5 35 36 C 34.5 36 34.5 34.5 33 33.5 C 32.5 31 32.5 31.5 33.5 30 C 34.5 28 36 28 36 26 z" />
  <circle cx="6" cy="12" r="2" />
  <circle cx="14" cy="9" r="2" />
  <circle cx="22.5" cy="8" r="2" />
  <circle cx="31" cy="9" r="2" />
  <circle cx="39" cy="12" r="2" />
"""

KING_PATH = """
  <path d="M 22.5 11.63 L 22.5 6" stroke-width="2" />
  <path d="M 20 8 L 25 8" stroke-width="2" />
  <path d="M 22.5 25 C 22.5 25 27 17.5 25.5 14.5 C 24 11.5 20.5 11.5 19.5 14.5 C 18 17.5 22.5 25 22.5 25" />
  <path d="M 11.5 37 C 17 40.5 28 40.5 33.5 37 C 36.5 35 37.5 32 37.5 28 C 37.5 22.5 30 19 22.5 19 C 15 19 7.5 22.5 7.5 28 C 7.5 32 8.5 35 11.5 37 z" />
  <path d="M 11.5 30 C 17 27 28 27 33.5 30" stroke-width="1.5" />
  <path d="M 11.5 33.5 C 17 30.5 28 30.5 33.5 33.5" stroke-width="1.5" />
  <path d="M 11.5 37 C 17 34 28 34 33.5 37" stroke-width="1.5" />
"""

PIECES = {
    "P": PAWN_PATH,
    "N": KNIGHT_PATH,
    "B": BISHOP_PATH,
    "R": ROOK_PATH,
    "Q": QUEEN_PATH,
    "K": KING_PATH
}

WHITE_STYLE = """
    fill: #f8fafc;
    stroke: #0f172a;
    stroke-width: 1.5;
    stroke-linecap: round;
    stroke-linejoin: round;
"""

BLACK_STYLE = """
    fill: #1e293b;
    stroke: #f1f5f9;
    stroke-width: 1.5;
    stroke-linecap: round;
    stroke-linejoin: round;
"""

def generate():
    for symbol, path in PIECES.items():
        # White
        w_svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 45 45" width="45" height="45">
  <g style="{WHITE_STYLE}">
    {path}
  </g>
</svg>"""
        with open(os.path.join(PIECES_DIR, f"w{symbol}.svg"), "w", encoding="utf-8") as f:
            f.write(w_svg)

        # Black
        b_svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 45 45" width="45" height="45">
  <g style="{BLACK_STYLE}">
    {path}
  </g>
</svg>"""
        with open(os.path.join(PIECES_DIR, f"b{symbol}.svg"), "w", encoding="utf-8") as f:
            f.write(b_svg)

    print("Generated 12 piece SVGs successfully!")

if __name__ == "__main__":
    generate()
