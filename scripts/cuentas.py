"""Cuentas desde la terminal: para crear la primera, antes de que exista alguien que las cree desde la app.

Uso:
  python scripts/cuentas.py crear --nombre "Ing. Jaime Santiago Lugo Miranda" --correo tu@correo --rol RESPONSABLE
  python scripts/cuentas.py listar

Trabaja siempre contra Supabase (usa SUPABASE_SECRET_KEY y los datos de conexión de .env).
La contraseña y el PIN se escriben en la terminal sin mostrarse; no se guardan en ningún archivo.
Después, las cuentas se administran desde la app (responsable o sub administración).
"""
from __future__ import annotations

import argparse
import getpass
import json
import re
import sys
import urllib.error
import urllib.request

import psycopg

import db

ROLES = ("DOCENTE", "RESPONSABLE", "SUBADMIN", "SELECCION")


def auth_admin(metodo: str, ruta: str, cuerpo: dict | None = None) -> dict:
    env = db.leer_env()
    url, secreta = env.get("SUPABASE_URL"), env.get("SUPABASE_SECRET_KEY")
    if not url or not secreta:
        sys.exit("Faltan SUPABASE_URL o SUPABASE_SECRET_KEY en .env")
    solicitud = urllib.request.Request(
        f"{url}/auth/v1/admin/{ruta}", method=metodo,
        data=json.dumps(cuerpo).encode() if cuerpo is not None else None,
        headers={"apikey": secreta, "Authorization": f"Bearer {secreta}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(solicitud, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"Supabase Auth respondió {e.code}: {e.read().decode(errors='replace')}")


def pedir_secreto(etiqueta: str, *, minimo: int, opcional: bool = False) -> str | None:
    while True:
        valor = getpass.getpass(f"{etiqueta}{' (Enter para omitir)' if opcional else ''}: ")
        if not valor and opcional:
            return None
        if len(valor) < minimo:
            print(f"  Debe tener al menos {minimo} caracteres.")
            continue
        if getpass.getpass("  Repítela: ") != valor:
            print("  No coinciden, intenta de nuevo.")
            continue
        return valor


def crear(args) -> None:
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", args.correo.strip()):
        sys.exit(f'"{args.correo}" no es un correo válido. Escribe tu correo real, por ejemplo: --correo jaime@ejemplo.com')
    if args.rol == "SELECCION" and not getattr(args, "matricula", None):
        sys.exit("Las cuentas de rol SELECCION necesitan --matricula.")
    contrasena = pedir_secreto("Contraseña", minimo=8)
    pin = None if args.rol == "SELECCION" else pedir_secreto("PIN de 4 a 6 números", minimo=4, opcional=True)

    with db.conectar(nube=True) as conn:
        if pin is not None:
            try:
                conn.execute("select app.validar_pin_nuevo(%s)", (pin,))
            except psycopg.Error as e:
                sys.exit(f"PIN no válido: {e.diag.message_primary}")
            conn.rollback()

        creado = auth_admin("POST", "users", {"email": args.correo.strip().lower(), "password": contrasena,
                                                "email_confirm": True, "user_metadata": {"nombre": args.nombre}})
        try:
            with conn.transaction():
                conn.execute("select public.cuenta_registrar(%s, %s, %s, %s, null, %s, %s, %s)",
                             (creado["id"], args.nombre, args.rol, args.correo.strip().lower(),
                              getattr(args, "matricula", None), getattr(args, "alumno", None), getattr(args, "grupo", None)))
                if pin is not None:
                    conn.execute("update public.usuario set pin_hash = extensions.crypt(%s, extensions.gen_salt('bf', 8)) "
                                 "where id = %s", (pin, creado["id"]))
        except psycopg.Error as e:
            auth_admin("DELETE", f"users/{creado['id']}")
            sys.exit(f"No se registró la cuenta (se deshizo en Supabase Auth): {e.diag.message_primary}")
    print(f"Cuenta creada: {args.nombre} ({args.rol}), {args.correo}{', con PIN' if pin else ''}.")


def listar(_args) -> None:
    with db.conectar(nube=True) as conn:
        filas = conn.execute("select nombre, rol, correo, activo, pin_hash is not null from public.usuario "
                             "order by activo desc, nombre").fetchall()
    if not filas:
        print("Todavía no hay cuentas.")
    for nombre, rol, correo, activo, pin in filas:
        print(f"  {nombre:<40}{rol:<13}{correo or '(sin correo)':<32}{'activa' if activo else 'DESACTIVADA':<13}{'PIN' if pin else ''}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Cuentas del inventario (Supabase)")
    sub = p.add_subparsers(dest="accion", required=True)
    c = sub.add_parser("crear")
    c.add_argument("--nombre", required=True)
    c.add_argument("--correo", required=True)
    c.add_argument("--rol", required=True, choices=ROLES)
    c.add_argument("--matricula", help="Matrícula del alumno (obligatoria para SELECCION)")
    c.add_argument("--alumno", help="Nombre completo del alumno si difiere")
    c.add_argument("--grupo", help="Grupo o área del alumno")
    sub.add_parser("listar")
    args = p.parse_args()
    {"crear": crear, "listar": listar}[args.accion](args)


if __name__ == "__main__":
    main()
