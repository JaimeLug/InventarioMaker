"""Solicitudes sin cuenta (Fase 3b, migración 0007): envío público, confirmación por correo, aprobación,
código de entrega, entrega con identificación, adeudos, avisos, tareas periódicas y fotos de identificación.

Cada llamada entra con los permisos reales: visitante sin sesión (anon), la función del servidor
(service_role) o una cuenta con PIN o contraseña.
"""
import re
import uuid

import psycopg
import pytest
from psycopg.types.json import Jsonb

from ayudantes import archivo, como, como_servidor, existencias, insertar, mov, nueva_sesion, rpc, usuario
from test_acceso import confirmar, rechazo

DOMINIO = "prepasoficiales.net"
IP = "187.190.1.10"


@pytest.fixture
def lab(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    s = usuario(bd, "SUBADMIN", "Sub Administración")
    d = usuario(bd, "DOCENTE", "Laura Gómez", pin="4826")
    multimetro = insertar(bd, "articulo", nombre="Multímetro Truper", categoria="HERRAMIENTAS")
    mov(bd, multimetro, "ALTA", 5, r)
    cautin = insertar(bd, "articulo", nombre="Cautín Weller", categoria="HERRAMIENTAS")
    mov(bd, cautin, "ALTA", 2, r)
    cinta = insertar(bd, "articulo", nombre="Cinta masking", categoria="CONSUMIBLES", es_consumible=True)
    mov(bd, cinta, "ALTA", 5, r)
    return dict(bd=bd, r=r, s=s, d=d, multimetro=multimetro, cautin=cautin, cinta=cinta)


def datos(lineas, **extra):
    base = {"tipo": "ALUMNO", "matricula": "23-0456", "nombre": "Juan Pérez Chan", "grupo": "5°B",
            "correo": f"juan.perez@{DOMINIO}", "motivo": "Proyecto de clase", "detalle": "Robot seguidor",
            "lineas": [{"articulo_id": str(a), "cantidad": c} for a, c in lineas]}
    base.update(extra)
    return base


def enviar(bd, lineas, *, ip=IP, dispositivo="cel-juan", **extra):
    with como_servidor(bd):
        return rpc(bd, "solicitud_publica_enviar", p_datos=Jsonb(datos(lineas, **extra)), p_ip=ip, p_dispositivo=dispositivo)


def publico(bd, funcion, **params):
    with como(bd):
        return rpc(bd, funcion, **params)


def enlaces_de_correo(bd, correo=f"juan.perez@{DOMINIO}"):
    """Los enlaces que se mandaron por correo (el token va al final de la dirección)."""
    cuerpos = bd.execute("select cuerpo from envio where canal = 'CORREO' and destino = %s order by id", (correo,)).fetchall()
    return [t for c in cuerpos for t in re.findall(r"/s/([0-9a-f]{48})", c["cuerpo"])]


def admin(bd, yo, funcion, *, confirmada=False, **params):
    sesion = nueva_sesion(bd, yo)
    if confirmada:
        assert confirmar(bd, yo, sesion)["ok"]
    with como(bd, yo, sesion=sesion):
        return rpc(bd, funcion, **params)


def lista(bd, yo, funcion, *args):
    marcas = ", ".join(["%s"] * len(args))
    with como(bd, yo):
        return bd.execute(f"select * from public.{funcion}({marcas})", args).fetchall()


def id_de(bd, folio):
    return bd.execute("select id from solicitud where folio = %s", (folio,)).fetchone()["id"]


def solicitud_confirmada(lab, lineas=None, **extra):
    bd = lab["bd"]
    r = enviar(bd, lineas or [(lab["multimetro"], 2)], **extra)
    publico(bd, "solicitud_publica_confirmar", p_token=enlaces_de_correo(bd, extra.get("correo", f"juan.perez@{DOMINIO}"))[-1])
    return r["token"], id_de(bd, r["folio"])


def aprobar(lab, sid, lineas=None, **extra):
    bd = lab["bd"]
    lineas = lineas if lineas is not None else [{"articulo_id": str(l["articulo_id"]), "cantidad": l["cantidad"]}
                        for l in bd.execute("select * from solicitud_linea where solicitud_id = %s", (sid,)).fetchall()]
    return admin(bd, lab["r"], "solicitud_aprobar", p_id=sid, p_lineas=Jsonb(lineas), p_fecha=extra.get("fecha"),
                 p_nota=extra.get("nota"), p_vigencia=extra.get("vigencia", "RATO"))


def entregar(lab, sid, *, fotos=True):
    bd = lab["bd"]
    ident = archivo(bd, f"identificaciones/{sid}/credencial.jpg", "privado") if fotos else None
    material = archivo(bd, f"entregas/{sid}/material.jpg", "privado")
    return admin(bd, lab["r"], "solicitud_entregar", p_id=sid, p_tipo_identificacion="TRANSPORTE",
                 p_foto_identificacion=ident, p_fotos_material=Jsonb([{"ruta": material}]), p_fecha_devolucion=None)


def hasta_entregada(lab, lineas=None):
    bd = lab["bd"]
    token, sid = solicitud_confirmada(lab, lineas)
    codigo = aprobar(lab, sid)["codigo"]
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=codigo)["ok"]
    entregar(lab, sid)
    return token, sid


