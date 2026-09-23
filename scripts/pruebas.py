"""Proyecto de pruebas (Fase 8): una copia del sistema con datos de prueba, sin tocar la base real.

Uso (siempre con INVENTARIO_ENTORNO=pruebas; lee .env.pruebas):
  INVENTARIO_ENTORNO=pruebas python scripts/pruebas.py preparar   Deja el proyecto listo de cero
  INVENTARIO_ENTORNO=pruebas python scripts/pruebas.py cuentas    Solo crea las cuentas de prueba que falten
  INVENTARIO_ENTORNO=pruebas python scripts/pruebas.py estado     Qué hay en el proyecto de pruebas

"preparar" hace, en orden: migraciones, funciones del servidor, secretos, cierre del registro público,
catálogo (los mismos dos Excel del levantamiento real), textos de la configuración copiados de la real
y las cuentas de prueba. Se puede correr otra vez: no duplica nada.

Datos: SOLO el catálogo. Ninguna persona real, ningún préstamo real, ninguna foto de identificación.
Las cuentas usan el Gmail del responsable con "+" (llegan todas a su bandeja) y sus contraseñas y PIN
se guardan en secretos/cuentas-pruebas.txt (ignorado por git), nunca en pantalla.
"""
from __future__ import annotations

import argparse
import os
import secrets
import string
import subprocess
import sys

import db
from cuentas import auth_admin

CORREO_BASE = ("jaimelugomiranda", "gmail.com")
CUENTAS = (
    ("Prueba · Responsable", "responsable", "RESPONSABLE"),
    ("Prueba · Sub administración", "subadmin", "SUBADMIN"),
    ("Prueba · Docente", "docente", "DOCENTE"),
    ("Prueba · Selección de robótica", "seleccion", "SELECCION"),
)
# Textos de la configuración que se copian de la real (las direcciones las pone cada despliegue).
NO_COPIAR = {"url_app", "url_funciones"}
# Lo único que se cambia a propósito en pruebas: los alumnos de prueba usan el Gmail con "+".
SOLO_EN_PRUEBAS = {"dominio_correo_alumnos": "gmail.com"}
ARCHIVO_CUENTAS = db.RAIZ / "secretos" / "cuentas-pruebas.txt"
PY = sys.executable


def exigir_pruebas() -> None:
    """Candado: nunca correr esto contra la base real."""
    if db.ENTORNO != "pruebas":
        sys.exit("Esto solo corre contra el proyecto de pruebas: antepón INVENTARIO_ENTORNO=pruebas")
    real = _leer(db.RAIZ / ".env").get("SUPABASE_URL", "").rstrip("/")
    prueba = db.leer_env().get("SUPABASE_URL", "").rstrip("/")
    if not prueba:
        sys.exit("Falta SUPABASE_URL en .env.pruebas")
    if prueba == real:
        sys.exit("¡.env.pruebas apunta al proyecto REAL! Corrige SUPABASE_URL antes de seguir.")


def _leer(ruta) -> dict[str, str]:
    valores = {}
    if ruta.exists():
        for linea in ruta.read_text(encoding="utf-8").splitlines():
            if "=" in linea and not linea.strip().startswith("#"):
                k, _, v = linea.partition("=")
                valores[k.strip()] = v.strip().strip('"').strip("'")
    return valores


def correr(*args: str) -> None:
    print(f"\n→ {' '.join(args[1:])}")
    r = subprocess.run([PY, *args], cwd=db.RAIZ, env={**os.environ, "INVENTARIO_ENTORNO": "pruebas"})
    if r.returncode != 0:
        sys.exit(f"Falló: {' '.join(args[1:])}")


def copiar_configuracion() -> None:
    """Nombre de la escuela, del laboratorio, jornada…: lo mismo que la real, para que los reportes se vean iguales."""
    real = _leer(db.RAIZ / ".env")
    import psycopg
    with psycopg.connect(host=real["SUPABASE_DB_HOST"], port=int(real.get("SUPABASE_DB_PORT") or 5432),
                         user=real["SUPABASE_DB_USER"], password=real["SUPABASE_DB_PASSWORD"],
                         dbname="postgres", sslmode="require", connect_timeout=15) as origen:
        filas = origen.execute("select clave, valor from public.configuracion").fetchall()
    from psycopg.types.json import Jsonb
    with db.conectar(nube=True) as destino:
        n = 0
        for clave, valor in filas:
            if clave in NO_COPIAR:
                continue
            n += destino.execute("update public.configuracion set valor = %s where clave = %s and valor is distinct from %s",
                                 (Jsonb(valor), clave, Jsonb(valor))).rowcount
        for clave, valor in SOLO_EN_PRUEBAS.items():
            destino.execute("update public.configuracion set valor = %s where clave = %s", (Jsonb(valor), clave))
    print(f"Configuración copiada de la real ({n} valores cambiados).")


