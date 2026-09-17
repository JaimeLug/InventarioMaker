"""Contenedores y acomodo (Fase 4a, migración 0009): alta, anidación, VEX/FTC, desactivar solo vacío,
acomodo directo, propuestas de docentes y préstamos por contenedor.
"""
import uuid

import pytest
from psycopg.types.json import Jsonb

from ayudantes import archivo, como, insertar, mov, rpc, usuario
from test_acceso import rechazo


@pytest.fixture
def taller(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    d = usuario(bd, "DOCENTE", "Laura Gómez", pin="4826")
    vex = insertar(bd, "articulo", nombre="Batería VEX V5", categoria="VEX")
    ftc = insertar(bd, "articulo", nombre="Control Hub", categoria="FTC")
    pinza = insertar(bd, "articulo", nombre="Pinza de punta", categoria="HERRAMIENTAS")
    mov(bd, pinza, "ALTA", 4, r)
    return dict(bd=bd, r=r, d=d, vex=vex, ftc=ftc, pinza=pinza)


def crear(bd, yo, nombre, tipo="CAJON", padre=None, categoria=None, foto=None, nivel="CONTRASENA", cid=None):
    cid = cid or uuid.uuid4()
    with como(bd, yo, nivel=nivel):
        return cid, rpc(bd, "contenedor_crear", p_id=cid, p_nombre=nombre, p_tipo=tipo, p_padre=padre,
                        p_categoria=categoria, p_foto=foto, p_nota=None)


def acomodar(bd, yo, articulos, contenedor, nivel="CONTRASENA"):
    with como(bd, yo, nivel=nivel):
        return rpc(bd, "articulos_acomodar", p_articulos=list(articulos), p_contenedor=contenedor)


def test_arbol_de_contenedores_con_ruta_y_codigo(taller):
    bd, r = taller["bd"], taller["r"]
    gabinete, g = crear(bd, r, "Gabinete 2", "GABINETE")
    cajon, c = crear(bd, r, "Cajón B", padre=gabinete)
    assert g["codigo"].startswith("C-") and c["codigo"] != g["codigo"]
    assert crear(bd, r, "Cajón B", padre=gabinete, cid=cajon)[1] == c              # reintento: no duplica
    with como(bd):
        fila = bd.execute("select * from v_contenedores where id = %s", (cajon,)).fetchone()
    assert (fila["ruta"], fila["padre_codigo"], fila["articulos"]) == ("Gabinete 2 › Cajón B", g["codigo"], 0)

    with rechazo("PT403", "ROL"):
        crear(bd, taller["d"], "Cajón del docente")
    with rechazo("PT403", "NIVEL_CONTRASENA"):
        crear(bd, r, "Con PIN", nivel="PIN")
    with rechazo("P0001", contiene="Elige el tipo"):
        crear(bd, r, "Raro", tipo="COHETE")
    with rechazo("P0001", contiene="dentro de sí mismo"), como(bd, r):
        rpc(bd, "contenedor_editar", p_id=gabinete, p_nombre="Gabinete 2", p_tipo="GABINETE", p_padre=cajon,
            p_categoria=None, p_foto=None, p_nota=None)


def test_foto_del_contenedor_en_su_carpeta(taller):
    bd, r = taller["bd"], taller["r"]
    cid = uuid.uuid4()
    with rechazo("P0001", contiene="no terminó de subirse"):
        crear(bd, r, "Canasta", "CANASTA", foto=f"contenedores/{cid}/1.jpg", cid=cid)
    with rechazo("P0001", contiene="Ruta de foto inválida"):
        crear(bd, r, "Canasta", "CANASTA", foto="articulos/otra/1.jpg", cid=cid)
    archivo(bd, f"contenedores/{cid}/1.jpg")
    crear(bd, r, "Canasta", "CANASTA", foto=f"contenedores/{cid}/1.jpg", cid=cid)
    with como(bd, r):
        assert bd.execute("select app.puede_subir_foto_contenedor() as p").fetchone()["p"]
    with como(bd, taller["d"], nivel="PIN"):
        assert not bd.execute("select app.puede_subir_foto_contenedor() as p").fetchone()["p"]


def test_vex_y_ftc_no_se_mezclan_al_acomodar(taller):
    bd, r = taller["bd"], taller["r"]
    solo_vex, _ = crear(bd, r, "Caja VEX", "CAJA", categoria="VEX")
    mixto, _ = crear(bd, r, "Cajón general")
    with rechazo("P0001", contiene="solo puede ir en un contenedor \"Solo FTC\""):
        acomodar(bd, r, [taller["ftc"]], solo_vex)
    with rechazo("P0001", contiene="es solo para VEX"):
        acomodar(bd, r, [taller["pinza"]], solo_vex)
    with rechazo("P0001", contiene="mixto"):
        acomodar(bd, r, [taller["vex"]], mixto)
    assert acomodar(bd, r, [taller["vex"]], solo_vex) == 1
    assert acomodar(bd, r, [taller["vex"]], solo_vex) == 0                          # ya estaba ahí
    assert acomodar(bd, r, [taller["pinza"]], mixto) == 1
    with rechazo("P0001", contiene="también debe serlo"), como(bd, r):
        rpc(bd, "contenedor_crear", p_id=uuid.uuid4(), p_nombre="Bolsa", p_tipo="BOLSA", p_padre=solo_vex,
            p_categoria=None, p_foto=None, p_nota=None)
    with como(bd):
        a = bd.execute("select ubicacion_ruta, contenedor_codigo from v_inventario where id = %s", (taller["pinza"],)).fetchone()
    assert a["ubicacion_ruta"] == "Cajón general"
    assert bd.execute("select count(*) as n from bitacora where evento = 'UBICACION'").fetchone()["n"] == 2
    with rechazo("PT403", "ROL"):
        acomodar(bd, taller["d"], [taller["pinza"]], None)


def test_desactivar_solo_si_esta_vacio(taller):
    bd, r = taller["bd"], taller["r"]
    gabinete, _ = crear(bd, r, "Gabinete 1", "GABINETE")
    cajon, _ = crear(bd, r, "Cajón A", padre=gabinete)
    acomodar(bd, r, [taller["pinza"]], cajon)

    def activar(cid, valor):
        with como(bd, r):
            rpc(bd, "contenedor_activar", p_id=cid, p_activo=valor)

    with rechazo("P0001", contiene="tiene contenedores adentro"):
        activar(gabinete, False)
    with rechazo("P0001", contiene="todavía tiene 1 artículo"):
        activar(cajon, False)
    acomodar(bd, r, [taller["pinza"]], None)
    activar(cajon, False)
    activar(gabinete, False)
    with rechazo("P0001", contiene="reactívalo primero"):
        activar(cajon, True)
    with rechazo("P0001", contiene="desactivado"):
        acomodar(bd, r, [taller["pinza"]], cajon)
    with rechazo("P0001", contiene="No se borran"):
        bd.execute("delete from contenedor where id = %s", (cajon,))


def test_el_docente_propone_y_el_responsable_decide(taller):
    bd, r, d = taller["bd"], taller["r"], taller["d"]
    cajon_a, _ = crear(bd, r, "Cajón A")
    cajon_b, _ = crear(bd, r, "Cajón B")
    acomodar(bd, r, [taller["pinza"]], cajon_a)

    with como(bd, d, nivel="PIN"):
        rpc(bd, "ubicacion_proponer", p_articulo=taller["pinza"], p_contenedor=cajon_b, p_nota="Estaba en el B")
    with rechazo("P0001", contiene="ya está registrado"), como(bd, d, nivel="PIN"):
        rpc(bd, "ubicacion_proponer", p_articulo=taller["pinza"], p_contenedor=cajon_a, p_nota=None)
    with rechazo("P0001", contiene="no es \"Solo VEX\""), como(bd, d, nivel="PIN"):
        rpc(bd, "ubicacion_proponer", p_articulo=taller["vex"], p_contenedor=cajon_b, p_nota=None)

    with como(bd, r):
        assert rpc(bd, "por_revisar_contar") == 1
        propuestas = bd.execute("select * from public.ubicacion_propuestas()").fetchall()
        assert [(p["articulo"], p["actual"], p["propuesta"], p["propuesta_por"]) for p in propuestas] \
            == [("Pinza de punta", "Cajón A", "Cajón B", "Laura Gómez")]
        rpc(bd, "ubicacion_resolver", p_id=propuestas[0]["id"], p_aceptar=True, p_motivo=None)
    assert bd.execute("select contenedor_id from articulo where id = %s", (taller["pinza"],)).fetchone()["contenedor_id"] == cajon_b
    assert [a["titulo"] for a in bd.execute("select titulo from aviso").fetchall()] == ["Propuesta de ubicación"]
    with rechazo("P0001", contiene="ya se resolvió"), como(bd, r):
        rpc(bd, "ubicacion_resolver", p_id=propuestas[0]["id"], p_aceptar=False, p_motivo="x")


def test_prestamos_de_lo_que_vive_en_un_contenedor(taller):
    bd, r, d = taller["bd"], taller["r"], taller["d"]
    cajon, _ = crear(bd, r, "Cajón de pinzas")
    acomodar(bd, r, [taller["pinza"]], cajon)
    with como(bd, d, nivel="PIN"):
        rpc(bd, "prestamo_registrar", p_lineas=Jsonb([{"articulo_id": str(taller["pinza"]), "cantidad": 2}]),
            p_responsable_usuario=d, p_responsable_solicitante=None, p_fecha_compromiso=None, p_nota=None, p_comando=None)
        abiertos = bd.execute("select * from public.prestamos_de_contenedor(%s)", (cajon,)).fetchall()
    assert [(p["nombre"], p["pendiente"], p["a_cargo"]) for p in abiertos] == [("Pinza de punta", 2, "Laura Gómez")]
    with rechazo("42501"), como(bd):                                                # sin sesión, ni siquiera se llama
        bd.execute("select * from public.prestamos_de_contenedor(%s)", (cajon,))
