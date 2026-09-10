"""patch_pwa_sw.py - Ajoute stockfish.js et uci_worker_bridge.js au pre-cache
du service worker genere par l'export Web Godot (PWA), afin que le moteur
Stockfish WASM fonctionne hors-ligne au 2e chargement.

La declaration const CACHED_FILES = [...] est detectee par expression reguliere,
quelle que soit la base de nommage de l'export (index.* ou RodChessXD2.*),
et les deux fichiers sont ajoutes s'ils sont absents (idempotent).

Usage : python tools/patch_pwa_sw.py <chemin/service.worker.js>
"""
import pathlib
import re
import sys


def patch(path: str) -> bool:
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    if '"stockfish.js"' in s and '"uci_worker_bridge.js"' in s:
        return False
    m = re.search(r'const CACHED_FILES = \[(.*?)\]', s, re.DOTALL)
    if not m:
        raise SystemExit("patch_pwa_sw: CACHED_FILES introuvable dans " + str(p))
    entries = m.group(1).rstrip()
    addition = ',"stockfish.js","uci_worker_bridge.js"'
    new_decl = 'const CACHED_FILES = [' + entries + addition + ']'
    p.write_text(s[:m.start()] + new_decl + s[m.end():], encoding="utf-8")
    return True


if __name__ == "__main__":
    target = sys.argv[1]
    print(("patched " if patch(target) else "already patched ") + target)
