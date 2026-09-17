"""Fase 5 (migración 0012): datos de reportes, revisión de kits contra su lista, faltantes y folio de actas."""
import uuid

import pytest
from psycopg.types.json import Jsonb

from ayudantes import como, insertar, mov, nueva_sesion, rpc, usuario
from test_acceso import confirmar, rechazo


@pytest.fixture
def lab(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    s = usuario(bd, "SUBADMIN", "Sub Administradora")
    d = usuario(bd, "DOCENTE", "Ruth Canché", pin="4826")
    juan = insertar(bd, "solicitante", nombre_completo="Juan Pérez", tipo="ALUMNO", matricula_o_clave="23-0456", grupo_area="5°B",
                    telefono="9991234567", correo="juan@prepasoficiales.net")
    hub = insertar(bd, "articulo", nombre="Control Hub", categoria="FTC")
    mov(bd, hub, "ALTA", 2, r)
    return dict(bd=bd, r=r, s=s, d=d, juan=juan, hub=hub)


def llamar(bd, yo, funcion, *, nivel="CONTRASENA", **params):
    with como(bd, yo, nivel=nivel):
        return rpc(bd, funcion, **params)


def tabla(bd, yo, funcion, *args):
    marcas = ", ".join(["%s"] * len(args))
    with como(bd, yo):
        return bd.execute(f"select * from public.{funcion}({marcas})", args).fetchall()


def test_prestamos_e_incidencias_con_matricula_pero_sin_contacto(lab):
    bd, r, d = lab["bd"], lab["r"], lab["d"]
    p = mov(bd, lab["hub"], "PRESTAMO", 1, r, responsable_solicitante_id=lab["juan"], fecha_compromiso="2026-01-10T15:00:00-06")
    insertar(bd, "incidencia", articulo_id=lab["hub"], tipo="PERDIDA", cantidad=1, nota="No apareció al devolver", en_taller=False,
             prestamo_id=p, responsable_solicitante_id=lab["juan"], reportada_por=d)
    with rechazo("PT403", "ROL"):
        tabla(bd, d, "reporte_prestamos_abiertos")

    prestamos = tabla(bd, r, "reporte_prestamos_abiertos")
    assert [(x["a_cargo"], x["matricula"], x["grupo"], x["vencido"], x["autorizo"]) for x in prestamos] == \
        [("Juan Pérez", "23-0456", "5°B", True, "Jaime Lugo")]
    assert prestamos[0]["dias_vencido"] > 0
    assert "telefono" not in prestamos[0] and "correo" not in prestamos[0]

    inc = tabla(bd, r, "reporte_incidencias", "2020-01-01", "2020-01-02")        # fuera de periodo, pero sigue en revisión
    assert [(x["tipo"], x["estado"], x["a_cargo"], x["reporto"]) for x in inc] == [("Pérdida", "En revisión", "Juan Pérez", "Ruth Canché")]


def test_bajas_y_movimientos_del_periodo(lab):
    bd, r = lab["bd"], lab["r"]
    bd.execute("update articulo set num_resguardo = 'P13/045' where id = %s", (lab["hub"],))
    mov(bd, lab["hub"], "BAJA", 2, r)
    bd.execute("update articulo set activo = false, estado_inventario = 'DADO_DE_BAJA' where id = %s", (lab["hub"],))
    bajas = tabla(bd, r, "reporte_bajas", "2000-01-01", "2100-01-01")
    assert [(b["codigo"], b["cantidad"], b["en_tramite"], b["total"]) for b in bajas] == [("A-1001", 2, True, True)]
    movs = tabla(bd, r, "reporte_movimientos", "2000-01-01", "2100-01-01")
    assert [m["tipo"] for m in movs] == ["ALTA", "BAJA"]


def test_revision_de_kit_y_faltantes(lab):
    bd, r, d = lab["bd"], lab["r"], lab["d"]
    plantilla = insertar(bd, "plantilla_kit", nombre="REV Control & Power Bundle", sku="REV-35-1906", categoria="FTC")
    lineas = {}
    for orden, (desc, cant) in enumerate([("Control Hub", 1), ("Driver Hub", 1), ("Gamepad", 1), ("Cables", None)], start=1):
        lineas[desc] = insertar(bd, "plantilla_kit_linea", plantilla_id=plantilla, orden=orden, descripcion=desc, cantidad=cant)

    with rechazo("PT403", "ROL"):
        llamar(bd, d, "revision_kit_crear", p_plantilla=plantilla, p_kits=3, p_nombre=None, p_articulo=None)
    rev = llamar(bd, r, "revision_kit_crear", p_plantilla=plantilla, p_kits=3, p_nombre="Bundles comprados", p_articulo=None)
    assert [(l["descripcion"], l["esperada"]) for l in rev["lineas"]] == [("Control Hub", 3), ("Driver Hub", 3), ("Gamepad", 3), ("Cables", None)]
    llamar(bd, r, "revision_kit_guardar", p_id=uuid.UUID(rev["id"]), p_kits=3, p_nota=None, p_lineas=Jsonb([
        {"plantilla_linea_id": str(lineas["Control Hub"]), "encontrada": 1, "nota": "S/N 31159523160015142"},
        {"plantilla_linea_id": str(lineas["Driver Hub"]), "encontrada": 0},
        {"plantilla_linea_id": str(lineas["Gamepad"]), "no_aplica": True, "nota": "Sustituidos por Logitech"},
    ]))
    resumen = tabla(bd, r, "revisiones_kit")
    assert [(x["renglones"], x["revisados"], x["con_faltante"]) for x in resumen] == [(4, 3, 2)]

    faltantes = {f["descripcion"]: f for f in tabla(bd, r, "reporte_faltantes_kits")}
    assert (faltantes["Control Hub"]["faltante"], faltantes["Control Hub"]["estado"]) == (2, "Faltante parcial")
    assert (faltantes["Driver Hub"]["faltante"], faltantes["Driver Hub"]["estado"]) == (3, "Faltante total")
    assert (faltantes["Gamepad"]["faltante"], faltantes["Gamepad"]["estado"]) == (None, "No aplica")
    assert faltantes["Cables"]["estado"] == "Sin revisar"
    assert bd.execute("select count(*) as n from movimiento").fetchone()["n"] == 1           # revisar no mueve el inventario


def test_folio_de_actas_y_registro_en_bitacora(lab):
    bd, r, s = lab["bd"], lab["r"], lab["s"]
    assert llamar(bd, r, "reporte_registrar", p_tipo="INVENTARIO", p_formato="EXCEL", p_parametros=Jsonb({})) is None
    with rechazo("PT403", "ROL"):
        llamar(bd, r, "reporte_registrar", p_tipo="ACTA_ENTREGA", p_formato="PDF", p_parametros=Jsonb({}))
    anio = bd.execute("select extract(year from app.hoy())::int as a").fetchone()["a"]
    assert llamar(bd, s, "reporte_registrar", p_tipo="ACTA_ENTREGA", p_formato="PDF", p_parametros=Jsonb({})) == f"AER-{anio}-001"
    assert llamar(bd, s, "reporte_registrar", p_tipo="ACTA_ENTREGA", p_formato="PDF", p_parametros=Jsonb({})) == f"AER-{anio}-002"
    assert llamar(bd, r, "reporte_registrar", p_tipo="ACTA_INVENTARIO", p_formato="PDF", p_parametros=Jsonb({})) == f"AIP-{anio}-001"
    assert bd.execute("select count(*) as n from bitacora where evento = 'REPORTE_GENERADO'").fetchone()["n"] == 4
    enc = llamar(bd, r, "reporte_encabezado")
    assert (enc["escuela"], enc["programa"], enc["responsable"], enc["generado_por"]) == \
        ("Escuela Preparatoria Número 13", "Programa Renacimiento Maya", "Jaime Lugo", "Jaime Lugo")


def test_el_encabezado_lo_cambia_sub_administracion(lab):
    bd, s = lab["bd"], lab["s"]
    sesion = nueva_sesion(bd, s)
    assert confirmar(bd, s, sesion)["ok"]
    with como(bd, s, sesion=sesion):
        rpc(bd, "configuracion_cambiar", p_clave="nombre_escuela", p_valor=Jsonb("Escuela Preparatoria No. 13"))
    assert bd.execute("select valor from configuracion where clave = 'nombre_escuela'").fetchone()["valor"] == "Escuela Preparatoria No. 13"