# --- F-04 Envío público ----------------------------------------------------------
def test_alumno_nuevo_pide_y_le_llega_el_enlace_para_confirmar(lab):
    bd = lab["bd"]
    r = enviar(bd, [(lab["multimetro"], 2), (lab["cautin"], 1)])
    assert r["folio"].startswith("LM-") and len(r["token"]) == 48
    assert (r["reconocido"], r["iniciales"], r["correo"]) == (False, "J. P. C.", f"j***@{DOMINIO}")

    s = bd.execute("select * from solicitud where folio = %s", (r["folio"],)).fetchone()
    assert (s["estado"], s["confirmada_en"], s["motivo"]) == ("PENDIENTE", None, "Proyecto de clase: Robot seguidor")
    ficha = bd.execute("select * from solicitante where id = %s", (s["solicitante_id"],)).fetchone()
    assert (ficha["verificada_en"], ficha["correo_confirmado_en"]) == (None, None)     # nace sin verificar (F-04b)
    assert existencias(bd, lab["multimetro"])["apartado"] == 0                          # pedir no aparta

    correo = bd.execute("select * from envio where canal = 'CORREO'").fetchone()
    assert correo["destino"] == f"juan.perez@{DOMINIO}" and "Confirma tu solicitud" in correo["asunto"]
    assert "2 × Multímetro Truper" in correo["cuerpo"] and "No fui yo" in correo["cuerpo"]
    assert bd.execute("select ip_hash from solicitud").fetchone()["ip_hash"] != IP      # la red no se guarda legible

    # Sin confirmar, no llega a la bandeja.
    assert lista(bd, lab["r"], "solicitudes_listar", "POR_REVISAR") == []
    assert [x["folio"] for x in lista(bd, lab["r"], "solicitudes_listar", "SIN_CONFIRMAR")] == [r["folio"]]


def test_validaciones_del_formulario_publico(lab):
    bd, m = lab["bd"], lab["multimetro"]
    with rechazo("P0001", contiene="correo institucional"):
        enviar(bd, [(m, 1)], correo="juan@gmail.com")
    with rechazo("P0001", contiene="nombre completo"):
        enviar(bd, [(m, 1)], nombre="Juan")
    with rechazo("P0001", contiene="quedan 5"):
        enviar(bd, [(m, 6)])
    with rechazo("P0001", contiene="consumible"):
        enviar(bd, [(lab["cinta"], 1)])
    with rechazo("P0001", contiene="a lo más en 14 días"):
        enviar(bd, [(m, 1)], fecha="2099-01-01")
    with rechazo("P0001", contiene="Cuéntanos"):
        enviar(bd, [(m, 1)], motivo="Otro", detalle="")
    with rechazo("P0001", contiene="quién eres"):
        enviar(bd, [(m, 1)], tipo="OTRO", correo="visita@gmail.com")
    # Un maestro no necesita correo institucional y puede pedir hasta 30 días.
    fecha = bd.execute("select (app.hoy() + 25)::text as f").fetchone()["f"]
    assert enviar(bd, [(m, 1)], tipo="MAESTRO", matricula="E-201", nombre="Mario Canul Pech", correo="mario@gmail.com", fecha=fecha)
    assert bd.execute("select count(*) as n from solicitud").fetchone()["n"] == 1


def test_sin_permiso_directo_desde_la_api(lab):
    bd = lab["bd"]
    with rechazo("42501"), como(bd):
        rpc(bd, "solicitud_publica_enviar", p_datos=Jsonb(datos([(lab["multimetro"], 1)])), p_ip=IP, p_dispositivo="x")
    with rechazo("42501"), como(bd):
        bd.execute("select * from solicitud")
    with rechazo("42501"), como(bd, lab["d"], nivel="PIN"):
        bd.execute("select * from envio")
    assert publico(bd, "solicitud_publica_estado", p_token="no-existe") is None


def test_freno_por_dispositivo_y_por_red(lab):
    bd, m = lab["bd"], lab["multimetro"]
    for i in range(5):
        enviar(bd, [(m, 1)], matricula=f"23-10{i}", correo=f"a{i}@{DOMINIO}")
    with rechazo("P0001", contiene="demasiadas solicitudes"):
        enviar(bd, [(m, 1)], matricula="23-199", correo=f"z@{DOMINIO}")
    # Otro celular en la misma red de la escuela sí puede (el límite de red es más alto).
    assert enviar(bd, [(m, 1)], matricula="23-199", correo=f"z@{DOMINIO}", dispositivo="otro-cel")
    bd.execute("update configuracion set valor = '6' where clave = 'solicitudes_por_hora_red'")
    with rechazo("P0001", contiene="demasiadas solicitudes"):
        enviar(bd, [(m, 1)], matricula="23-200", correo=f"y@{DOMINIO}", dispositivo="tercer-cel")


def test_una_solicitud_en_curso_por_persona(lab):
    bd, m = lab["bd"], lab["multimetro"]
    primera = enviar(bd, [(m, 1)])
    # Sin confirmar: la nueva la reemplaza.
    segunda = enviar(bd, [(m, 2)])
    estados = {x["folio"]: (x["estado"], x["motivo_cancelacion"]) for x in bd.execute("select * from solicitud").fetchall()}
    assert estados[primera["folio"]] == ("CANCELADA", "Reemplazada por una solicitud nueva")
    publico(bd, "solicitud_publica_confirmar", p_token=enlaces_de_correo(bd)[-1])
    with rechazo("P0001", contiene=f"Ya tienes la solicitud {segunda['folio']} en curso"):
        enviar(bd, [(m, 1)])


