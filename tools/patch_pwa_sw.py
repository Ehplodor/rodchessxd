"""patch_pwa_sw.py - Ajoute stockfish.js et uci_worker_bridge.js au pre-cache
du service worker genere par l'export Web Godot (PWA), afin que le moteur
Stockfish WASM fonctionne hors-ligne au 2e chargement.

Usage : python tools/patch_pwa_sw.py <chemin/index.service.worker.js>
"""
import pathlib
import sys


def patch(path: str) -> bool:
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    if '"stockfish.js"' in s:
        return False
    marker = 'const CACHED_FILES = ["index.html","index.js"'
    replaced = 'const CACHED_FILES = ["index.html","index.js","stockfish.js","uci_worker_bridge.js"'
    if marker not in s:
        raise SystemExit("patch_pwa_sw: marqueur CACHED_FILES introuvable dans " + str(p))
    p.write_text(s.replace(marker, replaced, 1), encoding="utf-8")
    return True


if __name__ == "__main__":
    target = sys.argv[1]
    print(("patched " if patch(target) else "already patched ") + target)
