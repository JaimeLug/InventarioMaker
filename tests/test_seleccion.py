"""Fase 11 (migraciones 0016 y 0017): la selección de robótica propone, el responsable decide."""
import uuid

import psycopg
import pytest
from psycopg.types.json import Jsonb

from ayudantes import archivo, como, como_servidor, existencias, insertar, mov, rpc, usuario
from test_acceso import alta, confirmar, rechazo


@pytest.fixture
def lab(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    sel = usuario(bd, "SELECCION", "Ana Selección")
    aid, _ = alta(bd, r)
    return dict(bd=bd, r=r, sel=sel, articulo=aid)


def sesion_sel(bd, sel):
    """La selección siempre entra con contraseña: no tiene PIN."""
    return como(bd, sel, nivel="CONTRASENA")


# --- Lo que NO puede -------------------------------------------------------------------------


def test_no_puede_prestar(lab):
    bd, sel = lab["bd"], lab["sel"]
    persona = insertar(bd, "solicitante", nombre_completo="Juan Pérez", tipo="ALUMNO", matricula_o_clave="23-0456")
    with rechazo("PT403", "ROL"), sesion_sel(bd, sel):
        rpc(bd, "prestamo_registrar", p_lineas=Jsonb([{"articulo_id": str(lab["articulo"]), "cantidad": 1}]),
            p_responsable_solicitante=persona, p_responsable_usuario=None, p_fecha_compromiso=None, p_nota=None, p_comando=None)


def test_no_puede_ver_a_los_alumnos(lab):
    bd, sel = lab["bd"], lab["sel"]
    insertar(bd, "solicitante", nombre_completo="Juan Pérez", tipo="ALUMNO", matricula_o_clave="23-0456")
    with rechazo("PT403", "ROL"), sesion_sel(bd, sel):
        rpc(bd, "solicitante_buscar", p_matricula="23-0456")
    with rechazo("PT403", "ROL"), sesion_sel(bd, sel):
        bd.execute("select * from public.solicitante_buscar_conocido(%s)", ("perez",)).fetchall()


def test_no_puede_dar_de_baja_ni_ajustar(lab):
    bd, sel, a = lab["bd"], lab["sel"], lab["articulo"]
    with rechazo("PT403", "ROL"), sesion_sel(bd, sel):
        rpc(bd, "baja_registrar", p_articulo=a, p_cantidad=1, p_de_fuera_de_servicio=False,
            p_motivo="OTRO", p_justificacion="No debería poder", p_oficio=None)
    with rechazo("PT403", "ROL"), sesion_sel(bd, sel):
        rpc(bd, "ajuste_conteo", p_articulo=a, p_en_taller=1, p_motivo="CONTEO_FISICO", p_nota=None)


def test_no_puede_aprobar_sus_propias_propuestas(lab):
    bd, sel = lab["bd"], lab["sel"]
    pid = uuid.uuid4()
    ruta = archivo(bd, f"articulos/{pid}/foto.jpg")
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid, p_tipo="ALTA", p_datos=Jsonb({"nombre": "Servo nuevo", "categoria": "FTC"}),
            p_cantidad=2, p_fotos=Jsonb([{"ruta": ruta}]), p_nota=None)
    with rechazo("PT403", "ROL"), sesion_sel(bd, sel):
        rpc(bd, "propuesta_aprobar", p_id=pid, p_datos=None)


def test_no_sale_en_la_lista_de_pin_ni_se_le_pone_pin(lab):
    bd, r, sel = lab["bd"], lab["r"], lab["sel"]
    # Aunque alguien le pusiera un PIN a mano, no aparece en "¿Quién eres?"
    bd.execute("update public.usuario set pin_hash = 'x' where id = %s", (sel,))
    nombres = [f["nombre"] for f in bd.execute("select * from public.pin_usuarios()").fetchall()]
    assert "Ana Selección" not in nombres

    sesion = None
    with rechazo("PT403", "ROL"):
        with como(bd, r, nivel="CONTRASENA") as sesion:
            rpc(bd, "pin_establecer", p_usuario=sel, p_pin="4827")


# --- Lo que SÍ puede -------------------------------------------------------------------------


