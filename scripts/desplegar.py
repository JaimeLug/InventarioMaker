"""Publica en Supabase lo que no son migraciones.

Uso:
  python scripts/desplegar.py funciones     Publica las funciones del servidor (supabase/functions)
  python scripts/desplegar.py secretos      Pasa a las funciones la llave de correo y la de Firebase
  python scripts/desplegar.py auth          Cierra el registro público de cuentas

Necesita SUPABASE_ACCESS_TOKEN en .env (supabase.com/dashboard/account/tokens).
Usa el CLI de Supabase por npx: no hay que instalarlo ni tener Docker.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
import urllib.error
import urllib.request

import db

VERSION_CLI = "2.117.0"
FUNCIONES = db.RAIZ / "supabase" / "functions"


def entorno() -> tuple[str, str]:
    env = db.leer_env()
    token, url = env.get("SUPABASE_ACCESS_TOKEN"), env.get("SUPABASE_URL", "")
    if not token:
        sys.exit("Falta SUPABASE_ACCESS_TOKEN en .env (se crea en supabase.com/dashboard/account/tokens)")
    referencia = url.removeprefix("https://").split(".", 1)[0]
    if not referencia:
        sys.exit("Falta SUPABASE_URL en .env")
    return token, referencia


def funciones(_args) -> None:
    token, referencia = entorno()
    nombres = sorted(d.name for d in FUNCIONES.iterdir() if d.is_dir() and not d.name.startswith("_"))
    npx = "npx.cmd" if os.name == "nt" else "npx"
    for nombre in nombres:
        print(f"Publicando {nombre}…")
        r = subprocess.run([npx, "--yes", f"supabase@{VERSION_CLI}", "functions", "deploy", nombre,
                            "--project-ref", referencia, "--no-verify-jwt", "--use-api"],
                           cwd=db.RAIZ, env={**os.environ, "SUPABASE_ACCESS_TOKEN": token})
        if r.returncode != 0:
            sys.exit(f"No se publicó {nombre}.")
    print(f"Listo: {', '.join(nombres)}")

    # La base despierta a la función "avisos" cada vez que encola un correo: necesita saber dónde está.
    url = f"https://{referencia}.supabase.co/functions/v1"
    with db.conectar(nube=True) as conn:
        conn.execute("update public.configuracion set valor = to_jsonb(%s::text) where clave = 'url_funciones'", (url,))
    print(f"Dirección de las funciones guardada en la configuración: {url}")


# Secretos que usan las funciones. Se leen de .env y nunca se imprimen.
SECRETOS = ("RESEND_API_KEY", "BREVO_API_KEY", "CORREO_REMITENTE")


def secretos(_args) -> None:
    token, referencia = entorno()
    env = db.leer_env()
    valores = {k: env[k] for k in SECRETOS if env.get(k)}
    archivo = env.get("FIREBASE_CUENTA_SERVICIO_ARCHIVO")
    if archivo:
        ruta = (db.RAIZ / archivo) if not os.path.isabs(archivo) else Path(archivo)
        if not ruta.exists():
            sys.exit(f"No encontré el archivo de la cuenta de servicio de Firebase: {ruta}")
        # En base64: un JSON con comillas y saltos de línea no sobrevive a un archivo .env.
        compacto = json.dumps(json.loads(ruta.read_text(encoding="utf-8")), separators=(",", ":"))
        valores["FIREBASE_CUENTA_SERVICIO"] = base64.b64encode(compacto.encode()).decode()
    if not valores:
        sys.exit("No hay secretos en .env. Revisa .env.ejemplo (sección de correo y Firebase).")

    npx = "npx.cmd" if os.name == "nt" else "npx"
    with tempfile.TemporaryDirectory() as carpeta:
        temporal = os.path.join(carpeta, "secretos.env")
        with open(temporal, "w", encoding="utf-8") as f:
            for k, v in valores.items():
                f.write(f"{k}={v}\n")
        r = subprocess.run([npx, "--yes", f"supabase@{VERSION_CLI}", "secrets", "set", "--env-file", temporal,
                            "--project-ref", referencia],
                           cwd=db.RAIZ, env={**os.environ, "SUPABASE_ACCESS_TOKEN": token}, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("No se guardaron los secretos:\n" + (r.stderr or r.stdout)[-800:])
    print("Secretos guardados en las funciones: " + ", ".join(sorted(valores)))


def auth(_args) -> None:
    token, referencia = entorno()
    url = f"https://api.supabase.com/v1/projects/{referencia}/config/auth"

    def llamar(metodo: str, cuerpo: dict | None = None) -> dict:
        solicitud = urllib.request.Request(url, method=metodo, data=json.dumps(cuerpo).encode() if cuerpo else None,
                                           headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(solicitud, timeout=30) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            sys.exit(f"La API de Supabase respondió {e.code}: {e.read().decode(errors='replace')}")

    antes = llamar("GET")
    print(f"Registro público de cuentas antes: {'cerrado' if antes.get('disable_signup') else 'ABIERTO'}")
    if not antes.get("disable_signup"):
        llamar("PATCH", {"disable_signup": True})
    despues = llamar("GET")
    print(f"Registro público de cuentas ahora: {'cerrado' if despues.get('disable_signup') else 'ABIERTO'}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Publicar en Supabase")
    p.add_argument("que", choices=["funciones", "secretos", "auth"])
    {"funciones": funciones, "secretos": secretos, "auth": auth}[p.parse_args().que](None)


if __name__ == "__main__":
    main()
