"""Acceso, cuentas, alta y edición de artículos, fotos (Fase 2, migración 0005).

Cada prueba entra con los mismos permisos que usa la API de Supabase:
visitante sin sesión, docente con PIN, responsable con contraseña, función del servidor.
"""
import contextlib
import uuid

import psycopg
import pytest
from psycopg.types.json import Jsonb

from ayudantes import CONTRASENA_PRUEBA, archivo, como, como_servidor, existencias, nueva_sesion, rpc, usuario

DATOS = {"nombre": "Vernier digital", "marca_modelo": "Truper 14388", "categoria": "HERRAMIENTAS"}


@contextlib.contextmanager
def rechazo(sqlstate, detalle=None, contiene=None):
    with pytest.raises(psycopg.Error) as e:
        yield
    assert e.value.sqlstate == sqlstate, f"{e.value.sqlstate}: {e.value}"
    if detalle:
        assert e.value.diag.message_detail == detalle
    if contiene:
        assert contiene in str(e.value)


def alta(bd, yo, *, cantidad=3, datos=None, nivel="CONTRASENA", sesion=None, comando=None, fotos=None, subida=True):
    aid = uuid.uuid4()
    if fotos is None:
        ruta = f"articulos/{aid}/principal.jpg"
        fotos = [{"ruta": archivo(bd, ruta) if subida else ruta}]
    with como(bd, yo, nivel=nivel, sesion=sesion):
        resultado = rpc(bd, "articulo_crear", p_id=aid, p_datos=Jsonb(datos or DATOS), p_cantidad=cantidad,
                        p_fotos=Jsonb(fotos), p_comando=comando)
    return aid, resultado


def confirmar(bd, yo, sesion, contrasena=CONTRASENA_PRUEBA):
    with como(bd, yo, sesion=sesion):
        return rpc(bd, "confirmar_contrasena", p_contrasena=contrasena)


@pytest.fixture
def cuentas(bd):
    return {
        "subadmin": usuario(bd, "SUBADMIN", "Sub Administración"),
        "responsable": usuario(bd, "RESPONSABLE", "Jaime Lugo"),
        "docente": usuario(bd, "DOCENTE", "Laura Gómez", pin="4826"),
    }


# --- Sesión ---------------------------------------------------------------
def test_mi_sesion(bd, cuentas):
    with como(bd):
        assert rpc(bd, "mi_sesion") is None
    with como(bd, cuentas["docente"], nivel="PIN"):
        s = rpc(bd, "mi_sesion")
    assert (s["nombre"], s["rol"], s["nivel"], s["vigente"], s["tiene_pin"]) == ("Laura Gómez", "DOCENTE", "PIN", True, True)
    with como(bd, cuentas["responsable"]):
        assert rpc(bd, "mi_sesion")["nivel"] == "CONTRASENA"


def test_la_jornada_vence_a_las_8_horas(bd, cuentas):
    vieja = nueva_sesion(bd, cuentas["responsable"], hace_horas=8.5)
    with rechazo("PT401", "SESION_VENCIDA"):
        alta(bd, cuentas["responsable"], sesion=vieja)
    with como(bd, cuentas["responsable"], sesion=vieja):
        assert rpc(bd, "mi_sesion")["vigente"] is False


def test_cuenta_desactivada_no_opera(bd, cuentas):
    bd.execute("update usuario set activo = false where id = %s", (cuentas["responsable"],))
    with rechazo("PT403", "CUENTA_INACTIVA"):
        alta(bd, cuentas["responsable"])


def test_sin_sesion_no_se_puede_llamar_a_escrituras(bd):
    with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd):
        rpc(bd, "articulo_crear", p_id=uuid.uuid4(), p_datos=Jsonb(DATOS), p_cantidad=1, p_fotos=Jsonb([]))


# --- Alta de artículos ------------------------------------------------------
def test_alta_completa(bd, cuentas):
    aid, r = alta(bd, cuentas["responsable"], cantidad=3)
    assert r["codigo"] == "A-1001"
    a = bd.execute("select * from articulo where id = %s", (aid,)).fetchone()
    assert (a["estado_inventario"], a["cantidad"], a["etiquetado"]) == ("VERIFICADO", 3, "CONTENEDOR")
    m = bd.execute("select * from movimiento where articulo_id = %s", (aid,)).fetchone()
    assert (m["tipo"], m["cantidad"], m["autorizado_por"]) == ("ALTA", 3, cuentas["responsable"])
    f = bd.execute("select * from foto where articulo_id = %s", (aid,)).fetchone()
    assert (f["es_principal"], f["tomada_por"]) == (True, cuentas["responsable"])


