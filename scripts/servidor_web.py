"""Sirve la app web ya compilada (app/build/web) en http://localhost:8123 para probarla.

A diferencia de "python -m http.server", cualquier dirección que no sea un archivo devuelve index.html,
así funcionan los enlaces directos como /s/<enlace> que llegan por correo.

Uso:  python scripts/servidor_web.py [puerto]
"""
import http.server
import sys
from functools import partial
from pathlib import Path

CARPETA = Path(__file__).resolve().parent.parent / "app" / "build" / "web"


class Manejador(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        ruta = Path(self.translate_path(self.path))
        if not ruta.exists():
            self.path = "/index.html"
        return super().send_head()


def main() -> None:
    puerto = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
    if not (CARPETA / "index.html").exists():
        sys.exit("Primero compila la app:  cd app  y luego  flutter build web")
    servidor = http.server.ThreadingHTTPServer(("127.0.0.1", puerto), partial(Manejador, directory=str(CARPETA)))
    print(f"App web en http://localhost:{puerto}")
    servidor.serve_forever()


if __name__ == "__main__":
    main()