# --- Confirmación, "no fui yo", cancelación ---------------------------------------
def test_confirmar_desde_el_correo_avisa_al_responsable(lab):
    bd = lab["bd"]
    celular = "fcm-token-del-celular-del-responsable-0001"
    admin(bd, lab["r"], "dispositivo_registrar", p_token=celular, p_plataforma="android")
    r = enviar(bd, [(lab["multimetro"], 2)])

    antes = publico(bd, "solicitud_publica_estado", p_token=r["token"])
    assert (antes["confirmada"], antes["enlace_de_correo"], antes["solicitante"]["nombre"]) == (False, False, "J. P. C.")
    with rechazo("P0001", contiene="Usa el que llegó a tu correo"):
        publico(bd, "solicitud_publica_confirmar", p_token=r["token"])      # el enlace del celular no confirma

    despues = publico(bd, "solicitud_publica_confirmar", p_token=enlaces_de_correo(bd)[0])
    assert (despues["confirmada"], despues["solicitante"]["nombre"]) == (True, "Juan Pérez Chan")
    assert publico(bd, "solicitud_publica_confirmar", p_token=enlaces_de_correo(bd)[0])["confirmada"]     # repetir no pasa nada

    avisos = lista(bd, lab["r"], "avisos_listar")
    assert [(a["titulo"], a["leido"]) for a in avisos] == [(f"Nueva solicitud {r['folio']}", False)]
    assert admin(bd, lab["r"], "avisos_sin_leer") == 1
    assert lista(bd, lab["s"], "avisos_listar") == []                        # sub administración no recibe cada solicitud
    push = bd.execute("select * from envio where canal = 'PUSH'").fetchone()
    assert push["destino"] == celular and "Juan" not in push["asunto"] + push["cuerpo"]    # sin nombres de alumnos
    admin(bd, lab["r"], "avisos_marcar_leidos")
    assert admin(bd, lab["r"], "avisos_sin_leer") == 0
    assert [x["folio"] for x in lista(bd, lab["r"], "solicitudes_listar", "POR_REVISAR")] == [r["folio"]]


def test_no_fui_yo_cancela_y_alerta(lab):
    bd = lab["bd"]
    r = enviar(bd, [(lab["multimetro"], 1)])
    with rechazo("P0001", contiene="Usa el enlace que llegó a tu correo"):
        publico(bd, "solicitud_publica_no_fui_yo", p_token=r["token"])
    estado = publico(bd, "solicitud_publica_no_fui_yo", p_token=enlaces_de_correo(bd)[0])
    assert (estado["estado"], estado["motivo_cancelacion"]) == ("CANCELADA", "El dueño del correo dijo que no la pidió")
    assert [a["titulo"] for a in lista(bd, lab["r"], "avisos_listar")] == [f"Alerta en {r['folio']}"]


def test_el_solicitante_cancela_y_se_libera_lo_apartado(lab):
    bd = lab["bd"]
    token, sid = solicitud_confirmada(lab)
    aprobar(lab, sid)
    assert existencias(bd, lab["multimetro"])["apartado"] == 2
    estado = publico(bd, "solicitud_publica_cancelar", p_token=token)
    assert estado["estado"] == "CANCELADA" and existencias(bd, lab["multimetro"])["apartado"] == 0
    assert bd.execute("select estado from codigo_entrega").fetchone()["estado"] == "ANULADO"


def test_matricula_ya_comprobada_no_se_cambia_desde_lo_publico(lab):
    bd, m = lab["bd"], lab["multimetro"]
    token, sid = hasta_entregada(lab, [(m, 1)])
    mov_id = bd.execute("select id from movimiento where solicitud_id = %s", (sid,)).fetchone()["id"]
    admin(bd, lab["r"], "devolucion_registrar", p_lineas=Jsonb([{"prestamo_id": str(mov_id), "regresan": 1}]), p_comando=None)

    # Alguien teclea la misma matrícula con su propio correo.
    r = enviar(bd, [(m, 1)], nombre="Otra Persona Distinta", correo=f"intruso@{DOMINIO}", dispositivo="cel-intruso")
    assert (r["reconocido"], r["iniciales"], r["correo"]) == (True, "J. P. C.", f"j***@{DOMINIO}")
    ficha = bd.execute("select * from solicitante where matricula_o_clave = '23-0456' and not posible_duplicado").fetchone()
    assert (ficha["nombre_completo"], ficha["correo"]) == ("Juan Pérez Chan", f"juan.perez@{DOMINIO}")
    assert enlaces_de_correo(bd, f"intruso@{DOMINIO}") == []                  # el enlace fue al correo verdadero

    # Si insiste en que ese no es su correo, queda como posible duplicado para revisar en persona.
    r2 = enviar(bd, [(m, 1)], nombre="Otra Persona Distinta", correo=f"intruso@{DOMINIO}", dispositivo="cel-intruso", otro_correo=True)
    assert r2["reconocido"] and r2["correo"] == f"i***@{DOMINIO}"
    publico(bd, "solicitud_publica_confirmar", p_token=enlaces_de_correo(bd, f"intruso@{DOMINIO}")[-1])
    fila = [x for x in lista(bd, lab["r"], "solicitudes_listar", "POR_REVISAR") if x["folio"] == r2["folio"]][0]
    assert fila["posible_duplicado"] and "Posible duplicado" in fila["alerta"]


