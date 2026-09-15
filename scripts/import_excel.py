"""Importa el Excel del levantamiento inicial a la base de datos.

Uso:
  python scripts/import_excel.py [archivo.xlsx] [--simular] [--actualizar]

  --simular     Hace todo y al final deshace: sirve para revisar el informe sin guardar.
  --actualizar  Si el artículo ya existe, actualiza sus datos descriptivos (nombre, marca,
                observaciones...). Nunca toca cantidades: esas solo cambian con movimientos.

Es idempotente: correrlo dos veces no duplica artículos, movimientos ni pendientes.
La llave es la "Ref. original" del Excel (ref_foto).
"""
from __future__ import annotations

import argparse
import sys
import uuid
from dataclasses import dataclass, field
from pathlib import Path

import psycopg
from psycopg.rows import tuple_row
from psycopg.types.json import Jsonb

import db
from inventario_excel import ArticuloExcel, leer_excel

EXCEL_POR_DEFECTO = db.RAIZ / "InventarioRobotica1erFaltaVerificarCant.xlsx"

# Fijo a propósito: genera siempre el mismo identificador de alta para cada Ref. original.
ESPACIO_IMPORTACION = uuid.UUID("6f1c1b2e-3c7a-4a51-9a53-0d6a2e9e1a01")


@dataclass
class Informe:
    leidos: int = 0
    nuevos: int = 0
    existentes: int = 0
    actualizados: int = 0
    movimientos: int = 0
    tareas: int = 0
    por_hoja: dict[str, int] = field(default_factory=dict)
    advertencias: list[str] = field(default_factory=list)


def id_alta(ref_foto: int) -> uuid.UUID:
    return uuid.uuid5(ESPACIO_IMPORTACION, f"alta-inicial-{ref_foto}")


def importar(conn: psycopg.Connection, articulos: list[ArticuloExcel], *, actualizar: bool = False) -> Informe:
    inf = Informe(leidos=len(articulos))
    with conn.cursor(row_factory=tuple_row) as cur:
        for a in articulos:
            inf.por_hoja[a.hoja] = inf.por_hoja.get(a.hoja, 0) + 1
            inf.advertencias += [f"{a.hoja}, Ref. {a.ref_foto}: {w}" for w in a.advertencias]

            cur.execute("select id from public.articulo where ref_foto = %s", (a.ref_foto,))
            fila = cur.fetchone()
            if fila is None:
                # El código del QR repite la Ref. original (A-0101). Los nuevos de la app empiezan en A-1001.
                if a.ref_foto < 1001:
                    codigo = f"A-{a.ref_foto:04d}"
                else:
                    codigo = cur.execute(
                        "select 'A-' || lpad(nextval('app.articulo_codigo_seq')::text, 4, '0')").fetchone()[0]
                cur.execute(
                    """
                    insert into public.articulo (
                      codigo, ref_foto, nombre, marca_modelo, categoria, subcategoria, cantidad_texto,
                      cantidad_estimada, conteo_desconocido, unidad, estado_inventario, estado_fisico,
                      estado_fisico_texto, etiquetado, ubicacion, num_resguardo, num_serie, observaciones,
                      es_consumible, datos_origen)
                    values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    returning id
                    """,
                    (codigo, a.ref_foto, a.nombre, a.marca_modelo,
                     a.categoria, a.subcategoria, a.cantidad_texto, a.cantidad.estimada, a.cantidad.desconocida,
                     a.cantidad.unidad, a.estado_inventario, a.estado_fisico, a.estado_fisico_texto, a.etiquetado,
                     a.ubicacion, a.num_resguardo, a.num_serie, a.observaciones, a.es_consumible,
                     Jsonb(a.datos_origen)),
                )
                articulo_id = cur.fetchone()[0]
                inf.nuevos += 1
            else:
                articulo_id = fila[0]
                inf.existentes += 1
                if actualizar:
                    cur.execute(
                        """
                        update public.articulo
                           set nombre = %s, marca_modelo = %s, observaciones = %s,
                               estado_fisico_texto = %s, datos_origen = %s
                         where id = %s
                           and (nombre, marca_modelo, observaciones, estado_fisico_texto)
                               is distinct from (%s, %s, %s, %s)
                        """,
                        (a.nombre, a.marca_modelo, a.observaciones, a.estado_fisico_texto, Jsonb(a.datos_origen),
                         articulo_id, a.nombre, a.marca_modelo, a.observaciones, a.estado_fisico_texto),
                    )
                    inf.actualizados += cur.rowcount

            if a.cantidad.valor and not a.cantidad.desconocida:
                cur.execute(
                    """
                    insert into public.movimiento (articulo_id, tipo, cantidad, nota, origen, comando_id)
                    values (%s, 'ALTA', %s, %s, 'IMPORTACION', %s)
                    on conflict (comando_id) do nothing
                    """,
                    (articulo_id, a.cantidad.valor,
                     f'Alta inicial desde el Excel (hoja {a.hoja}, renglón {a.fila}, cantidad "{a.cantidad_texto}")',
                     id_alta(a.ref_foto)),
                )
                inf.movimientos += cur.rowcount

            for t in a.tareas:
                cur.execute(
                    """
                    insert into public.tarea_pendiente (articulo_id, tipo, descripcion, origen, prioridad)
                    values (%s, %s, %s, 'IMPORTACION', %s)
                    on conflict (articulo_id, tipo) where origen = 'IMPORTACION' do nothing
                    """,
                    (articulo_id, t.tipo, t.descripcion, t.prioridad),
                )
                inf.tareas += cur.rowcount
    return inf


