"""Recorta las letras de la app (Barlow, Barlow Condensed e IBM Plex Mono) a lo que se usa.

Uso:
  python scripts/recortar_fuentes.py

Deja en cada archivo de app/assets/fuentes/ solo:
  * Letras latinas (con acentos, ñ y ü), griegas (Ω, µ) y los signos de puntuación, flechas,
    fracciones y símbolos técnicos. Se quitan el cirílico y el vietnamita.
  * Las funciones tipográficas que pide la app: cifras tabulares, cero con barra, ligaduras y
    acentos compuestos. Se quitan versalitas y variantes que ningún estilo usa.
  * Sin instrucciones de "hinting": el celular y el navegador no las usan al dibujar.

Se puede volver a correr: recortar un archivo ya recortado lo deja igual. Una letra que falte
(un símbolo raro en un nombre) no se pierde: Flutter la toma de otra fuente del sistema.
Iconos (lucide.ttf) no se tocan: Flutter ya los recorta solo al compilar.
Necesita fonttools (requirements-dev.txt).
"""
from __future__ import annotations

from pathlib import Path

from fontTools import subset

CARPETA = Path(__file__).resolve().parent.parent / "app" / "assets" / "fuentes"
LETRAS = ("Barlow-", "BarlowCondensed-", "IBMPlexMono-")
UNICODES = "U+0000-024F,U+02B0-036F,U+0370-03FF,U+2000-2BFF,U+FB00-FB02"
FUNCIONES = "ccmp,locl,mark,mkmk,kern,liga,clig,calt,rlig,tnum,pnum,zero"


def recortar(archivo: Path) -> tuple[int, int]:
    antes = archivo.stat().st_size
    subset.main([
        str(archivo),
        f"--unicodes={UNICODES}",
        f"--layout-features={FUNCIONES}",
        "--name-IDs=*",           # nombre, autores y licencia se quedan
        "--name-languages=*",
        "--notdef-outline",
        "--drop-tables+=DSIG,meta",
        "--no-hinting",
        f"--output-file={archivo}",
    ])
    return antes, archivo.stat().st_size


def main() -> None:
    total_antes = total_despues = 0
    for archivo in sorted(CARPETA.glob("*.ttf")):
        if not archivo.name.startswith(LETRAS):
            continue
        antes, despues = recortar(archivo)
        total_antes += antes
        total_despues += despues
        print(f"{archivo.name:32} {antes / 1024:6.0f} KB → {despues / 1024:4.0f} KB")
    print(f"{'Total':32} {total_antes / 1024:6.0f} KB → {total_despues / 1024:4.0f} KB")


if __name__ == "__main__":
    main()