def test_ficha_nunca_comprobada_toma_los_datos_nuevos(lab):
    bd, m = lab["bd"], lab["multimetro"]
    enviar(bd, [(m, 1)], nombre="Nombre Mal Escrito", correo=f"mal@{DOMINIO}")
    r = enviar(bd, [(m, 1)], dispositivo="otro")
    assert not r["reconocido"]
    assert bd.execute("select count(*) as n from solicitante").fetchone()["n"] == 1
    assert bd.execute("select correo from solicitante").fetchone()["correo"] == f"juan.perez@{DOMINIO}"


def test_recuperar_enlace_responde_igual_exista_o_no(lab):
    bd = lab["bd"]
    r = enviar(bd, [(lab["multimetro"], 1)])
    antes = len(enlaces_de_correo(bd))
    with como_servidor(bd):
        rpc(bd, "solicitud_publica_recuperar", p_folio=r["folio"], p_matricula="99-9999", p_ip=IP, p_dispositivo="x")
        rpc(bd, "solicitud_publica_recuperar", p_folio=r["folio"].lower(), p_matricula="23-0456", p_ip=IP, p_dispositivo="x")
    assert len(enlaces_de_correo(bd)) == antes + 1


# --- F-06 Aprobar, rechazar -------------------------------------------------------
def test_aprobar_parcial_pide_nota_y_aparta(lab):
    bd, m, c = lab["bd"], lab["multimetro"], lab["cautin"]
    token, sid = solicitud_confirmada(lab, [(m, 3), (c, 1)])
    with rechazo("PT403", "ROL"), como(bd, lab["d"], nivel="CONTRASENA"):
        rpc(bd, "solicitud_detalle", p_id=sid)
    with rechazo("PT403", "NIVEL_CONTRASENA"), como(bd, lab["r"], nivel="PIN"):
        rpc(bd, "solicitud_detalle", p_id=sid)

    detalle = admin(bd, lab["r"], "solicitud_detalle", p_id=sid)
    assert detalle["solicitante"]["correo_confirmado"] and detalle["solicitante"]["verificada_en"] is None
    assert [(l["nombre"], l["cantidad"], l["disponible"]) for l in detalle["lineas"]] == [("Cautín Weller", 1, 2), ("Multímetro Truper", 3, 5)]

    parcial = [{"articulo_id": str(m), "cantidad": 2}]
    with rechazo("P0001", contiene="escribe una nota"):
        aprobar(lab, sid, parcial)
    r = aprobar(lab, sid, parcial, nota="Solo hay 2 multímetros para alumnos esta semana", vigencia="HOY")
    assert re.fullmatch(r"\d{6}", r["codigo"])
    assert (existencias(bd, m)["apartado"], existencias(bd, m)["disponible"], existencias(bd, c)["apartado"]) == (2, 3, 0)

    estado = publico(bd, "solicitud_publica_estado", p_token=token)
    assert (estado["estado"], estado["nota_aprobacion"], estado["autorizo"]) == ("APROBADA", "Solo hay 2 multímetros para alumnos esta semana", "Jaime Lugo")
    assert "codigo" not in estado                                        # el código nunca se le manda al alumno
    correo = bd.execute("select cuerpo from envio where asunto like 'Solicitud aprobada%'").fetchone()["cuerpo"]
    assert r["codigo"] not in correo and "identificación con foto" in correo
    with rechazo("P0001", contiene="ya fue aprobada (por Jaime Lugo)"):
        aprobar(lab, sid, parcial, nota="otra vez")


def test_no_se_aprueba_mas_de_lo_disponible(lab):
    bd, c = lab["bd"], lab["cautin"]
    _, sid = solicitud_confirmada(lab, [(c, 2)])
    mov(bd, c, "PRESTAMO", 1, lab["r"])
    with rechazo("P0001", contiene="Solo hay 1 disponibles"):
        aprobar(lab, sid)
    with rechazo("P0001", contiene="No aprobaste ningún artículo"):
        aprobar(lab, sid, [], nota="nada")


def test_rechazar_con_motivo(lab):
    bd = lab["bd"]
    token, sid = solicitud_confirmada(lab)
    with rechazo("P0001", contiene="Explica"):
        admin(bd, lab["r"], "solicitud_rechazar", p_id=sid, p_motivo="Otro", p_detalle=None)
    admin(bd, lab["r"], "solicitud_rechazar", p_id=sid, p_motivo="Uso no justificado", p_detalle="Pide el de física")
    estado = publico(bd, "solicitud_publica_estado", p_token=token)
    assert (estado["estado"], estado["motivo_rechazo"]) == ("RECHAZADA", "Uso no justificado: Pide el de física")