def verificar(conn: psycopg.Connection) -> list[str]:
    """Revisiones rápidas después de importar."""
    lineas = []
    with conn.cursor(row_factory=tuple_row) as cur:
        cur.execute("select categoria::text, articulos, con_pendientes, estimados, sin_conteo "
                    "from public.v_resumen_categoria order by categoria")
        lineas.append(f"  {'Categoría':<26}{'Artículos':>10}{'Con pend.':>11}{'Estimados':>11}{'Sin conteo':>12}")
        for cat, art, pend, est, sin in cur.fetchall():
            lineas.append(f"  {cat:<26}{art:>10}{pend:>11}{est:>11}{sin:>12}")
        descuadres = cur.execute("select count(*) from public.v_descuadres").fetchone()[0]
        lineas.append(f"  Descuadres entre cantidad y movimientos: {descuadres}")
    return lineas


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Importa el Excel del levantamiento inicial")
    p.add_argument("archivo", nargs="?", type=Path, default=EXCEL_POR_DEFECTO)
    p.add_argument("--simular", action="store_true", help="no guarda nada, solo muestra el informe")
    p.add_argument("--actualizar", action="store_true", help="actualiza datos descriptivos de artículos existentes")
    args = p.parse_args()

    if not args.archivo.exists():
        sys.exit(f"No encontré el archivo {args.archivo}")
    try:
        articulos = leer_excel(args.archivo)
    except ValueError as e:
        sys.exit(f"El Excel no tiene el formato esperado: {e}")

    with db.conectar() as conn:
        try:
            with conn.transaction():
                inf = importar(conn, articulos, actualizar=args.actualizar)
                resumen = verificar(conn)
                if args.simular:
                    raise psycopg.Rollback()
        except psycopg.Error as e:
            sys.exit(f"La importación se canceló y no se guardó nada:\n  {e}")

    print(f"{'SIMULACIÓN (no se guardó nada)' if args.simular else 'Importación terminada'}: {args.archivo.name}")
    print(f"  Renglones leídos: {inf.leidos}  " + "  ".join(f"{h}: {n}" for h, n in inf.por_hoja.items()))
    print(f"  Artículos nuevos: {inf.nuevos}   ya existían: {inf.existentes}   actualizados: {inf.actualizados}")
    print(f"  Movimientos de alta nuevos: {inf.movimientos}   Pendientes nuevos: {inf.tareas}")
    if inf.advertencias:
        print("Advertencias:")
        for w in inf.advertencias:
            print(f"  - {w}")
    print("Estado de la base:")
    print("\n".join(resumen))


if __name__ == "__main__":
    main()
