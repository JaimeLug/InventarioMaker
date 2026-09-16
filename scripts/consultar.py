"""Consulta del inventario desde la terminal (Fase 1, antes de tener la app).

Uso:
  python scripts/consultar.py                         Resumen por categoría
  python scripts/consultar.py lista [filtros]         Listado de artículos
      --categoria FTC   --buscar "llave"   --pendientes   --estado POR_CONTAR
  python scripts/consultar.py ficha A-0101            Ficha completa de un artículo
  python scripts/consultar.py pendientes [--tipo CONTAR]
  python scripts/consultar.py descuadres              Artículos cuya cantidad no cuadra con sus movimientos
  python scripts/consultar.py csv salidas/inventario.csv
  python scripts/consultar.py uso                     Espacio ocupado contra el límite del plan gratuito

Con --nube antes del comando consulta Supabase:  python scripts/consultar.py --nube lista
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from psycopg.rows import dict_row

import db

CATEGORIAS = {
    "VEX": "VEX", "FTC": "FTC", "HERRAMIENTAS": "Herramientas",
    "HERRAMIENTAS_ELECTRICAS": "Herramientas eléctricas", "CONSUMIBLES": "Consumibles",
    "COMUN": "Común", "SIN_CLASIFICAR": "Sin clasificar",
}
ESTADOS = {
    "SIN_CLASIFICAR": "Sin clasificar", "POR_CONTAR": "Por contar", "POR_VERIFICAR": "Por verificar",
    "VERIFICADO": "Verificado", "DESGLOSADO": "Desglosado", "DADO_DE_BAJA": "Dado de baja",
}
TAREAS = {
    "CONTAR": "Contar físicamente", "VERIFICAR_DATO": "Verificar dato/contenido",
    "ABRIR_REVISAR": "Abrir y revisar contenido", "REGISTRAR_SERIE": "Registrar serie/medida",
    "IDENTIFICAR_ETIQUETAR": "Identificar/etiquetar", "FALTA_PIEZA": "Falta pieza/dato",
    "DEFINIR_VEX_FTC": "Definir si es VEX o FTC", "CONFIRMAR_VACIO": "Confirmar si está vacío",
    "LOCALIZAR_CONTENIDO": "Localizar contenido faltante",
}


def categoria_desde_texto(valor: str) -> str:
    buscado = valor.strip().lower()
    for clave, nombre in CATEGORIAS.items():
        if buscado in (clave.lower(), nombre.lower()):
            return clave
    sys.exit(f"Categoría desconocida: {valor}. Opciones: {', '.join(CATEGORIAS.values())}")


def cantidad(r: dict) -> str:
    """Cómo se muestra una cantidad: ~ si es estimada, ? si nunca se contó."""
    if r["conteo_desconocido"]:
        return "?"
    prefijo = "~" if r["cantidad_estimada"] else ""
    return f"{prefijo}{r['existencia']} {r['unidad']}"


def recortar(texto: str | None, ancho: int) -> str:
    texto = texto or ""
    return texto if len(texto) <= ancho else texto[: ancho - 1] + "…"


def resumen(conn) -> None:
    filas = conn.execute("select * from public.v_resumen_categoria order by categoria").fetchall()
    print(f"{'Categoría':<25}{'Artículos':>10}{'Con pendientes':>16}{'Estimados':>11}{'Sin conteo':>12}{'Verificados':>13}")
    tot = dict.fromkeys(["articulos", "con_pendientes", "estimados", "sin_conteo", "verificados"], 0)
    for r in filas:
        print(f"{CATEGORIAS[r['categoria']]:<25}{r['articulos']:>10}{r['con_pendientes']:>16}"
              f"{r['estimados']:>11}{r['sin_conteo']:>12}{r['verificados']:>13}")
        for k in tot:
            tot[k] += r[k]
    print(f"{'TOTAL':<25}{tot['articulos']:>10}{tot['con_pendientes']:>16}"
          f"{tot['estimados']:>11}{tot['sin_conteo']:>12}{tot['verificados']:>13}")
    abiertos = conn.execute("select count(*) as n from public.tarea_pendiente where not resuelta").fetchone()["n"]
    descuadres = conn.execute("select count(*) as n from app.v_descuadres").fetchone()["n"]
    print(f"\nPendientes abiertos: {abiertos}    Descuadres: {descuadres}")


def lista(conn, args) -> None:
    condiciones, params = ["activo"], []
    if args.categoria:
        condiciones.append("categoria = %s")
        params.append(categoria_desde_texto(args.categoria))
    if args.buscar:
        condiciones.append("(nombre || ' ' || coalesce(marca_modelo, '') || ' ' || coalesce(observaciones, '') || ' ' || codigo) ilike %s")
        params.append(f"%{args.buscar}%")
    if args.pendientes:
        condiciones.append("pendientes_abiertos > 0")
    if args.estado:
        condiciones.append("estado_inventario = %s")
        params.append(args.estado.upper())
    filas = conn.execute(
        f"select * from public.v_inventario where {' and '.join(condiciones)} order by categoria, ref_foto nulls last, nombre",
        params).fetchall()

    print(f"{'Código':<8}{'Artículo':<46}{'Cantidad':>14}{'Disp.':>7}  {'Estado':<15}{'Pend.':>5}")
    categoria_actual = None
    for r in filas:
        if r["categoria"] != categoria_actual:
            categoria_actual = r["categoria"]
            print(f"\n— {CATEGORIAS[categoria_actual]} —")
        disponible = "—" if not r["prestable"] else str(r["disponible"])
        print(f"{r['codigo']:<8}{recortar(r['nombre'], 45):<46}{cantidad(r):>14}{disponible:>7}  "
              f"{ESTADOS[r['estado_inventario']]:<15}{r['pendientes_abiertos'] or '':>5}")
    print(f"\n{len(filas)} artículos")


def ficha(conn, codigo: str) -> None:
    r = conn.execute("select * from public.v_inventario where upper(codigo) = upper(%s) or ref_foto::text = %s",
                     (codigo, codigo)).fetchone()
    if not r:
        sys.exit(f"No existe el artículo {codigo}")
    print(f"{r['codigo']}  {r['nombre']}")
    campos = [
        ("Marca / modelo", r["marca_modelo"]), ("Categoría", CATEGORIAS[r["categoria"]]),
        ("Subcategoría", r["subcategoria"]), ("Ref. foto original", r["ref_foto"]),
        ("Cantidad", cantidad(r) + (f'  (Excel: "{r["cantidad_texto"]}")' if r["cantidad_texto"] else "")),
        ("Disponible", r["disponible"] if r["prestable"] else "No se presta todavía"),
        ("Prestado / fuera de servicio", f"{r['prestado']} / {r['fuera_servicio']}"),
        ("Estado", ESTADOS[r["estado_inventario"]]), ("Estado físico", r["estado_fisico_texto"]),
        ("Etiquetado", r["etiquetado"].capitalize()), ("Ubicación", r["ubicacion_ruta"] or r["ubicacion_texto"] or "Sin asignar"),
        ("Resguardo", r["num_resguardo"]), ("Número de serie", r["num_serie"]), ("Observaciones", r["observaciones"]),
    ]
    for etiqueta, valor in campos:
        if valor not in (None, ""):
            print(f"  {etiqueta + ':':<30}{valor}")

    tareas = conn.execute("select tipo, descripcion, resuelta from public.tarea_pendiente where articulo_id = %s order by creada_en",
                          (r["id"],)).fetchall()
    if tareas:
        print("\n  Pendientes:")
        for t in tareas:
            marca = "✓" if t["resuelta"] else "•"
            print(f"   {marca} {TAREAS[t['tipo']]}: {t['descripcion']}")

    movs = conn.execute("select fecha, tipo, cantidad, nota from public.movimiento where articulo_id = %s order by fecha",
                        (r["id"],)).fetchall()
    print("\n  Movimientos:")
    for m in movs:
        print(f"   {m['fecha']:%d/%m/%Y %H:%M}  {m['tipo']:<14}{m['cantidad']:>5}  {m['nota'] or ''}")


def pendientes(conn, tipo: str | None) -> None:
    filas = conn.execute(
        """
        select t.tipo, a.codigo, a.nombre, a.categoria, t.descripcion, t.prioridad
        from public.tarea_pendiente t join public.articulo a on a.id = t.articulo_id
        where not t.resuelta and (%s::text is null or t.tipo::text = %s)
        order by t.tipo, t.prioridad desc, a.categoria, a.ref_foto
        """, (tipo, tipo)).fetchall()
    actual = None
    for f in filas:
        if f["tipo"] != actual:
            actual = f["tipo"]
            n = sum(1 for x in filas if x["tipo"] == actual)
            print(f"\n— {TAREAS[actual]} ({n}) —")
        alta = " [ALTA]" if f["prioridad"] else ""
        print(f"  {f['codigo']:<8}{recortar(f['nombre'], 42):<44}{CATEGORIAS[f['categoria']]}{alta}")
    print(f"\n{len(filas)} pendientes abiertos")


def descuadres(conn) -> None:
    filas = conn.execute("select * from app.v_descuadres order by codigo").fetchall()
    if not filas:
        print("Todo cuadra: la cantidad de cada artículo coincide con la suma de sus movimientos.")
        return
    print(f"{'Código':<8}{'Artículo':<46}{'Registrado':>11}{'Movimientos':>13}")
    for f in filas:
        print(f"{f['codigo']:<8}{recortar(f['nombre'], 45):<46}{f['cantidad_registrada']!s:>11}{f['existencia']:>13}")


def exportar_csv(conn, ruta: Path) -> None:
    filas = conn.execute("select * from public.v_inventario order by categoria, ref_foto nulls last").fetchall()
    ruta.parent.mkdir(parents=True, exist_ok=True)
    columnas = [c for c in filas[0].keys() if c not in ("id", "contenedor_id", "version")] if filas else []
    with ruta.open("w", newline="", encoding="utf-8-sig") as f:  # con BOM para que Excel respete los acentos
        w = csv.DictWriter(f, fieldnames=columnas, extrasaction="ignore")
        w.writeheader()
        w.writerows(filas)
    print(f"{len(filas)} artículos exportados a {ruta}")


LIMITE_BASE_MB = 500      # plan gratuito de Supabase
LIMITE_ARCHIVOS_MB = 1024


def uso(conn) -> None:
    total = conn.execute("select pg_database_size(current_database()) as b").fetchone()["b"]
    tablas = conn.execute(
        """select c.relname as tabla, pg_total_relation_size(c.oid) as bytes
           from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
           order by 2 desc""").fetchall()
    propias = sum(t["bytes"] for t in tablas)
    print(f"Base de datos: {total / 2**20:.1f} MB de {LIMITE_BASE_MB} MB ({100 * total / 2**20 / LIMITE_BASE_MB:.1f} %)")
    print(f"  De eso, datos del inventario: {propias / 2**20:.2f} MB (el resto es del sistema)\n")
    print(f"  {'Tabla':<22}{'Filas':>8}{'Tamaño':>12}")
    for t in tablas:
        filas = conn.execute(f"select count(*) as n from public.{t['tabla']}").fetchone()["n"]
        print(f"  {t['tabla']:<22}{filas:>8}{t['bytes'] / 1024:>9.0f} KB")
    if conn.execute("select to_regclass('storage.objects') is not null as hay").fetchone()["hay"]:
        f = conn.execute("select count(*) as n, coalesce(sum((metadata->>'size')::bigint), 0) as b "
                         "from storage.objects").fetchone()
        print(f"\nArchivos (fotos): {f['n']} archivos, {f['b'] / 2**20:.1f} MB de {LIMITE_ARCHIVOS_MB} MB")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Consulta del inventario")
    p.add_argument("--nube", action="store_true", help="consultar Supabase (datos en .env)")
    sub = p.add_subparsers(dest="comando")
    l = sub.add_parser("lista")
    l.add_argument("--categoria")
    l.add_argument("--buscar")
    l.add_argument("--pendientes", action="store_true")
    l.add_argument("--estado")
    sub.add_parser("ficha").add_argument("codigo")
    sub.add_parser("pendientes").add_argument("--tipo")
    sub.add_parser("descuadres")
    sub.add_parser("csv").add_argument("ruta", type=Path)
    sub.add_parser("uso")
    args = p.parse_args()

    with db.conectar(nube=args.nube, row_factory=dict_row) as conn:
        match args.comando:
            case None: resumen(conn)
            case "lista": lista(conn, args)
            case "ficha": ficha(conn, args.codigo)
            case "pendientes": pendientes(conn, args.tipo.upper() if args.tipo else None)
            case "descuadres": descuadres(conn)
            case "csv": exportar_csv(conn, args.ruta)
            case "uso": uso(conn)


if __name__ == "__main__":
    main()