def test_sube_fotos_que_quedan_sin_verificar(lab):
    bd, r, sel, a = lab["bd"], lab["r"], lab["sel"], lab["articulo"]
    ruta = archivo(bd, f"articulos/{a}/de-la-seleccion.jpg")
    with sesion_sel(bd, sel):
        foto = rpc(bd, "foto_agregar", p_articulo=a, p_ruta=ruta, p_tipo="GENERAL", p_principal=False)
    f = bd.execute("select es_principal, verificada_en, tomada_por from public.foto where id = %s", (foto,)).fetchone()
    assert (f["es_principal"], f["verificada_en"], f["tomada_por"]) == (False, None, sel)

    # Al responsable le llegó el aviso y la ve en su lista
    assert bd.execute("select count(*) from public.aviso where usuario_id = %s", (r,)).fetchone()["count"] >= 1
    with como(bd, r, nivel="CONTRASENA"):
        pendientes = bd.execute("select * from public.fotos_por_verificar()").fetchall()
    assert [p["id"] for p in pendientes] == [foto]

    # Quien la subió también la ve mientras espera (y solo la suya)
    with sesion_sel(bd, sel):
        mias = bd.execute("select * from public.fotos_por_verificar()").fetchall()
    assert [m["id"] for m in mias] == [foto]

    with como(bd, r, nivel="CONTRASENA"):
        rpc(bd, "foto_verificar", p_foto=foto, p_aceptar=True, p_motivo=None)
    assert bd.execute("select verificada_en from public.foto where id = %s", (foto,)).fetchone()["verificada_en"] is not None
    # Ya verificada, sale de la lista de quien la subió
    with sesion_sel(bd, sel):
        assert bd.execute("select * from public.fotos_por_verificar()").fetchall() == []


def test_la_foto_descartada_pide_motivo_y_se_quita(lab):
    bd, r, sel, a = lab["bd"], lab["r"], lab["sel"], lab["articulo"]
    ruta = archivo(bd, f"articulos/{a}/borrosa.jpg")
    with sesion_sel(bd, sel):
        foto = rpc(bd, "foto_agregar", p_articulo=a, p_ruta=ruta, p_tipo="GENERAL", p_principal=False)
    with pytest.raises(psycopg.errors.RaiseException, match="por qué"), como(bd, r, nivel="CONTRASENA"):
        rpc(bd, "foto_verificar", p_foto=foto, p_aceptar=False, p_motivo="")
    with como(bd, r, nivel="CONTRASENA"):
        rpc(bd, "foto_verificar", p_foto=foto, p_aceptar=False, p_motivo="Salió movida")
    f = bd.execute("select borrada_en, borrada_motivo from public.foto where id = %s", (foto,)).fetchone()
    assert f["borrada_en"] is not None and f["borrada_motivo"] == "Salió movida"


def test_propone_un_articulo_y_el_responsable_lo_aprueba(lab):
    bd, r, sel = lab["bd"], lab["r"], lab["sel"]
    pid = uuid.uuid4()
    ruta = archivo(bd, f"articulos/{pid}/servo.jpg")
    datos = {"nombre": "Servomotor REV Smart", "categoria": "FTC", "unidad": "pieza"}
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid, p_tipo="ALTA", p_datos=Jsonb(datos), p_cantidad=4,
            p_fotos=Jsonb([{"ruta": ruta}]), p_nota="Llegaron 4 en la caja nueva")

    with como(bd, r, nivel="CONTRASENA") as sesion:
        pendientes = bd.execute("select * from public.propuestas_listar(%s)", ("PENDIENTE",)).fetchall()
        assert [(p["tipo"], p["creada_por"]) for p in pendientes] == [("ALTA", "Ana Selección")]
        confirmar(bd, r, sesion)
        rpc(bd, "propuesta_aprobar", p_id=pid, p_datos=None)

    creado = bd.execute("select nombre, categoria, activo from public.articulo where id = %s", (pid,)).fetchone()
    assert (creado["nombre"], creado["categoria"], creado["activo"]) == ("Servomotor REV Smart", "FTC", True)
    assert existencias(bd, pid)["en_taller"] == 4
    assert bd.execute("select estado from public.propuesta where id = %s", (pid,)).fetchone()["estado"] == "APROBADA"
    # Quien la propuso recibe su aviso
    assert bd.execute("select count(*) from public.aviso where usuario_id = %s and titulo like 'Tu propuesta%%'",
                      (sel,)).fetchone()["count"] == 1