def test_alta_es_de_responsable_o_subadmin_con_contrasena(bd, cuentas):
    with rechazo("PT403", "ROL"):
        alta(bd, cuentas["docente"])
    with rechazo("PT403", "NIVEL_CONTRASENA"):
        alta(bd, cuentas["responsable"], nivel="PIN")
    alta(bd, cuentas["subadmin"])


def test_alta_repetida_con_el_mismo_comando_no_duplica(bd, cuentas):
    comando = uuid.uuid4()
    _, primero = alta(bd, cuentas["responsable"], comando=comando)
    _, segundo = alta(bd, cuentas["responsable"], comando=comando)
    assert primero == segundo
    assert bd.execute("select count(*) as n from articulo").fetchone()["n"] == 1


def test_alta_sin_conteo_queda_por_contar(bd, cuentas):
    aid, _ = alta(bd, cuentas["responsable"], cantidad=None)
    a = bd.execute("select * from v_inventario where id = %s", (aid,)).fetchone()
    assert (a["estado_inventario"], a["conteo_desconocido"], a["prestable"]) == ("POR_CONTAR", True, False)
    t = bd.execute("select tipo, origen from tarea_pendiente where articulo_id = %s", (aid,)).fetchone()
    assert (t["tipo"], t["origen"]) == ("CONTAR", "SISTEMA")


def test_validaciones_del_alta(bd, cuentas):
    r = cuentas["responsable"]
    with rechazo("P0001", contiene="al menos una foto"):
        alta(bd, r, fotos=[])
    with rechazo("P0001", contiene="Elige la categoría"):
        alta(bd, r, datos={**DATOS, "categoria": "SIN_CLASIFICAR"})
    with rechazo("P0001", contiene="no terminó de subirse"):
        alta(bd, r, subida=False)
    with rechazo("P0001", contiene="no se capturan en el alta: cantidad"):
        alta(bd, r, datos={**DATOS, "cantidad": 50})
    alta(bd, r, datos={**DATOS, "num_serie": "SN-001"})
    with rechazo("P0001", contiene="ya está registrado"):
        alta(bd, r, datos={**DATOS, "num_serie": "SN-001"})


def test_foto_de_otro_articulo_se_rechaza(bd, cuentas):
    ajena = archivo(bd, f"articulos/{uuid.uuid4()}/foto.jpg")
    with rechazo("P0001", contiene="Ruta de foto inválida"):
        alta(bd, cuentas["responsable"], fotos=[{"ruta": ajena}])


# --- Edición ---------------------------------------------------------------
def test_edicion_queda_en_bitacora_y_no_toca_cantidades(bd, cuentas):
    r = cuentas["responsable"]
    aid, _ = alta(bd, r)
    with como(bd, r):
        rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"observaciones": "Pila nueva"}), p_justificacion=None)
    evento = bd.execute("select usuario_id, datos from bitacora where registro_id = %s and evento = 'EDICION'", (str(aid),)).fetchone()
    assert evento["usuario_id"] == r
    assert evento["datos"]["cambios"]["observaciones"]["despues"] == "Pila nueva"
    with rechazo("P0001", contiene="no se editan aquí: cantidad"):
        with como(bd, r):
            rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"cantidad": 99}), p_justificacion=None)
    with rechazo("PT403", "ROL"):
        with como(bd, cuentas["docente"]):
            rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"nombre": "x"}), p_justificacion=None)


def test_pasar_entre_vex_y_ftc_pide_justificacion_y_contrasena(bd, cuentas):
    r = cuentas["responsable"]
    aid, _ = alta(bd, r, datos={"nombre": "Engrane", "categoria": "VEX"})
    sesion = nueva_sesion(bd, r)

    def cambiar(justificacion):
        with como(bd, r, sesion=sesion):
            rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"categoria": "FTC"}), p_justificacion=justificacion)

    with rechazo("P0001", contiene="escribe por qué"):
        cambiar(None)
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        cambiar("Tiene logo de REV")
    assert confirmar(bd, r, sesion, "equivocada")["ok"] is False
    assert confirmar(bd, r, sesion)["ok"] is True
    cambiar("Tiene logo de REV")
    evento = bd.execute("select datos from bitacora where registro_id = %s and evento = 'EDICION'", (str(aid),)).fetchone()
    assert evento["datos"]["justificacion"] == "Tiene logo de REV"

    # La reconfirmación se gastó: regresar a VEX pide contraseña otra vez.
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        with como(bd, r, sesion=sesion):
            rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"categoria": "VEX"}), p_justificacion="Error mío")


