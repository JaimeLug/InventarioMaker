"""Movimientos desde la app (Fase 3, migración 0006): préstamo, devolución, reportes, consumo,
reparación, ajuste de conteo, baja. Cada prueba entra con los permisos reales de la API y
revisa que las cifras de existencias queden bien.
"""
import uuid

import psycopg
import pytest
from psycopg.types.json import Jsonb

from ayudantes import archivo, como, existencias, insertar, mov, nueva_sesion, rpc, usuario
from test_acceso import confirmar, rechazo

DOMINIO = "prepasoficiales.net"


@pytest.fixture
def lab(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    s = usuario(bd, "SUBADMIN", "Sub Administración")
    d = usuario(bd, "DOCENTE", "Laura Gómez", pin="4826")
    d2 = usuario(bd, "DOCENTE", "Pedro Ruiz", pin="7302")
    multimetro = insertar(bd, "articulo", nombre="Multímetro Truper", categoria="HERRAMIENTAS", ubicacion="Gabinete 2")
    mov(bd, multimetro, "ALTA", 10, r)
    cinta = insertar(bd, "articulo", nombre="Cinta masking", categoria="CONSUMIBLES", es_consumible=True, unidad="rollo")
    mov(bd, cinta, "ALTA", 5, r)
    return dict(bd=bd, r=r, s=s, d=d, d2=d2, multimetro=multimetro, cinta=cinta)


def prestar(bd, yo, lineas, *, nivel="PIN", usuario_id=None, solicitante=None, fecha=None, comando=None, sesion=None):
    with como(bd, yo, nivel=nivel, sesion=sesion):
        return rpc(bd, "prestamo_registrar", p_lineas=Jsonb(lineas),
                   p_responsable_usuario=usuario_id if solicitante is None else None,
                   p_responsable_solicitante=solicitante, p_fecha_compromiso=fecha, p_nota=None, p_comando=comando)


def tabla(bd, yo, funcion, *args, nivel="CONTRASENA", sesion=None):
    marcas = ", ".join(["%s"] * len(args))
    with como(bd, yo, nivel=nivel, sesion=sesion):
        return bd.execute(f"select * from public.{funcion}({marcas})", args).fetchall()


def ficha_alumno(bd, yo, nombre="Juan Pérez Chan", matricula="23-0456"):
    with como(bd, yo, nivel="PIN"):
        return rpc(bd, "solicitante_crear_rapido", p_nombre=nombre, p_tipo="ALUMNO", p_matricula=matricula,
                   p_grupo="5°B", p_correo=f"juan.perez@{DOMINIO}", p_telefono=None)


def resolver(bd, yo, ids, decision, motivo=None):
    sesion = nueva_sesion(bd, yo)
    assert confirmar(bd, yo, sesion)["ok"]
    with como(bd, yo, sesion=sesion):
        return rpc(bd, "incidencia_resolver", p_ids=list(ids), p_decision=decision, p_motivo=motivo)


def cifras(bd, a, *campos):
    e = existencias(bd, a)
    return tuple(e[c] for c in campos)


# --- F-07 Préstamo directo ------------------------------------------------------
def test_prestamo_propio_vence_al_fin_de_la_jornada(lab):
    bd, d, a = lab["bd"], lab["d"], lab["multimetro"]
    r = prestar(bd, d, [{"articulo_id": str(a), "cantidad": 2}], usuario_id=d)
    fin = bd.execute("select app.fin_jornada() as f").fetchone()["f"]
    m = bd.execute("select * from movimiento where id = %s", (uuid.UUID(r["movimientos"][0]),)).fetchone()
    assert (m["fecha_compromiso"], m["autorizado_por"], m["responsable_usuario_id"]) == (fin, d, d)
    assert cifras(bd, a, "prestado", "disponible") == (2, 8)
    mios = tabla(bd, d, "mis_prestamos", nivel="PIN")
    assert [(p["codigo"], p["pendiente"], p["a_mi_nombre"]) for p in mios] == [("A-1001", 2, True)]


def test_varios_articulos_en_un_prestamo_sin_duplicar_al_reintentar(lab):
    bd, d = lab["bd"], lab["d"]
    lineas = [{"articulo_id": str(lab["multimetro"]), "cantidad": 1}, {"articulo_id": str(lab["cinta"]), "cantidad": 1}]
    comando = uuid.uuid4()
    primero = prestar(bd, d, lineas, usuario_id=d, comando=comando)
    segundo = prestar(bd, d, lineas, usuario_id=d, comando=comando)
    assert primero == segundo and len(primero["movimientos"]) == 2
    grupos = bd.execute("select distinct grupo from movimiento where tipo = 'PRESTAMO'").fetchall()
    assert [g["grupo"] for g in grupos] == [comando]


def test_prestamo_necesita_un_solo_responsable_y_disponibilidad(lab):
    bd, d, a = lab["bd"], lab["d"], lab["multimetro"]
    with rechazo("P0001", contiene="para quién"), como(bd, d, nivel="PIN"):
        rpc(bd, "prestamo_registrar", p_lineas=Jsonb([{"articulo_id": str(a), "cantidad": 1}]),
            p_responsable_usuario=None, p_responsable_solicitante=None, p_fecha_compromiso=None, p_nota=None, p_comando=None)
    with rechazo("P0001", contiene="Solo hay 10 disponibles"):
        prestar(bd, d, [{"articulo_id": str(a), "cantidad": 11}], usuario_id=d)
    with rechazo("P0001", contiene="dos veces"):
        prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}] * 2, usuario_id=d)