def test_propone_una_correccion_y_se_aplica(lab):
    bd, r, sel, a = lab["bd"], lab["r"], lab["sel"], lab["articulo"]
    pid = uuid.uuid4()
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid, p_tipo="CORRECCION", p_articulo=a,
            p_datos=Jsonb({"marca_modelo": "Truper 14388-A"}), p_cantidad=None, p_fotos=Jsonb([]), p_nota="Dice A atrás")
    with como(bd, r, nivel="CONTRASENA") as sesion:
        confirmar(bd, r, sesion)
        rpc(bd, "propuesta_aprobar", p_id=pid, p_datos=None)
    assert bd.execute("select marca_modelo from public.articulo where id = %s", (a,)).fetchone()["marca_modelo"] == "Truper 14388-A"


def test_descartar_pide_motivo_y_avisa(lab):
    bd, r, sel = lab["bd"], lab["r"], lab["sel"]
    pid = uuid.uuid4()
    ruta = archivo(bd, f"articulos/{pid}/foto.jpg")
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid, p_tipo="ALTA", p_datos=Jsonb({"nombre": "Cosa repetida", "categoria": "COMUN"}),
            p_cantidad=1, p_fotos=Jsonb([{"ruta": ruta}]), p_nota=None)
    with pytest.raises(psycopg.errors.RaiseException, match="por qué"), como(bd, r, nivel="CONTRASENA"):
        rpc(bd, "propuesta_descartar", p_id=pid, p_motivo="  ")
    with como(bd, r, nivel="CONTRASENA"):
        rpc(bd, "propuesta_descartar", p_id=pid, p_motivo="Ya existe como A-0001")
    p = bd.execute("select estado, motivo from public.propuesta where id = %s", (pid,)).fetchone()
    assert (p["estado"], p["motivo"]) == ("DESCARTADA", "Ya existe como A-0001")
    assert bd.execute("select count(*) from public.aviso where usuario_id = %s and titulo like 'Tu propuesta%%'",
                      (sel,)).fetchone()["count"] == 1


def test_solo_ve_sus_propias_propuestas(lab):
    bd, r, sel = lab["bd"], lab["r"], lab["sel"]
    otro = usuario(bd, "SELECCION", "Beto Selección")
    for quien, nombre in ((sel, "Lo de Ana"), (otro, "Lo de Beto")):
        pid = uuid.uuid4()
        ruta = archivo(bd, f"articulos/{pid}/f.jpg")
        with como(bd, quien, nivel="CONTRASENA"):
            rpc(bd, "propuesta_crear", p_id=pid, p_tipo="ALTA", p_datos=Jsonb({"nombre": nombre, "categoria": "COMUN"}),
                p_cantidad=1, p_fotos=Jsonb([{"ruta": ruta}]), p_nota=None)
    with sesion_sel(bd, sel):
        mias = bd.execute("select * from public.propuestas_listar(%s)", ("PENDIENTE",)).fetchall()
    assert [m["datos"]["nombre"] for m in mias] == ["Lo de Ana"]
    with como(bd, r, nivel="CONTRASENA"):
        todas = bd.execute("select * from public.propuestas_listar(%s)", ("PENDIENTE",)).fetchall()
    assert len(todas) == 2


def test_avisa_si_el_articulo_quiza_ya_existe(lab):
    bd, sel = lab["bd"], lab["sel"]
    with sesion_sel(bd, sel):
        parecidos = bd.execute("select * from public.articulos_parecidos(%s)", ("vernier",)).fetchall()
    assert [p["nombre"] for p in parecidos] == ["Vernier digital"]
    with sesion_sel(bd, sel):
        assert bd.execute("select * from public.articulos_parecidos(%s)", ("xy",)).fetchall() == []


