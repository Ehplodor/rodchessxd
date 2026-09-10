import http.server
import socketserver
import webbrowser
import os
import sys

PORT = 8060
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class GodotHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # Headers essentiels pour Godot 4 HTML5 (Cross-Origin Isolation et WASM)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        if path.endswith(".pck"):
            return "application/octet-stream"
        return super().guess_type(path)

class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

def run():
    with ThreadingTCPServer(("", PORT), GodotHTTPRequestHandler) as httpd:
        url = f"http://localhost:{PORT}/RodChessXD2.html"
        print("=" * 60)
        print(f" Serveur Web RodChessXD prêt sur {url}")
        print(" Headers COOP / COEP activés (compatibilité WebAssembly & Godot 4)")
        print(" Ouverture automatique de votre navigateur...")
        print(" Pour arrêter le serveur, appuyez sur Ctrl + C.")
        print("=" * 60)
        webbrowser.open(url)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServeur arrêté proprement.")

if __name__ == "__main__":
    run()