def test_ficha_rapida_de_alumno_y_prestamo_a_su_nombre(lab):
    bd, d, d2, a = lab["bd"], lab["d"], lab["d2"], lab["multimetro"]
    with rechazo("P0001", contiene=f"institucional (@{DOMINIO})"), como(bd, d, nivel="PIN"):
        rpc(bd, "solicitante_crear_rapido", p_nombre="Juan Pérez Chan", p_tipo="ALUMNO", p_matricula="23-0456",
            p_grupo="5°B", p_correo="juan@gmail.com", p_telefono=None)
    assert tabla(bd, d, "solicitante_buscar", "23-0456", nivel="PIN") == []

    juan = ficha_alumno(bd, d)
    encontrado = tabla(bd, d2, "solicitante_buscar", " 23-0456 ", nivel="PIN")
    assert [(f["nombre_completo"], f["verificada"], f["vencidos"]) for f in encontrado] == [("Juan Pérez Chan", True, 0)]
    with rechazo("P0001", contiene="Ya existe una ficha"):
        ficha_alumno(bd, d2)
    assert tabla(bd, d2, "solicitante_buscar", "23-045", nivel="PIN") == []     # solo matrícula exacta

    prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], solicitante=juan)
    abiertos = tabla(bd, d2, "prestamos_de_articulo", a, nivel="PIN")      # P-13: quien recibe ve el nombre
    assert [(p["a_cargo"], p["autorizo"]) for p in abiertos] == [("Juan Pérez Chan (Alumno, 5°B)", "Laura Gómez")]
    assert [p["a_mi_nombre"] for p in tabla(bd, d, "mis_prestamos", nivel="PIN")] == [False]

    bd.execute("update solicitante set bloqueo_manual = true, bloqueo_motivo = 'no devolvió una pinza' where id = %s", (juan,))
    with rechazo("P0001", contiene="no puede llevarse más material. Tiene un bloqueo: no devolvió una pinza"):
        prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], solicitante=juan)