def test_puede_contar_suelto_y_dentro_del_inventario(lab):
    bd, r, sel, a = lab["bd"], lab["r"], lab["sel"], lab["articulo"]
    with sesion_sel(bd, sel):
        r1 = rpc(bd, "conteo_proponer", p_articulo=a, p_en_taller=2, p_nota="Conté dos")
    assert r1["diferencia"] == 2 - existencias(bd, a)["en_taller"]

    with como(bd, r, nivel="CONTRASENA"):
        inv = rpc(bd, "inventario_abrir", p_nombre="Inventario de prueba", p_alcance=Jsonb({"categorias": ["HERRAMIENTAS"]}))
    with sesion_sel(bd, sel):
        rpc(bd, "inventario_contar", p_inventario=inv, p_articulo=a, p_cantidad=2, p_contenedor=None, p_nota=None)
    fila = bd.execute("select cantidad_fisica, contado_por from public.conteo_linea where inventario_id = %s", (inv,)).fetchone()
    assert (fila["cantidad_fisica"], fila["contado_por"]) == (2, sel)


def test_puede_reportar_un_dano(lab):
    bd, sel, a = lab["bd"], lab["sel"], lab["articulo"]
    iid = uuid.uuid4()
    with sesion_sel(bd, sel):
        rpc(bd, "incidencia_reportar", p_id=iid, p_articulo=a, p_tipo="DANO", p_cantidad=1, p_prestamo=None,
            p_nota="Se le rompió la punta", p_fotos=Jsonb([]), p_sin_foto="No traigo el celular a la mano")
    assert bd.execute("select reportada_por from public.incidencia where id = %s", (iid,)).fetchone()["reportada_por"] == sel


def test_puede_proponer_ubicacion_y_la_propuesta_llega_al_responsable(lab):
    bd, r, sel, a = lab["bd"], lab["r"], lab["sel"], lab["articulo"]
    cont = insertar(bd, "contenedor", nombre="Cajón B")
    with sesion_sel(bd, sel):
        pid = rpc(bd, "ubicacion_proponer", p_articulo=a, p_contenedor=cont, p_nota="Lo encontré aquí")
    assert pid is not None
    # El artículo NO se mueve hasta que el responsable acepte.
    assert bd.execute("select contenedor_id from public.articulo where id = %s", (a,)).fetchone()["contenedor_id"] is None
    # Llegó el aviso al responsable.
    assert bd.execute("select count(*) from public.aviso where usuario_id = %s", (r,)).fetchone()["count"] >= 1
    # La propuesta existe y está pendiente.
    p = bd.execute("select estado, propuesta_por from public.propuesta_ubicacion where id = %s", (pid,)).fetchone()
    assert (p["estado"], p["propuesta_por"]) == ("PENDIENTE", sel)


def test_ve_sus_propios_reportes_en_mis_reportes(lab):
    bd, r, sel, a = lab["bd"], lab["r"], lab["sel"], lab["articulo"]
    iid = uuid.uuid4()
    with sesion_sel(bd, sel):
        # La validación pide foto o una explicación de al menos 15 letras.
        rpc(bd, "incidencia_reportar", p_id=iid, p_articulo=a, p_tipo="PERDIDA", p_cantidad=1, p_prestamo=None,
            p_nota="Se extravió durante la práctica", p_fotos=Jsonb([]),
            p_sin_foto="No se puede tomar foto en este momento")
    with sesion_sel(bd, sel):
        mis = bd.execute("select * from public.mis_reportes()").fetchall()
    assert len(mis) == 1 and mis[0]["id"] == iid
    # El responsable solo ve los suyos (ninguno en este escenario).
    with como(bd, r, nivel="CONTRASENA"):
        suyos = bd.execute("select * from public.mis_reportes()").fetchall()
    assert suyos == []