def test_bloqueado_por_vencido_no_pide_ni_se_aprueba_hasta_desbloquear(lab):
    bd, m = lab["bd"], lab["multimetro"]
    _, sid = hasta_entregada(lab, [(m, 1)])
    # Los movimientos no se editan: para simular que pasó el tiempo se apaga la protección solo en la prueba.
    bd.execute("alter table movimiento disable trigger solo_agregar")
    bd.execute("update movimiento set fecha_compromiso = now() - interval '1 day' where solicitud_id = %s", (sid,))
    bd.execute("alter table movimiento enable trigger solo_agregar")
    bd.execute("select app.tareas_periodicas()")
    assert bd.execute("select estado from solicitud where id = %s", (sid,)).fetchone()["estado"] == "VENCIDA"
    ficha = bd.execute("select * from solicitante").fetchone()
    assert ficha["bloqueado"]

    with rechazo("P0001", contiene="Tiene material pendiente de devolver"):
        enviar(bd, [(m, 1)], dispositivo="otro")
    adeudos = lista(bd, lab["r"], "adeudos_listar")
    assert [(a["nombre"], a["piezas"], a["vencidos"], a["bloqueado"]) for a in adeudos] == [("Juan Pérez Chan", 1, 1, True)]

    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        admin(bd, lab["r"], "solicitante_desbloquear", p_id=ficha["id"], p_motivo="Lo devuelve mañana, lo necesita hoy")
    admin(bd, lab["r"], "solicitante_desbloquear", confirmada=True, p_id=ficha["id"], p_motivo="Lo devuelve mañana, lo necesita hoy")
    assert enviar(bd, [(m, 1)], dispositivo="otro")["reconocido"]


# --- Código de entrega -------------------------------------------------------------
def test_codigo_incorrecto_se_bloquea_a_los_5_intentos(lab):
    bd = lab["bd"]
    token, sid = solicitud_confirmada(lab)
    codigo = aprobar(lab, sid)["codigo"]
    malo = "000000" if codigo != "000000" else "111111"
    for restantes in (4, 3, 2, 1):
        assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=malo)["restantes"] == restantes
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=malo)["motivo"] == "BLOQUEADO"
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=codigo)["motivo"] == "BLOQUEADO"

    nuevo = admin(bd, lab["r"], "solicitud_codigo_nuevo", p_id=sid, p_vigencia="RATO")["codigo"]
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=nuevo)["ok"]
    estados = [c["estado"] for c in bd.execute("select estado from codigo_entrega order by generado_en").fetchall()]
    assert estados == ["BLOQUEADO", "USADO"]


def test_codigo_vencido_y_nuevo_anula_el_anterior(lab):
    bd = lab["bd"]
    token, sid = solicitud_confirmada(lab)
    primero = aprobar(lab, sid)["codigo"]
    segundo = admin(bd, lab["r"], "solicitud_codigo_nuevo", p_id=sid, p_vigencia="MANANA")["codigo"]
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=primero)["ok"] is (primero == segundo)
    bd.execute("update codigo_entrega set generado_en = generado_en - interval '1 day'")
    bd.execute("update codigo_entrega set expira_en = now() - interval '1 minute' where estado = 'VIGENTE'")
    r = publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=segundo)
    assert (r["ok"], r["motivo"]) == (False, "EXPIRADO")
    assert sorted(c["estado"] for c in bd.execute("select estado from codigo_entrega").fetchall()) == ["ANULADO", "EXPIRADO"]


def test_canje_en_el_dispositivo_del_laboratorio_pide_matricula(lab):
    bd = lab["bd"]
    _, sid = solicitud_confirmada(lab)
    codigo = aprobar(lab, sid)["codigo"]
    assert admin(bd, lab["r"], "solicitud_canjear_en_laboratorio", p_id=sid, p_matricula="23-9999", p_codigo=codigo)["motivo"] == "MATRICULA"
    assert admin(bd, lab["r"], "solicitud_canjear_en_laboratorio", p_id=sid, p_matricula="23-0456", p_codigo=codigo)["ok"]


# --- Entrega --------------------------------------------------------------------
def test_entrega_crea_los_prestamos_a_nombre_del_alumno(lab):
    bd, m, c = lab["bd"], lab["multimetro"], lab["cautin"]
    token, sid = solicitud_confirmada(lab, [(m, 2), (c, 1)])
    codigo = aprobar(lab, sid)["codigo"]

    with rechazo("P0001", contiene="Falta que el solicitante escriba el código"):
        entregar(lab, sid)
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=codigo)["ok"]
    assert publico(bd, "solicitud_publica_estado", p_token=token)["codigo_aceptado"]
    assert bd.execute("select count(*) as n from movimiento where tipo = 'PRESTAMO'").fetchone()["n"] == 0   # canjear no presta
    with rechazo("P0001", contiene="Falta la foto de la identificación"):
        entregar(lab, sid, fotos=False)

    # Un docente no entrega solicitudes ni sube identificaciones.
    with como(bd, lab["d"], nivel="PIN"):
        assert not bd.execute("select app.puede_subir_privado(%s) as p", (f"identificaciones/{sid}/x.jpg",)).fetchone()["p"]

    # La aprobó Jaime; la entrega Sub Administración.
    ident = archivo(bd, f"identificaciones/{sid}/credencial.jpg", "privado")
    material = archivo(bd, f"entregas/{sid}/material.jpg", "privado")
    r = admin(bd, lab["s"], "solicitud_entregar", p_id=sid, p_tipo_identificacion="TRANSPORTE", p_foto_identificacion=ident,
              p_fotos_material=Jsonb([{"ruta": material}]), p_fecha_devolucion=None)
    assert (r["prestamos"], r["a_cargo"]) == (2, "Juan Pérez Chan")

    prestamos = bd.execute("select * from movimiento where tipo = 'PRESTAMO' order by cantidad").fetchall()
    ficha = bd.execute("select * from solicitante").fetchone()
    assert {(p["autorizado_por"], p["registrado_por"], p["responsable_solicitante_id"], p["solicitud_id"], p["origen"]) for p in prestamos} \
        == {(lab["r"], lab["s"], ficha["id"], sid, "SOLICITUD")}
    assert (ficha["verificada_por"], ficha["verificada_en"] is not None) == (lab["s"], True)
    assert (existencias(bd, m)["prestado"], existencias(bd, m)["apartado"]) == (2, 0)

    estado = publico(bd, "solicitud_publica_estado", p_token=token)
    assert (estado["estado"], estado["autorizo"], [l["pendiente"] for l in estado["lineas"]]) == ("ENTREGADO", "Jaime Lugo", [1, 2])
    assert bd.execute("select count(*) as n from envio where asunto like 'Material entregado%'").fetchone()["n"] == 1

    # Devolver todo la cierra como DEVUELTA.
    for p in prestamos:
        admin(bd, lab["d"], "devolucion_registrar", p_lineas=Jsonb([{"prestamo_id": str(p["id"]), "regresan": p["cantidad"]}]), p_comando=None)
    assert bd.execute("select estado from solicitud where id = %s", (sid,)).fetchone()["estado"] == "DEVUELTA"