def test_deshacer_un_prestamo_recien_hecho(lab):
    bd, d, d2, a = lab["bd"], lab["d"], lab["d2"], lab["multimetro"]
    r = prestar(bd, d, [{"articulo_id": str(a), "cantidad": 3}], usuario_id=d)
    with rechazo("PT403", "ROL"), como(bd, d2, nivel="PIN"):
        rpc(bd, "prestamo_deshacer", p_grupo=uuid.UUID(r["grupo"]))
    with como(bd, d, nivel="PIN"):
        assert rpc(bd, "prestamo_deshacer", p_grupo=uuid.UUID(r["grupo"])) == 1
    assert cifras(bd, a, "prestado", "disponible") == (0, 10)
    nota = bd.execute("select nota from movimiento where tipo = 'DEVOLUCION'").fetchone()["nota"]
    assert nota == "Deshecho por quien lo registró"

    bd.execute("update configuracion set valor = '0' where clave = 'ventana_deshacer_segundos'")
    r2 = prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], usuario_id=d)
    with rechazo("P0001", contiene="Ya pasó el tiempo"), como(bd, d, nivel="PIN"):
        rpc(bd, "prestamo_deshacer", p_grupo=uuid.UUID(r2["grupo"]))


def test_extender_un_prestamo(lab):
    bd, r, d, d2, a = lab["bd"], lab["r"], lab["d"], lab["d2"], lab["multimetro"]
    p = uuid.UUID(prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], usuario_id=d)["movimientos"][0])

    def extender(yo, dias, motivo="Proyecto del concurso", nivel="PIN"):
        with como(bd, yo, nivel=nivel):
            rpc(bd, "prestamo_extender", p_prestamo=p,
                p_fecha=bd.execute("select now() + make_interval(days => %s) as f", (dias,)).fetchone()["f"], p_motivo=motivo)

    extender(d, 3)
    with rechazo("P0001", contiene="debe ser después"):
        extender(d, 2)
    with rechazo("PT403", "ROL"):
        extender(d2, 5)
    extender(r, 5, "Lo necesita para la feria")
    with rechazo("P0001", contiene="a lo más 30 días"):
        extender(r, 40)
    vence = bd.execute("select vence_en > now() + interval '4 days' as ok from app.v_prestamos_abiertos").fetchone()
    assert vence["ok"]
    historial = tabla(bd, r, "historial_articulo", a)
    assert [h["tipo"] for h in historial if h["tipo"] == "EXTENSION"] == ["EXTENSION", "EXTENSION"]


# --- F-08 Devolución y F-09 confirmación ------------------------------------------
def test_devolucion_parcial_con_dano_y_faltante_perdido(lab):
    bd, r, d, d2, a = lab["bd"], lab["r"], lab["d"], lab["d2"], lab["multimetro"]
    juan = ficha_alumno(bd, d)
    p = prestar(bd, d, [{"articulo_id": str(a), "cantidad": 5}], solicitante=juan)["movimientos"][0]
    dano = uuid.uuid4()
    foto = archivo(bd, f"incidencias/{dano}/1.jpg", bucket="privado")

    with como(bd, d2, nivel="PIN"):
        res = rpc(bd, "devolucion_registrar", p_lineas=Jsonb([{
            "prestamo_id": p, "regresan": 3, "danadas": 1, "incidencia_dano_id": str(dano),
            "nota_dano": "La punta roja llegó quemada", "fotos_dano": [{"ruta": foto}],
            "faltante": "PERDIDO", "nota_perdida": "El alumno dice que se le perdieron en el camión",
            "sin_foto_perdida": "Se perdieron fuera de la escuela",
        }]), p_comando=None)
    assert res == {"devueltas": 3, "reportes": 2}
    assert cifras(bd, a, "existencia", "prestado", "retenido", "disponible") == (10, 2, 1, 7)

    revisar = tabla(bd, r, "por_revisar")
    assert sorted((i["tipo"], i["cantidad"], i["a_cargo"], i["reportada_por"]) for i in revisar) == [
        ("DANO", 1, "Juan Pérez Chan (Alumno, 5°B)", "Pedro Ruiz"),
        ("PERDIDA", 2, "Juan Pérez Chan (Alumno, 5°B)", "Pedro Ruiz")]
    assert [i["fotos"] for i in revisar if i["tipo"] == "DANO"] == [[foto]]

    assert resolver(bd, r, [i["id"] for i in revisar], "CONFIRMAR") == 2
    assert cifras(bd, a, "existencia", "prestado", "fuera_servicio", "retenido", "disponible") == (8, 0, 1, 0, 7)
    perdida = bd.execute("select * from movimiento where tipo = 'PERDIDA'").fetchone()
    assert (perdida["responsable_solicitante_id"], perdida["autorizado_por"], perdida["registrado_por"]) == (juan, r, d2)
    assert bd.execute("select count(*) as n from app.v_prestamos_abiertos").fetchone()["n"] == 0