def test_recibe_avisos_propios_y_puede_leerlos(lab):
    bd, r, sel = lab["bd"], lab["r"], lab["sel"]
    pid = uuid.uuid4()
    ruta = archivo(bd, f"articulos/{pid}/f.jpg")
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid, p_tipo="ALTA",
            p_datos=Jsonb({"nombre": "Sensor de distancia", "categoria": "FTC"}),
            p_cantidad=1, p_fotos=Jsonb([{"ruta": ruta}]), p_nota=None)
    # Antes de que el responsable resuelva, la selección no tiene avisos todavía.
    with sesion_sel(bd, sel):
        assert rpc(bd, "avisos_sin_leer") == 0
    with como(bd, r, nivel="CONTRASENA") as sesion:
        confirmar(bd, r, sesion)
        rpc(bd, "propuesta_descartar", p_id=pid, p_motivo="Ya existe en el catálogo")
    # Ahora sí hay un aviso: la propuesta no procedió.
    with sesion_sel(bd, sel):
        assert rpc(bd, "avisos_sin_leer") == 1
        # avisos_listar() devuelve table: usar fetchall, no rpc().
        lista = bd.execute("select * from public.avisos_listar()").fetchall()
    assert len(lista) == 1 and not lista[0]["leido"]


def test_responsable_crea_y_desactiva_cuenta_seleccion_pero_no_subadmin(lab):
    """El responsable administra cuentas DOCENTE y SELECCION; no puede crear SUBADMIN."""
    bd, r = lab["bd"], lab["r"]
    # El responsable puede crear una cuenta de selección.
    with como(bd, r, nivel="CONTRASENA") as sesion:
        confirmar(bd, r, sesion)
        rpc(bd, "cuenta_autorizar", p_accion="CREAR", p_rol="SELECCION")
    # El responsable NO puede crear una cuenta de subadmin.
    with rechazo("PT403", "ROL"), como(bd, r, nivel="CONTRASENA") as sesion:
        confirmar(bd, r, sesion)
        rpc(bd, "cuenta_autorizar", p_accion="CREAR", p_rol="SUBADMIN")
    # Puede desactivar una cuenta de selección existente.
    sel2 = usuario(bd, "SELECCION", "Carla Selección")
    with como(bd, r, nivel="CONTRASENA") as sesion:
        confirmar(bd, r, sesion)
        rpc(bd, "cuenta_autorizar", p_accion="DESACTIVAR", p_usuario=sel2)


def test_fotos_de_alta_quedan_verificadas_al_aprobar_y_no_quedan_sueltas_al_descartar(lab):
    """Las fotos de una propuesta de ALTA viven en propuesta.fotos (JSONB).
    Al aprobar: articulo_crear las inserta en public.foto ya verificadas.
    Al descartar: nunca se insertaron, así que no hay foto suelta que limpiar."""
    bd, r, sel = lab["bd"], lab["r"], lab["sel"]

    # Aprobar: las fotos que venían con la propuesta quedan verificadas al crearse el artículo.
    pid1 = uuid.uuid4()
    ruta1 = archivo(bd, f"articulos/{pid1}/sensor.jpg")
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid1, p_tipo="ALTA",
            p_datos=Jsonb({"nombre": "Sensor infrarrojo", "categoria": "FTC"}),
            p_cantidad=2, p_fotos=Jsonb([{"ruta": ruta1}]), p_nota=None)
    with como(bd, r, nivel="CONTRASENA") as sesion:
        confirmar(bd, r, sesion)
        rpc(bd, "propuesta_aprobar", p_id=pid1, p_datos=None)
    # Después de aprobar, la foto existe en la tabla y ya fue verificada.
    f1 = bd.execute("select verificada_en, borrada_en from public.foto where articulo_id = %s", (pid1,)).fetchone()
    assert f1["verificada_en"] is not None and f1["borrada_en"] is None

    # Descartar: las fotos solo existen en propuesta.fotos (JSONB); no se insertan en public.foto.
    pid2 = uuid.uuid4()
    ruta2 = archivo(bd, f"articulos/{pid2}/servo.jpg")
    with sesion_sel(bd, sel):
        rpc(bd, "propuesta_crear", p_id=pid2, p_tipo="ALTA",
            p_datos=Jsonb({"nombre": "Servo duplicado", "categoria": "FTC"}),
            p_cantidad=1, p_fotos=Jsonb([{"ruta": ruta2}]), p_nota=None)
    with como(bd, r, nivel="CONTRASENA"):
        rpc(bd, "propuesta_descartar", p_id=pid2, p_motivo="Ya está en el catálogo como A-0205")
    # No existe ninguna foto en la tabla con esa ruta: se descartó limpiamente.
    assert bd.execute("select count(*) from public.foto where url = %s", (ruta2,)).fetchone()["count"] == 0
    # La propuesta sí quedó como DESCARTADA.
    assert bd.execute("select estado from public.propuesta where id = %s", (pid2,)).fetchone()["estado"] == "DESCARTADA"