def test_perdida_confirmada_tambien_cierra_la_solicitud(lab):
    bd, m = lab["bd"], lab["multimetro"]
    _, sid = hasta_entregada(lab, [(m, 2)])
    p = bd.execute("select id from movimiento where solicitud_id = %s", (sid,)).fetchone()["id"]
    inc = uuid.uuid4()
    admin(bd, lab["d"], "devolucion_registrar", p_comando=None, p_lineas=Jsonb([{
        "prestamo_id": str(p), "regresan": 1, "faltante": "PERDIDO", "incidencia_perdida_id": str(inc),
        "nota_perdida": "Dice que lo dejó en el camión", "fotos_perdida": [], "sin_foto_perdida": "No hay nada que fotografiar"}]))
    assert bd.execute("select estado from solicitud where id = %s", (sid,)).fetchone()["estado"] == "ENTREGADO"
    admin(bd, lab["r"], "incidencia_resolver", confirmada=True, p_ids=[inc], p_decision="CONFIRMAR", p_motivo=None)
    assert bd.execute("select estado from solicitud where id = %s", (sid,)).fetchone()["estado"] == "DEVUELTA"
    exp = admin(bd, lab["r"], "persona_expediente", p_tipo="SOLICITANTE",
                p_id=bd.execute("select id from solicitante").fetchone()["id"])
    assert [(i["tipo"], i["estado"]) for i in exp["incidencias"]] == [("PERDIDA", "CONFIRMADA")]


def test_anular_entrega_sin_identificacion(lab):
    bd = lab["bd"]
    token, sid = solicitud_confirmada(lab)
    codigo = aprobar(lab, sid)["codigo"]
    publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=codigo)
    admin(bd, lab["r"], "solicitud_entrega_anular", p_id=sid, p_motivo="No trae identificación con foto")
    with rechazo("P0001", contiene="Falta que el solicitante escriba el código"):
        entregar(lab, sid)
    assert existencias(bd, lab["multimetro"])["apartado"] == 2      # sigue apartado
    nuevo = admin(bd, lab["r"], "solicitud_codigo_nuevo", p_id=sid, p_vigencia="RATO")["codigo"]
    assert publico(bd, "solicitud_publica_canjear", p_token=token, p_codigo=nuevo)["ok"]
    entregar(lab, sid)


# --- Fotos de identificación ----------------------------------------------------------
def test_la_identificacion_solo_se_ve_tras_registrarlo(lab):
    bd = lab["bd"]
    _, sid = hasta_entregada(lab)
    ruta = f"identificaciones/{sid}/credencial.jpg"

    def puede(yo, nivel="CONTRASENA", sesion=None):
        with como(bd, yo, nivel=nivel, sesion=sesion):
            return bd.execute("select app.puede_ver_privado(%s) as p", (ruta,)).fetchone()["p"]

    assert not puede(lab["r"])                                     # sin pedirla primero, ni el responsable
    assert not puede(lab["d"], "PIN")
    sesion = nueva_sesion(bd, lab["r"])
    with como(bd, lab["r"], sesion=sesion):
        assert rpc(bd, "identificacion_ver", p_solicitud=sid) == [ruta]
    assert puede(lab["r"])
    assert not puede(lab["s"])                                     # cada persona deja su propio registro
    with rechazo("PT403", "ROL"), como(bd, lab["d"]):
        rpc(bd, "identificacion_ver", p_solicitud=sid)
    vistas = bd.execute("select usuario_id from bitacora where evento = 'IDENTIFICACION_VISTA'").fetchall()
    assert [v["usuario_id"] for v in vistas] == [lab["r"]]
    assert puede(lab["r"], sesion=sesion) and not puede(lab["r"], nivel="PIN")