def test_dano_sin_foto_ni_explicacion_se_rechaza(lab):
    bd, d, a = lab["bd"], lab["d"], lab["multimetro"]
    p = prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], usuario_id=d)["movimientos"][0]
    with rechazo("P0001", contiene="Agrega una foto"), como(bd, d, nivel="PIN"):
        rpc(bd, "devolucion_registrar", p_lineas=Jsonb([{"prestamo_id": p, "regresan": 1, "danadas": 1,
                                                          "nota_dano": "Se rompió la carcasa de plástico"}]), p_comando=None)
    assert cifras(bd, a, "prestado") == (1,)   # nada se aplicó


def test_reporte_en_el_taller_retiene_y_se_puede_descartar(lab):
    bd, r, d, a = lab["bd"], lab["r"], lab["d"], lab["multimetro"]
    rid = uuid.uuid4()
    foto = archivo(bd, f"incidencias/{rid}/1.jpg", bucket="privado")

    def reportar(cantidad, nota="Pantalla estrellada, no enciende", fotos=None):
        with como(bd, d, nivel="PIN"):
            return rpc(bd, "incidencia_reportar", p_id=rid, p_articulo=a, p_tipo="DANO", p_cantidad=cantidad,
                       p_prestamo=None, p_nota=nota, p_fotos=Jsonb(fotos if fotos is not None else [{"ruta": foto}]),
                       p_sin_foto=None)

    with rechazo("P0001", contiene="al menos 15"):
        reportar(1, nota="roto")
    with rechazo("P0001", contiene="Solo hay 10"):
        reportar(20)
    assert reportar(2) == rid
    assert reportar(2) == rid                       # reintento: no duplica
    assert cifras(bd, a, "retenido", "disponible") == (2, 8)

    with rechazo("P0001", contiene="por qué se descarta"):
        resolver(bd, r, [rid], "DESCARTAR")
    resolver(bd, r, [rid], "DESCARTAR", "Estaba sin pilas, funciona bien")
    assert cifras(bd, a, "retenido", "disponible", "fuera_servicio") == (0, 10, 0)
    with rechazo("P0001", contiene="ya fue resuelto"):
        resolver(bd, r, [rid], "CONFIRMAR")


def test_resolver_es_de_responsable_con_contrasena_reconfirmada(lab):
    bd, r, d, a = lab["bd"], lab["r"], lab["d"], lab["multimetro"]
    rid = uuid.uuid4()
    with como(bd, d, nivel="PIN"):
        rpc(bd, "incidencia_reportar", p_id=rid, p_articulo=a, p_tipo="PERDIDA", p_cantidad=1, p_prestamo=None,
            p_nota="No aparece en el gabinete desde el lunes", p_fotos=Jsonb([]), p_sin_foto="No hay nada que fotografiar")
    with rechazo("PT403", "ROL"), como(bd, d, nivel="PIN"):
        rpc(bd, "incidencia_resolver", p_ids=[rid], p_decision="CONFIRMAR", p_motivo=None)
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"), como(bd, r):
        rpc(bd, "incidencia_resolver", p_ids=[rid], p_decision="CONFIRMAR", p_motivo=None)
    resolver(bd, r, [rid], "CONFIRMAR")
    assert cifras(bd, a, "existencia", "disponible") == (9, 9)


