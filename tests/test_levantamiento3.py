"""Incorporación del levantamiento 3 (hoja VEX y listas de contenido de fábrica) sobre la importación inicial."""
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

import levantamiento3
from import_excel import importar
from inventario_excel import leer_excel

RAIZ = Path(__file__).resolve().parent.parent


def test_levantamiento3_sobre_el_inventario_inicial(url_base):
    with psycopg.connect(url_base, autocommit=True, row_factory=dict_row) as bd:
        importar(bd, leer_excel(RAIZ / "InventarioRobotica1erFaltaVerificarCant.xlsx"))
    with psycopg.connect(url_base) as conn:
        primero = levantamiento3.aplicar(conn, RAIZ / "InventarioRobotica3erFaltaVerificarCant.xlsx")
        conn.commit()
        segundo = levantamiento3.aplicar(conn, RAIZ / "InventarioRobotica3erFaltaVerificarCant.xlsx")
        conn.commit()
    assert (len(primero["actualizados"]), len(primero["nuevos"]), primero["ajustes"]) == (5, 12, ["A-0130: 3 → 2"])
    assert (segundo["nuevos"], segundo["ajustes"], segundo["plantillas"], segundo["tareas"]) == ([], [], [], 0)

    with psycopg.connect(url_base, row_factory=dict_row) as bd:
        vex = bd.execute("select count(*) as n from articulo where categoria = 'VEX' and activo").fetchone()["n"]
        assert vex == 17
        kit = bd.execute("select nombre, cantidad from articulo where codigo = 'A-0130'").fetchone()
        assert (kit["nombre"], kit["cantidad"]) == ("V5 Robot Kit (caja de competencia)", 2)
        cortex = bd.execute("select cantidad, observaciones from articulo where nombre = 'Cortex Microcontroller'").fetchone()
        assert cortex["cantidad"] == 1 and "A-0105" in cortex["observaciones"]
        # Lo que viene dentro de cada caja no se dio de alta suelto.
        assert bd.execute("select count(*) as n from articulo where nombre = 'Motor 2-Wire 393'").fetchone()["n"] == 0
        plantillas = {p["nombre"]: p["n"] for p in bd.execute(
            "select p.nombre, count(l.id) as n from plantilla_kit p join plantilla_kit_linea l on l.plantilla_id = p.id group by p.nombre").fetchall()}
        assert plantillas[levantamiento3.PLANTILLA_VEX] == 13 and plantillas["REV Control & Power Bundle"] == 6
        gamepad = bd.execute("select nota from plantilla_kit_linea where sku = 'REV-31-2983'").fetchone()
        assert "Logitech" in gamepad["nota"]
        assert bd.execute("select count(*) as n from app.v_descuadres").fetchone()["n"] == 0