def test_identificaciones_se_borran_al_fin_de_ciclo_si_no_debe_nada(lab):
    bd, m = lab["bd"], lab["multimetro"]
    _, sid = hasta_entregada(lab, [(m, 1)])
    huerfana = archivo(bd, "identificaciones/00000000-0000-0000-0000-000000000000/abandonada.jpg", "privado")
    bd.execute("update storage.objects set created_at = now() - interval '2 days' where name = %s", (huerfana,))

    def por_borrar():
        with como_servidor(bd):
            return sorted(r["ruta"] for r in bd.execute("select * from public.identificaciones_por_borrar(50)").fetchall())

    assert por_borrar() == [huerfana]                              # la de la entrega sigue: el ciclo no ha terminado
    bd.execute("update configuracion set valor = to_jsonb((app.hoy() - 1)::text) where clave = 'fin_ciclo_escolar'")
    bd.execute("update foto set tomada_en = now() - interval '3 days' where url like 'identificaciones/%%'")
    assert por_borrar() == [huerfana]                              # todavía debe el multímetro
    p = bd.execute("select id from movimiento where solicitud_id = %s", (sid,)).fetchone()["id"]
    admin(bd, lab["d"], "devolucion_registrar", p_lineas=Jsonb([{"prestamo_id": str(p), "regresan": 1}]), p_comando=None)
    rutas = por_borrar()
    assert rutas == sorted([huerfana, f"identificaciones/{sid}/credencial.jpg"])

    with como_servidor(bd):
        rpc(bd, "identificaciones_borradas", p_rutas=rutas)
    foto = bd.execute("select * from foto where url like 'identificaciones/%%'").fetchone()
    assert foto["borrada_en"] is not None                          # el registro se queda
    assert bd.execute("select count(*) as n from bitacora where evento = 'IDENTIFICACION_BORRADA'").fetchone()["n"] == 2
    detalle = admin(bd, lab["r"], "solicitud_detalle", p_id=sid)
    assert detalle["identificacion_borrada"]


# --- Tareas periódicas -----------------------------------------------------------
def test_cancelaciones_automaticas(lab):
    bd, m = lab["bd"], lab["multimetro"]
    sin_confirmar = enviar(bd, [(m, 1)])
    _, sin_respuesta = solicitud_confirmada(lab, matricula="23-0001", correo=f"a1@{DOMINIO}", dispositivo="d1")
    _, sin_recoger = solicitud_confirmada(lab, matricula="23-0002", correo=f"a2@{DOMINIO}", dispositivo="d2")
    aprobar(lab, sin_recoger)

    bd.execute("update solicitud set creada_en = now() - interval '25 hours' where folio = %s", (sin_confirmar["folio"],))
    bd.execute("update solicitud set confirmada_en = now() - interval '8 days' where id = %s", (sin_respuesta,))
    bd.execute("update solicitud set recoger_hasta = now() - interval '1 minute' where id = %s", (sin_recoger,))
    r = bd.execute("select app.tareas_periodicas() as r").fetchone()["r"]
    assert (r["sin_confirmar"], r["sin_respuesta"], r["sin_recoger"]) == (1, 1, 1)
    motivos = sorted(x["motivo_cancelacion"] for x in bd.execute("select motivo_cancelacion from solicitud").fetchall())
    assert motivos == ["No se confirmó desde el correo", "No se recogió", "Sin respuesta del laboratorio"]
    assert existencias(bd, m)["apartado"] == 0
    assert bd.execute("select count(*) as n from envio where asunto like 'Solicitud cancelada%'").fetchone()["n"] == 2


def test_dias_habiles_y_recordatorios(lab):
    bd, m = lab["bd"], lab["multimetro"]
    # Viernes 18 de septiembre de 2026 + 2 días hábiles = martes 22.
    assert str(bd.execute("select app.dias_habiles_despues('2026-09-18 12:00-06', 2) as d").fetchone()["d"]) == "2026-09-22"
    _, sid = hasta_entregada(lab, [(m, 1)])
    bd.execute("alter table movimiento disable trigger solo_agregar")
    bd.execute("update movimiento set fecha_compromiso = app.al_fin_de_jornada(app.hoy() + 1) where solicitud_id = %s", (sid,))
    bd.execute("alter table movimiento enable trigger solo_agregar")
    assert bd.execute("select app.tareas_periodicas() as r").fetchone()["r"]["recordatorios"] == 1
    assert bd.execute("select app.tareas_periodicas() as r").fetchone()["r"]["recordatorios"] == 0     # no se repite
    assert bd.execute("select count(*) as n from envio where asunto = 'Mañana vence tu préstamo'").fetchone()["n"] == 1


def test_cola_de_envios(lab):
    bd = lab["bd"]
    enviar(bd, [(lab["multimetro"], 1)])
    admin(bd, lab["r"], "dispositivo_registrar", p_token="token-fcm-vencido-000000000000", p_plataforma="android")
    publico(bd, "solicitud_publica_confirmar", p_token=enlaces_de_correo(bd)[0])
    with como_servidor(bd):
        correos = bd.execute("select * from public.envios_tomar(array['CORREO'], 10)").fetchall()
        assert len(correos) == 1 and bd.execute("select * from public.envios_tomar(array['CORREO'], 10)").fetchall() == []
        rpc(bd, "envio_resultado", p_id=correos[0]["id"], p_ok=True, p_error=None, p_token_invalido=False)
        push = bd.execute("select * from public.envios_tomar(array['PUSH'], 10)").fetchall()
        rpc(bd, "envio_resultado", p_id=push[0]["id"], p_ok=False, p_error="UNREGISTERED", p_token_invalido=True)
    assert [e["estado"] for e in bd.execute("select estado from envio order by id").fetchall()] == ["ENVIADO", "FALLIDO"]
    assert not bd.execute("select activo from dispositivo").fetchone()["activo"]