# --- F-10 Consumo -------------------------------------------------------------------
def test_consumo_de_docente_espera_autorizacion_y_se_autoriza_en_lote(lab):
    bd, r, d, cinta = lab["bd"], lab["r"], lab["d"], lab["cinta"]
    with como(bd, d, nivel="PIN"):
        uno = rpc(bd, "consumo_registrar", p_articulo=cinta, p_cantidad=1, p_nota="Práctica de vinil 5°B", p_comando=None)
        dos = rpc(bd, "consumo_registrar", p_articulo=cinta, p_cantidad=1, p_nota=None, p_comando=None)
    assert (uno["aplicado"], dos["aplicado"]) == (False, False)
    assert cifras(bd, cinta, "existencia", "retenido", "disponible") == (5, 2, 3)

    with como(bd, r):
        assert rpc(bd, "consumo_registrar", p_articulo=cinta, p_cantidad=1, p_nota="Rotular cajas", p_comando=None)["aplicado"]
    with como(bd, r, nivel="PIN"):                                  # con PIN también espera autorización
        assert not rpc(bd, "consumo_registrar", p_articulo=cinta, p_cantidad=1, p_nota=None, p_comando=None)["aplicado"]
    assert cifras(bd, cinta, "existencia", "retenido") == (4, 3)

    consumos = [i["id"] for i in tabla(bd, r, "por_revisar") if i["tipo"] == "CONSUMO"]
    assert resolver(bd, r, consumos, "CONFIRMAR") == 3             # una sola contraseña para el lote
    assert cifras(bd, cinta, "existencia", "retenido", "disponible") == (1, 0, 1)
    with rechazo("P0001", contiene="Solo los consumibles"), como(bd, d, nivel="PIN"):
        rpc(bd, "consumo_registrar", p_articulo=lab["multimetro"], p_cantidad=1, p_nota=None, p_comando=None)


# --- Fotos privadas ---------------------------------------------------------------------
def test_quien_ve_las_fotos_privadas(lab):
    bd, r, d, d2, a = lab["bd"], lab["r"], lab["d"], lab["d2"], lab["multimetro"]
    rid = uuid.uuid4()
    ruta = f"incidencias/{rid}/1.jpg"
    with como(bd, d, nivel="PIN"):
        bd.execute("insert into storage.objects (bucket_id, name) values ('privado', %s)", (ruta,))
        rpc(bd, "incidencia_reportar", p_id=rid, p_articulo=a, p_tipo="DANO", p_cantidad=1, p_prestamo=None,
            p_nota="Cable pelado junto al conector", p_fotos=Jsonb([{"ruta": ruta}]), p_sin_foto=None)

    def ve(yo, nivel="CONTRASENA"):
        with como(bd, yo, nivel=nivel):
            return bd.execute("select count(*) as n from storage.objects where bucket_id = 'privado'").fetchone()["n"] == 1

    assert ve(d, "PIN")                  # quien reportó
    assert not ve(d2, "PIN")             # otro docente
    assert ve(r)                         # responsable con contraseña
    assert not ve(r, "PIN")              # responsable con PIN
    with como(bd):
        assert bd.execute("select count(*) as n from storage.objects where bucket_id = 'privado'").fetchone()["n"] == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege), como(bd, d, nivel="PIN"):
        bd.execute("insert into storage.objects (bucket_id, name) values ('privado', 'identificaciones/x.jpg')")
    assert tabla(bd, d, "mis_reportes", nivel="PIN")[0]["fotos"] == [ruta]