def test_cuenta_seleccion_crea_o_reutiliza_solicitante(lab):
    bd, r = lab["bd"], lab["r"]
    # 1. Crear cuenta SELECCION sin matrícula falla
    uid1 = uuid.uuid4()
    bd.execute("insert into auth.users (id, email) values (%s, %s)", (uid1, "uno@escuela.mx"))
    with pytest.raises(psycopg.Error, match="matrícula"), como_servidor(bd):
        rpc(bd, "cuenta_registrar", p_id=uid1, p_nombre="Alumno Uno", p_rol="SELECCION",
            p_correo="uno@escuela.mx", p_creada_por=r, p_matricula=None)

    # 2. Con matrícula nueva crea el solicitante tipo ALUMNO y lo vincula
    with como_servidor(bd):
        rpc(bd, "cuenta_registrar", p_id=uid1, p_nombre="Alumno Uno", p_rol="SELECCION",
            p_correo="uno@escuela.mx", p_creada_por=r, p_matricula="24-0001",
            p_nombre_alumno="Alumno Uno Completo", p_grupo="3-A")
    u1 = bd.execute("select solicitante_id from public.usuario where id = %s", (uid1,)).fetchone()
    assert u1["solicitante_id"] is not None
    s1 = bd.execute("select nombre_completo, tipo, matricula_o_clave from public.solicitante where id = %s",
                    (u1["solicitante_id"],)).fetchone()
    assert (s1["nombre_completo"], s1["tipo"], s1["matricula_o_clave"]) == ("Alumno Uno Completo", "ALUMNO", "24-0001")

    # 3. Si el alumno ya tenía ficha (porque pidió material antes sin cuenta), se reutiliza esa misma
    ficha_previa = insertar(bd, "solicitante", nombre_completo="Alumna Dos", tipo="ALUMNO",
                            matricula_o_clave="24-0002", grupo_area="3-B")
    uid2 = uuid.uuid4()
    bd.execute("insert into auth.users (id, email) values (%s, %s)", (uid2, "dos@escuela.mx"))
    with como_servidor(bd):
        rpc(bd, "cuenta_registrar", p_id=uid2, p_nombre="Alumna Dos", p_rol="SELECCION",
            p_correo="dos@escuela.mx", p_creada_por=r, p_matricula="24-0002")
    u2 = bd.execute("select solicitante_id from public.usuario where id = %s", (uid2,)).fetchone()
    assert u2["solicitante_id"] == ficha_previa

    # 4. Pero dos cuentas no pueden quedar pegadas a la misma ficha (error de dedo en la matrícula)
    uid3 = uuid.uuid4()
    bd.execute("insert into auth.users (id, email) values (%s, %s)", (uid3, "tres@escuela.mx"))
    with pytest.raises(psycopg.Error, match="Ya hay una cuenta"), como_servidor(bd):
        rpc(bd, "cuenta_registrar", p_id=uid3, p_nombre="Alumno Tres", p_rol="SELECCION",
            p_correo="tres@escuela.mx", p_creada_por=r, p_matricula="24-0002")