# --- Expediente, configuración -------------------------------------------------------
def test_expediente_de_un_prestamo(lab):
    bd, m = lab["bd"], lab["multimetro"]
    _, sid = hasta_entregada(lab, [(m, 1)])
    p = bd.execute("select id from movimiento where solicitud_id = %s", (sid,)).fetchone()["id"]
    with rechazo("PT403", "ROL"), como(bd, lab["d"]):
        rpc(bd, "expediente_prestamo", p_prestamo=p)
    exp = admin(bd, lab["s"], "expediente_prestamo", p_prestamo=p)
    assert (exp["a_cargo"], exp["a_cargo_matricula"], exp["autorizo"]) == ("Juan Pérez Chan (Alumno, 5°B)", "23-0456", "Jaime Lugo")
    sol = exp["solicitud"]
    assert (sol["confirmada_como"], sol["tipo_identificacion"], sol["hay_identificacion"]) == ("CORREO", "TRANSPORTE", True)
    assert [c["estado"] for c in sol["codigos"]] == ["USADO"] and len(sol["fotos_entrega"]) == 1
    assert "identificaciones" not in str(exp)                      # la ruta de la identificación no viaja en el expediente


def test_confirmar_en_persona_y_editar_ficha(lab):
    bd = lab["bd"]
    r = enviar(bd, [(lab["multimetro"], 1)], tipo="MAESTRO", matricula="E-77", nombre="Mario Canul Pech", correo="mario@gmail.com")
    sid = id_de(bd, r["folio"])
    with rechazo("P0001", contiene="no está confirmada"):
        aprobar(lab, sid)
    admin(bd, lab["r"], "solicitud_confirmar_en_persona", p_id=sid)
    assert aprobar(lab, sid)["codigo"]
    ficha = bd.execute("select id from solicitante").fetchone()["id"]
    admin(bd, lab["r"], "solicitante_editar", p_id=ficha, p_nombre="Mario Canul Pech", p_grupo="Física",
          p_correo="mario.canul@gmail.com", p_telefono=None)
    assert bd.execute("select correo_confirmado_en from solicitante").fetchone()["correo_confirmado_en"] is None


def test_configuracion_la_cambia_sub_administracion(lab):
    bd = lab["bd"]
    with rechazo("PT403", "ROL"):
        admin(bd, lab["r"], "configuracion_cambiar", p_clave="fin_ciclo_escolar", p_valor=Jsonb("2027-07-09"))
    with rechazo("P0001", contiene="no se cambia desde la app"):
        admin(bd, lab["s"], "configuracion_cambiar", p_clave="pin_intentos_max", p_valor=Jsonb(99))
    admin(bd, lab["s"], "configuracion_cambiar", confirmada=True, p_clave="plazo_max_alumno_dias", p_valor=Jsonb("21"))
    assert bd.execute("select valor from configuracion where clave = 'plazo_max_alumno_dias'").fetchone()["valor"] == 21
    with rechazo("P0001", contiene="La hora no es válida"):
        admin(bd, lab["s"], "configuracion_cambiar", confirmada=True, p_clave="hora_fin_jornada", p_valor=Jsonb("25:99"))


def test_reporte_de_dano_avisa_al_responsable(lab):
    bd, m = lab["bd"], lab["multimetro"]
    inc = uuid.uuid4()
    archivo(bd, f"incidencias/{inc}/1.jpg", "privado")
    with como(bd, lab["d"], nivel="PIN"):
        rpc(bd, "incidencia_reportar", p_id=inc, p_articulo=m, p_tipo="DANO", p_cantidad=1, p_prestamo=None,
            p_nota="La perilla está rota y no gira", p_fotos=Jsonb([{"ruta": f"incidencias/{inc}/1.jpg"}]), p_sin_foto=None)
    assert [(a["titulo"], a["cuerpo"], a["ruta"]) for a in lista(bd, lab["r"], "avisos_listar")] \
        == [("Reporte de daño", "1 de Multímetro Truper", "/por-revisar")]


def test_correos_viejos_caducan_y_la_tarea_solo_despierta_si_hay_trabajo(lab):
    bd = lab["bd"]
    assert not bd.execute("select app.hay_trabajo_para_avisos() as h").fetchone()["h"]
    enviar(bd, [(lab["multimetro"], 1)])
    assert bd.execute("select app.hay_trabajo_para_avisos() as h").fetchone()["h"]
    assert bd.execute("select app.caducar_envios() as n").fetchone()["n"] == 0
    bd.execute("update envio set creado_en = now() - interval '3 days'")
    assert bd.execute("select app.caducar_envios() as n").fetchone()["n"] == 1
    assert bd.execute("select estado, error from envio").fetchone() == {"estado": "FALLIDO", "error": "Caducó sin enviarse"}
    assert not bd.execute("select app.hay_trabajo_para_avisos() as h").fetchone()["h"]