# --- Reparación, conteo y baja ----------------------------------------------------------------
def test_ajuste_de_conteo_verifica_y_resuelve_el_pendiente(lab):
    bd, r, d = lab["bd"], lab["r"], lab["d"]
    a = insertar(bd, "articulo", nombre="Destornilladores surtidos", categoria="HERRAMIENTAS", cantidad_estimada=True,
                 estado_inventario="POR_CONTAR", ubicacion="Cajón azul")
    mov(bd, a, "ALTA", 17, r)
    insertar(bd, "tarea_pendiente", articulo_id=a, tipo="CONTAR", descripcion="Contar", origen="IMPORTACION")
    prestar(bd, d, [{"articulo_id": str(a), "cantidad": 2}], usuario_id=d)

    def ajustar(en_taller, motivo="CONTEO_FISICO", nota=None, confirmada=True):
        sesion = nueva_sesion(bd, r)
        if confirmada:
            confirmar(bd, r, sesion)
        with como(bd, r, sesion=sesion):
            return rpc(bd, "ajuste_conteo", p_articulo=a, p_en_taller=en_taller, p_motivo=motivo, p_nota=nota)

    with rechazo("P0001", contiene="Explica la diferencia de -2"):
        ajustar(13)
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        ajustar(15, confirmada=False)
    assert ajustar(13, nota="Faltaban dos del juego rojo") == {"diferencia": -2, "estado": "POR_VERIFICAR"}
    art = bd.execute("select cantidad_estimada, estado_inventario from articulo where id = %s", (a,)).fetchone()
    assert (art["cantidad_estimada"], art["estado_inventario"]) == (False, "POR_VERIFICAR")    # sin foto no se verifica
    assert cifras(bd, a, "existencia", "prestado", "en_taller") == (15, 2, 13)
    assert bd.execute("select resuelta from tarea_pendiente where articulo_id = %s", (a,)).fetchone()["resuelta"]

    insertar(bd, "foto", articulo_id=a, url=archivo(bd, f"articulos/{a}/f.jpg"), es_principal=True)
    assert ajustar(13) == {"diferencia": 0, "estado": "VERIFICADO"}                           # mismo conteo: sin movimiento
    assert bd.execute("select count(*) as n from movimiento where tipo = 'AJUSTE_CONTEO'").fetchone()["n"] == 1


def test_reparacion(lab):
    bd, r, d, a = lab["bd"], lab["r"], lab["d"], lab["multimetro"]
    mov(bd, a, "DANO", 2, r)
    with rechazo("PT403", "ROL"), como(bd, d):
        rpc(bd, "reparacion_registrar", p_articulo=a, p_cantidad=1, p_nota=None)
    with como(bd, r):
        rpc(bd, "reparacion_registrar", p_articulo=a, p_cantidad=1, p_nota="Cambio de fusible")
    assert cifras(bd, a, "fuera_servicio", "disponible") == (1, 9)


def test_baja_total_parcial_oficio_y_reactivacion(lab):
    bd, r, d = lab["bd"], lab["r"], lab["d"]
    a = insertar(bd, "articulo", nombre="Impresora 3D Ender-3", categoria="HERRAMIENTAS_ELECTRICAS", num_resguardo="P13/0276")
    mov(bd, a, "ALTA", 3, r)
    mov(bd, a, "DANO", 1, r)

    def baja(cantidad=None, fuera=False, oficio=None, justificacion="Tarjeta madre quemada, sin refacción"):
        sesion = nueva_sesion(bd, r)
        confirmar(bd, r, sesion)
        with como(bd, r, sesion=sesion):
            return rpc(bd, "baja_registrar", p_articulo=a, p_cantidad=cantidad, p_de_fuera_de_servicio=fuera,
                       p_motivo="IRREPARABLE", p_justificacion=justificacion, p_oficio=oficio)

    assert baja(1, fuera=True) == {"total": False, "en_tramite": False}
    assert cifras(bd, a, "existencia", "fuera_servicio") == (2, 0)

    prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], usuario_id=d)
    with rechazo("P0001", contiene="Hay 1 prestados"):
        baja()
    p = bd.execute("select prestamo_id from app.v_prestamos_abiertos").fetchone()["prestamo_id"]
    with como(bd, d, nivel="PIN"):
        rpc(bd, "devolucion_registrar", p_lineas=Jsonb([{"prestamo_id": str(p), "regresan": 1}]), p_comando=None)

    assert baja() == {"total": True, "en_tramite": True}
    fila = bd.execute("select activo, estado_inventario, baja_en_tramite, existencia from v_inventario where id = %s", (a,)).fetchone()
    assert (fila["activo"], fila["estado_inventario"], fila["baja_en_tramite"], fila["existencia"]) == (False, "DADO_DE_BAJA", True, 0)
    with rechazo("P0001", contiene="dado de baja"):
        prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], usuario_id=d)

    with como(bd, r):
        rpc(bd, "baja_registrar_oficio", p_articulo=a, p_oficio="SA/123/2026")
    assert not bd.execute("select baja_en_tramite from v_inventario where id = %s", (a,)).fetchone()["baja_en_tramite"]

    sesion = nueva_sesion(bd, r)
    confirmar(bd, r, sesion)
    with como(bd, r, sesion=sesion):
        rpc(bd, "articulo_reactivar", p_articulo=a, p_cantidad=1, p_justificacion="Se consiguió la refacción en garantía")
    assert cifras(bd, a, "existencia", "disponible") == (1, 1)
    assert bd.execute("select activo from articulo where id = %s", (a,)).fetchone()["activo"]