def test_clasificar_algo_sin_clasificar(bd, cuentas):
    r = cuentas["responsable"]
    aid = bd.execute("insert into articulo (nombre, categoria, estado_inventario) values ('Caja de madera', "
                     "'SIN_CLASIFICAR', 'SIN_CLASIFICAR') returning id").fetchone()["id"]
    with como(bd, r):
        rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"categoria": "COMUN"}), p_justificacion="Son herrajes de mueble")
    a = bd.execute("select categoria, estado_inventario from articulo where id = %s", (aid,)).fetchone()
    assert (a["categoria"], a["estado_inventario"]) == ("COMUN", "POR_VERIFICAR")
    with rechazo("P0001", contiene="no puede volver"):
        with como(bd, r):
            rpc(bd, "articulo_editar", p_id=aid, p_cambios=Jsonb({"categoria": "SIN_CLASIFICAR"}), p_justificacion=None)


# --- Contraseña y PIN ---------------------------------------------------------
def test_confirmar_contrasena_se_bloquea_tras_5_fallos(bd, cuentas):
    r = cuentas["responsable"]
    sesion = nueva_sesion(bd, r)
    restantes = [confirmar(bd, r, sesion, "mala")["restantes"] for _ in range(5)]
    assert restantes == [4, 3, 2, 1, 0]
    assert confirmar(bd, r, sesion)["motivo"] == "BLOQUEADO"
    assert bd.execute("select count(*) as n from bitacora where evento = 'CONTRASENA_FALLIDA'").fetchone()["n"] == 5


def test_confirmar_contrasena_exige_sesion_con_contrasena(bd, cuentas):
    with rechazo("PT403", "NIVEL_CONTRASENA"):
        with como(bd, cuentas["docente"], nivel="PIN"):
            rpc(bd, "confirmar_contrasena", p_contrasena=CONTRASENA_PRUEBA)


def test_pin_solo_lo_verifica_el_servidor(bd, cuentas):
    for rol in (None, cuentas["docente"]):
        with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd, rol):
            rpc(bd, "pin_verificar", p_usuario=cuentas["docente"], p_pin="4826")
    with como_servidor(bd):
        r = rpc(bd, "pin_verificar", p_usuario=cuentas["docente"], p_pin="4826")
    assert r["ok"] is True and r["correo"].endswith("@prueba.local")


def test_pin_se_bloquea_tras_5_fallos(bd, cuentas):
    d = cuentas["docente"]

    def intentar(pin):
        with como_servidor(bd):
            return rpc(bd, "pin_verificar", p_usuario=d, p_pin=pin)

    assert [intentar("0000")["restantes"] for _ in range(4)] == [4, 3, 2, 1]
    assert intentar("0000")["motivo"] == "BLOQUEADO"
    assert intentar("4826")["motivo"] == "BLOQUEADO"   # ni con el PIN correcto mientras dure el bloqueo
    eventos = [e["evento"] for e in bd.execute("select evento from bitacora order by id").fetchall()]
    assert eventos == ["PIN_FALLIDO"] * 4 + ["PIN_BLOQUEADO"]


def test_lista_de_nombres_para_pin(bd, cuentas):
    with como(bd):
        nombres = bd.execute("select nombre from public.pin_usuarios()").fetchall()
    assert [n["nombre"] for n in nombres] == ["Laura Gómez"]


def test_establecer_pin(bd, cuentas):
    d, r, s = cuentas["docente"], cuentas["responsable"], cuentas["subadmin"]

    def establecer(yo, destino, pin, confirmada=True):
        sesion = nueva_sesion(bd, yo)
        if confirmada:
            assert confirmar(bd, yo, sesion)["ok"]
        with como(bd, yo, sesion=sesion):
            rpc(bd, "pin_establecer", p_usuario=destino, p_pin=pin)

    for malo, mensaje in (("12", "de 4 a 6 números"), ("7777", "mismo número"), ("3456", "secuencia"), ("9876", "secuencia")):
        with rechazo("P0001", contiene=mensaje):
            establecer(d, d, malo)
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        establecer(d, d, "5139", confirmada=False)
    establecer(d, d, "5139")
    with como_servidor(bd):
        assert rpc(bd, "pin_verificar", p_usuario=d, p_pin="5139")["ok"] is True

    with rechazo("PT403", "ROL"):
        establecer(d, r, "5139")          # un docente no cambia el PIN de otro
    establecer(r, d, "7302")              # el responsable sí, el de un docente
    with rechazo("PT403", "ROL"):
        establecer(r, s, "7302")          # pero no el de sub administración
    establecer(s, r, "8415")              # sub administración, el de cualquiera