def test_seleccion_crea_solicitud_sesion(lab):
    bd, r, a = lab["bd"], lab["r"], lab["articulo"]
    # Crear alumno y usuario de selección vinculado
    sol_id = insertar(bd, "solicitante", nombre_completo="Carlos Robótica", tipo="ALUMNO", matricula_o_clave="24-0100")
    sel_user = usuario(bd, "SELECCION", "Carlos Selección", solicitante_id=sol_id)

    # Consulta su ficha
    with como(bd, sel_user, nivel="CONTRASENA"):
        ficha = bd.execute("select * from public.seleccion_mi_ficha()").fetchone()
    assert ficha["matricula"] == "24-0100" and ficha["impedimento"] is None

    # Crea solicitud desde su sesión
    sid = uuid.uuid4()
    lineas = Jsonb([{"articulo_id": str(a), "cantidad": 1}])
    with como(bd, sel_user, nivel="CONTRASENA"):
        res = rpc(bd, "solicitud_crear_sesion", p_id=sid, p_lineas=lineas, p_motivo="Competencia regional",
                  p_fecha_devolucion=None, p_nota="Práctica el fin de semana")
    assert res["folio"].startswith("LM-")

    # La solicitud nace confirmada en persona
    s = bd.execute("select estado, confirmada_como, confirmada_en, solicitante_id from public.solicitud where id = %s", (sid,)).fetchone()
    assert (s["estado"], s["confirmada_como"], s["solicitante_id"]) == ("PENDIENTE", "EN_PERSONA", sol_id)
    assert s["confirmada_en"] is not None

    # Avisó al responsable
    assert bd.execute("select count(*) from public.aviso where usuario_id = %s and ruta = '/solicitudes'", (r,)).fetchone()["count"] >= 1


def test_seleccion_ve_sus_solicitudes_y_puede_cancelar(lab):
    bd, a = lab["bd"], lab["articulo"]
    sol1 = insertar(bd, "solicitante", nombre_completo="Alumno Uno", tipo="ALUMNO", matricula_o_clave="24-0010")
    sol2 = insertar(bd, "solicitante", nombre_completo="Alumno Dos", tipo="ALUMNO", matricula_o_clave="24-0020")
    u1 = usuario(bd, "SELECCION", "User Uno", solicitante_id=sol1)
    u2 = usuario(bd, "SELECCION", "User Dos", solicitante_id=sol2)

    sid = uuid.uuid4()
    with como(bd, u1, nivel="CONTRASENA"):
        rpc(bd, "solicitud_crear_sesion", p_id=sid, p_lineas=Jsonb([{"articulo_id": str(a), "cantidad": 1}]),
            p_motivo="Taller", p_fecha_devolucion=None, p_nota=None)

    # u1 ve su solicitud
    with como(bd, u1, nivel="CONTRASENA"):
        mias1 = bd.execute("select * from public.mis_solicitudes_sesion()").fetchall()
    assert len(mias1) == 1 and mias1[0]["id"] == sid

    # u2 NO ve la solicitud de u1
    with como(bd, u2, nivel="CONTRASENA"):
        mias2 = bd.execute("select * from public.mis_solicitudes_sesion()").fetchall()
    assert len(mias2) == 0

    # u1 cancela su solicitud
    with como(bd, u1, nivel="CONTRASENA"):
        rpc(bd, "solicitud_cancelar_sesion", p_id=sid)
    assert bd.execute("select estado from public.solicitud where id = %s", (sid,)).fetchone()["estado"] == "CANCELADA"


def test_seleccion_con_adeudo_no_puede_solicitar(lab):
    bd, r, a = lab["bd"], lab["r"], lab["articulo"]
    sol_id = insertar(bd, "solicitante", nombre_completo="Deudor", tipo="ALUMNO", matricula_o_clave="24-9999")
    sel_user = usuario(bd, "SELECCION", "Deudor Selección", solicitante_id=sol_id)

    # Se le presta algo y vence hace 10 días
    p = mov(bd, a, "PRESTAMO", 1, r, responsable_solicitante_id=sol_id, fecha_compromiso="2026-01-01T15:00:00-06")

    # Al consultar su ficha, aparece el impedimento
    with como(bd, sel_user, nivel="CONTRASENA"):
        ficha = bd.execute("select * from public.seleccion_mi_ficha()").fetchone()
    assert "pendiente de devolver" in (ficha["impedimento"] or "")

    # Intentar solicitar falla
    sid = uuid.uuid4()
    with pytest.raises(psycopg.errors.RaiseException, match="No puedes pedir material.*pendiente de devolver"):
        with como(bd, sel_user, nivel="CONTRASENA"):
            rpc(bd, "solicitud_crear_sesion", p_id=sid, p_lineas=Jsonb([{"articulo_id": str(a), "cantidad": 1}]),
                p_motivo="Taller", p_fecha_devolucion=None, p_nota=None)