# --- Lecturas con nombres y bitácora -----------------------------------------------------------
def test_vencidos_publicos_sin_nombres_y_listado_para_responsable(lab):
    bd, r, d, a = lab["bd"], lab["r"], lab["d"], lab["multimetro"]
    mov(bd, a, "PRESTAMO", 1, d, responsable_usuario_id=d, fecha_compromiso="2026-01-10")
    prestar(bd, d, [{"articulo_id": str(a), "cantidad": 1}], usuario_id=d)
    with como(bd):
        assert rpc(bd, "vencidos_contar") == 1
    listado = tabla(bd, r, "prestamos_abiertos_listar")
    assert [(p["vencido"], p["a_cargo"]) for p in listado] == [(True, "Laura Gómez"), (False, "Laura Gómez")]
    with rechazo("PT403", "ROL"):
        tabla(bd, d, "prestamos_abiertos_listar")
    with rechazo("PT403", "NIVEL_CONTRASENA"):
        tabla(bd, r, "historial_articulo", a, nivel="PIN")


def test_comentarios_en_un_reporte(lab):
    bd, r, d, d2, a = lab["bd"], lab["r"], lab["d"], lab["d2"], lab["multimetro"]
    rid = uuid.uuid4()
    with como(bd, d, nivel="PIN"):
        rpc(bd, "incidencia_reportar", p_id=rid, p_articulo=a, p_tipo="PERDIDA", p_cantidad=1, p_prestamo=None,
            p_nota="No lo encuentro en su lugar desde ayer", p_fotos=Jsonb([]), p_sin_foto="No hay nada que fotografiar")
    with como(bd, r):
        rpc(bd, "incidencia_comentar", p_incidencia=rid, p_texto="¿Revisaste el cajón de la mesa 3?")
    with como(bd, d, nivel="PIN"):
        rpc(bd, "incidencia_comentar", p_incidencia=rid, p_texto="Sí, ahí tampoco está")
    with rechazo("PT403", "ROL"), como(bd, d2, nivel="PIN"):
        rpc(bd, "incidencia_comentar", p_incidencia=rid, p_texto="Yo lo vi")
    comentarios = tabla(bd, d, "mis_reportes", nivel="PIN")[0]["comentarios"]
    assert [(c["autor"], c["texto"]) for c in comentarios] == [
        ("Jaime Lugo", "¿Revisaste el cajón de la mesa 3?"), ("Laura Gómez", "Sí, ahí tampoco está")]


def test_bitacora_solo_para_sub_administracion(lab):
    bd, r, s = lab["bd"], lab["r"], lab["s"]
    ficha_alumno(bd, lab["d"])
    eventos = tabla(bd, s, "bitacora_listar", None, 50)
    assert eventos[0]["evento"] == "SOLICITANTE_CREADO" and eventos[0]["usuario"] == "Laura Gómez"
    assert eventos[0]["referencia"] == "Juan Pérez Chan (Alumno, 5°B)"
    with rechazo("PT403", "ROL"):
        tabla(bd, r, "bitacora_listar", None, 50)


def test_la_jornada_termina_a_la_hora_configurada(bd):
    fila = bd.execute("""select app.fin_jornada() > now() as futuro,
                                to_char(app.fin_jornada() at time zone 'America/Merida', 'HH24:MI') as hora""").fetchone()
    assert (fila["futuro"], fila["hora"]) == (True, "15:00")