# --- Cuentas ------------------------------------------------------------------
def test_quien_administra_cuentas(bd, cuentas):
    d, r, s = cuentas["docente"], cuentas["responsable"], cuentas["subadmin"]

    def autorizar(yo, accion, rol=None, destino=None):
        sesion = nueva_sesion(bd, yo)
        confirmar(bd, yo, sesion)
        with como(bd, yo, sesion=sesion):
            return rpc(bd, "cuenta_autorizar", p_accion=accion, p_rol=rol, p_usuario=destino)

    with como(bd, r):
        assert len(bd.execute("select * from public.cuentas_listar()").fetchall()) == 3
    with rechazo("PT403", "ROL"), como(bd, d):
        bd.execute("select * from public.cuentas_listar()")

    assert autorizar(r, "CREAR", "DOCENTE") == r
    with rechazo("PT403", "ROL"):
        autorizar(r, "CREAR", "RESPONSABLE")
    assert autorizar(s, "CREAR", "SUBADMIN") == s
    with rechazo("P0001", contiene="propia cuenta"):
        autorizar(s, "DESACTIVAR", destino=s)
    with rechazo("PT403", "ROL"):
        autorizar(r, "DESACTIVAR", destino=s)

    with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd, s):
        rpc(bd, "cuenta_registrar", p_id=uuid.uuid4(), p_nombre="x", p_rol="DOCENTE", p_correo=None, p_creada_por=s)


# --- Fotos ----------------------------------------------------------------------
def test_docente_con_pin_agrega_fotos_pero_no_cambia_la_principal(bd, cuentas):
    r, d = cuentas["responsable"], cuentas["docente"]
    aid, _ = alta(bd, r)
    placa = archivo(bd, f"articulos/{aid}/placa.jpg")
    with como(bd, d, nivel="PIN"):
        nueva = rpc(bd, "foto_agregar", p_articulo=aid, p_ruta=placa, p_tipo="PLACA_SERIE", p_principal=False)
    f = bd.execute("select es_principal, tomada_por, tipo from foto where id = %s", (nueva,)).fetchone()
    assert (f["es_principal"], f["tomada_por"], f["tipo"]) == (False, d, "PLACA_SERIE")

    otra = archivo(bd, f"articulos/{aid}/otra.jpg")
    # Un docente nunca cambia la principal: se le dice que su cuenta no puede, no se le pide contraseña.
    with rechazo("PT403", "ROL"), como(bd, d, nivel="PIN"):
        rpc(bd, "foto_agregar", p_articulo=aid, p_ruta=otra, p_tipo="GENERAL", p_principal=True)
    with rechazo("PT403", "NIVEL_CONTRASENA"), como(bd, cuentas["responsable"], nivel="PIN"):
        rpc(bd, "foto_agregar", p_articulo=aid, p_ruta=otra, p_tipo="GENERAL", p_principal=True)
    with rechazo("P0001", contiene="reporte o una entrega"), como(bd, d, nivel="PIN"):
        rpc(bd, "foto_agregar", p_articulo=aid, p_ruta=otra, p_tipo="DANO", p_principal=False)

    with como(bd, r):
        rpc(bd, "foto_hacer_principal", p_foto=nueva)
    principales = bd.execute("select id from foto where articulo_id = %s and es_principal", (aid,)).fetchall()
    assert [p["id"] for p in principales] == [nueva]
    assert existencias(bd, aid)["existencia"] == 3


def test_subir_archivos_al_almacen(bd, cuentas):
    ruta = f"articulos/{uuid.uuid4()}/foto.jpg"
    subir = "insert into storage.objects (bucket_id, name) values ('fotos', %s)"
    with como(bd, cuentas["docente"], nivel="PIN"):
        bd.execute(subir, (ruta,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd):
        bd.execute(subir, (f"articulos/{uuid.uuid4()}/x.jpg",))
    with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd, cuentas["docente"]):
        bd.execute(subir, ("otra-carpeta/x.jpg",))
    vieja = nueva_sesion(bd, cuentas["docente"], hace_horas=9)
    with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd, cuentas["docente"], sesion=vieja):
        bd.execute(subir, (f"articulos/{uuid.uuid4()}/y.jpg",))
