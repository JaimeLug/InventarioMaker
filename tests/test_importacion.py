"""Importación del Excel real del levantamiento."""
from pathlib import Path

import pytest

from import_excel import importar
from inventario_excel import leer_excel

EXCEL = Path(__file__).resolve().parent.parent / "InventarioRobotica1erFaltaVerificarCant.xlsx"

POR_CATEGORIA = {"VEX": 5, "FTC": 33, "HERRAMIENTAS": 28, "HERRAMIENTAS_ELECTRICAS": 21,
                 "CONSUMIBLES": 36, "COMUN": 17, "SIN_CLASIFICAR": 3}

# Pendientes que vienen tal cual del Excel (hoja Resumen). CONTAR y CONFIRMAR_VACIO
# pueden ser más, porque la importación agrega los de cantidades estimadas y cajas vacías.
PENDIENTES_EXACTOS = {"VERIFICAR_DATO": 15, "IDENTIFICAR_ETIQUETAR": 6, "ABRIR_REVISAR": 5,
                      "REGISTRAR_SERIE": 5, "FALTA_PIEZA": 4, "DEFINIR_VEX_FTC": 3, "LOCALIZAR_CONTENIDO": 2}


@pytest.fixture(scope="module")
def articulos():
    return leer_excel(EXCEL)


@pytest.fixture
def importado(bd, articulos):
    informe = importar(bd, articulos)
    return bd, informe


def uno(bd, consulta, *params):
    return bd.execute(consulta, params).fetchone()


def test_se_importan_los_143_articulos_por_hoja(importado):
    bd, inf = importado
    assert (inf.leidos, inf.nuevos) == (143, 143)
    filas = bd.execute("select categoria::text as c, count(*) as n from articulo group by 1").fetchall()
    assert {f["c"]: f["n"] for f in filas} == POR_CATEGORIA


def test_correrlo_dos_veces_no_duplica_nada(importado, articulos):
    bd, _ = importado
    antes = uno(bd, "select (select count(*) from articulo) a, (select count(*) from movimiento) m, "
                    "(select count(*) from tarea_pendiente) t")
    segundo = importar(bd, articulos)
    despues = uno(bd, "select (select count(*) from articulo) a, (select count(*) from movimiento) m, "
                      "(select count(*) from tarea_pendiente) t")
    assert (segundo.nuevos, segundo.existentes, segundo.movimientos, segundo.tareas) == (0, 143, 0, 0)
    assert antes == despues


def test_cantidades_estimadas_y_sin_conteo(importado):
    bd, _ = importado
    destornilladores = uno(bd, "select * from v_inventario where nombre = 'Destornilladores surtidos (cajón)'")
    assert (destornilladores["existencia"], destornilladores["cantidad_estimada"],
            destornilladores["estado_inventario"], destornilladores["cantidad_texto"]) == (17, True, "POR_CONTAR", "~17")

    bandas = uno(bd, "select * from v_inventario where nombre = 'Bandas dentadas / cadena de arrastre'")
    assert (bandas["conteo_desconocido"], bandas["existencia"], bandas["prestable"]) == (True, 0, False)

    kit = uno(bd, "select * from v_inventario where nombre = 'Kit base VEX Classroom & Competition'")
    assert (kit["existencia"], kit["unidad"], kit["cantidad_estimada"]) == (4, "caja", False)


def test_sin_clasificar_no_se_puede_prestar(importado):
    bd, _ = importado
    filas = bd.execute("select estado_inventario, prestable from v_inventario where categoria = 'SIN_CLASIFICAR'").fetchall()
    assert len(filas) == 3
    assert all(f["estado_inventario"] == "SIN_CLASIFICAR" and not f["prestable"] for f in filas)


def test_pendientes_del_excel(importado):
    bd, _ = importado
    filas = bd.execute("select tipo::text as t, count(*) as n from tarea_pendiente group by 1").fetchall()
    conteo = {f["t"]: f["n"] for f in filas}
    for tipo, esperado in PENDIENTES_EXACTOS.items():
        assert conteo[tipo] == esperado, tipo
    assert conteo["CONTAR"] >= 16
    assert conteo["CONFIRMAR_VACIO"] >= 1
    assert uno(bd, "select count(*) as n from tarea_pendiente where origen <> 'IMPORTACION'")["n"] == 0


def test_estuches_vacios_quedan_con_pendiente_de_alta_prioridad(importado):
    bd, _ = importado
    filas = bd.execute(
        "select a.ref_foto from tarea_pendiente t join articulo a on a.id = t.articulo_id "
        "where t.tipo = 'LOCALIZAR_CONTENIDO' and t.prioridad = 1 order by 1").fetchall()
    assert [f["ref_foto"] for f in filas] == [138, 139]


def test_resguardos_y_series_extraidos(importado):
    bd, _ = importado
    resguardos = bd.execute("select ref_foto, num_resguardo from articulo where num_resguardo is not null order by 1").fetchall()
    assert [(f["ref_foto"], f["num_resguardo"]) for f in resguardos] == [(101, "P13/0276"), (104, "P13/0264")]
    series = bd.execute("select ref_foto from articulo where num_serie is not null order by 1").fetchall()
    assert [f["ref_foto"] for f in series] == [7, 101, 102]


def test_codigos_siguen_la_referencia_de_la_foto(importado):
    bd, _ = importado
    assert uno(bd, "select codigo from articulo where ref_foto = 101")["codigo"] == "A-0101"


def test_altas_iniciales_y_todo_cuadra(importado):
    bd, _ = importado
    altas = uno(bd, "select count(*) as n from movimiento where tipo = 'ALTA' and origen = 'IMPORTACION'")["n"]
    con_numero = uno(bd, "select count(*) as n from articulo where not conteo_desconocido")["n"]
    assert altas == con_numero
    assert uno(bd, "select count(*) as n from app.v_descuadres")["n"] == 0
    assert uno(bd, "select count(*) as n from movimiento where tipo <> 'ALTA'")["n"] == 0


def test_se_conserva_el_renglon_original(importado):
    bd, _ = importado
    origen = uno(bd, "select datos_origen from articulo where ref_foto = 101")["datos_origen"]
    assert origen["hoja"] == "Herramientas eléctricas" and "P13/0276" in origen["Observaciones"]