def _clave() -> str:
    alfabeto = string.ascii_letters.replace("l", "").replace("I", "").replace("O", "") + "23456789"
    return "Prueba-" + "".join(secrets.choice(alfabeto) for _ in range(8))


def _pin(conn) -> str:
    while True:
        pin = "".join(secrets.choice("0123456789") for _ in range(4))
        try:
            conn.execute("select app.validar_pin_nuevo(%s)", (pin,))
            conn.rollback()
            return pin
        except Exception:  # noqa: BLE001 (PIN demasiado fácil: se sortea otro)
            conn.rollback()


def cuentas(_args=None) -> None:
    exigir_pruebas()
    nuevas = []
    with db.conectar(nube=True) as conn:
        for nombre, sufijo, rol in CUENTAS:
            correo = f"{CORREO_BASE[0]}+{sufijo}@{CORREO_BASE[1]}"
            if conn.execute("select 1 from public.usuario where lower(correo) = %s", (correo,)).fetchone():
                print(f"Ya existe: {correo}")
                continue
            clave = _clave()
            pin = None if rol == "SELECCION" else _pin(conn)
            creado = auth_admin("POST", "users", {"email": correo, "password": clave, "email_confirm": True,
                                                   "user_metadata": {"nombre": nombre}})
            matricula = "24-SEL01" if rol == "SELECCION" else None
            try:
                with conn.transaction():
                    conn.execute("select public.cuenta_registrar(%s, %s, %s, %s, null, %s, %s, %s)",
                                 (creado["id"], nombre, rol, correo, matricula, nombre if matricula else None, "Robótica" if matricula else None))
                    if pin is not None:
                        conn.execute("update public.usuario set pin_hash = extensions.crypt(%s, extensions.gen_salt('bf', 8)) "
                                     "where id = %s", (pin, creado["id"]))
            except Exception as e:  # noqa: BLE001
                auth_admin("DELETE", f"users/{creado['id']}")
                sys.exit(f"No se registró {correo} (se deshizo): {e}")
            nuevas.append((rol, correo, clave, pin))
            print(f"Cuenta de prueba creada: {nombre} · {rol} · {correo}")
    if nuevas:
        ARCHIVO_CUENTAS.parent.mkdir(exist_ok=True)
        with ARCHIVO_CUENTAS.open("a", encoding="utf-8") as f:
            if f.tell() == 0:
                f.write("CUENTAS DEL PROYECTO DE PRUEBAS (solo sirven ahí; no se suben a git)\n\n")
            for rol, correo, clave, pin in nuevas:
                f.write(f"{rol:<12} {correo:<45} contraseña: {clave}   PIN: {pin}\n")
        print(f"Contraseñas y PIN guardados en {ARCHIVO_CUENTAS.relative_to(db.RAIZ)}")


def preparar(_args) -> None:
    exigir_pruebas()
    correr("scripts/db.py", "--nube", "migrar")
    correr("scripts/desplegar.py", "funciones")
    correr("scripts/desplegar.py", "secretos")
    correr("scripts/desplegar.py", "auth")
    correr("scripts/import_excel.py", "--nube")
    correr("scripts/levantamiento3.py", "--nube")
    copiar_configuracion()
    cuentas()
    estado()


def estado(_args=None) -> None:
    exigir_pruebas()
    with db.conectar(nube=True) as conn:
        print(f"\nProyecto de pruebas: {db.leer_env().get('SUPABASE_URL')}")
        for tabla in ("articulo", "contenedor", "plantilla_kit", "movimiento", "usuario", "solicitante", "solicitud"):
            print(f"  {tabla:<16}{conn.execute(f'select count(*) from public.{tabla}').fetchone()[0]}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Proyecto de pruebas (Fase 8)")
    p.add_argument("accion", choices=["preparar", "cuentas", "estado"])
    {"preparar": preparar, "cuentas": cuentas, "estado": estado}[p.parse_args().accion](None)


if __name__ == "__main__":
    main()
