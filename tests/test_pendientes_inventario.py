"""Fase 4b (migración 0010): pendientes, conteos en lote, desglose de kits con plantillas, inventario periódico
y "avísame cuando regrese".
"""
import uuid

import pytest
from psycopg.types.json import Jsonb

from ayudantes import archivo, como, como_servidor, existencias, insertar, mov, nueva_sesion, rpc, usuario
from test_acceso import confirmar, rechazo


@pytest.fixture
def taller(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    s = usuario(bd, "SUBADMIN", "Sub Administración")
    d = usuario(bd, "DOCENTE", "Ruth Canché", pin="4826")
    cajon = insertar(bd, "contenedor", nombre="Cajón A")
    llaves = insertar(bd, "articulo", nombre="Llaves combinadas", categoria="HERRAMIENTAS", cantidad_estimada=True,
                      estado_inventario="POR_CONTAR")
    mov(bd, llaves, "ALTA", 10, r)
    tarea = lambda a, tipo: insertar(bd, "tarea_pendiente", articulo_id=a, tipo=tipo, descripcion=tipo, origen="IMPORTACION")
    return dict(bd=bd, r=r, s=s, d=d, cajon=cajon, llaves=llaves, tarea=tarea)


def admin(bd, yo, funcion, *, confirmada=False, nivel="CONTRASENA", **params):
    sesion = nueva_sesion(bd, yo)
    if confirmada:
        assert confirmar(bd, yo, sesion)["ok"]
    with como(bd, yo, nivel=nivel, sesion=sesion):
        return rpc(bd, funcion, **params)


def tabla(bd, yo, funcion, *args, nivel="CONTRASENA"):
    marcas = ", ".join(["%s"] * len(args))
    with como(bd, yo, nivel=nivel):
        return bd.execute(f"select * from public.{funcion}({marcas})", args).fetchall()


def estado(bd, a):
    return bd.execute("select estado_inventario from articulo where id = %s", (a,)).fetchone()["estado_inventario"]


def foto_principal(bd, a):
    insertar(bd, "foto", articulo_id=a, url=archivo(bd, f"articulos/{a}/f.jpg"), es_principal=True)


# --- VERIFICADO: una sola regla ---------------------------------------------------
def test_verificado_con_foto_ubicacion_conteo_y_sin_pendientes(taller):
    bd, r = taller["bd"], taller["r"]
    a = insertar(bd, "articulo", nombre="Vernier", categoria="HERRAMIENTAS", estado_inventario="POR_VERIFICAR")
    mov(bd, a, "ALTA", 1, r)
    t = taller["tarea"](a, "REGISTRAR_SERIE")
    foto_principal(bd, a)
    bd.execute("update articulo set contenedor_id = %s where id = %s", (taller["cajon"], a))
    assert estado(bd, a) == "POR_VERIFICAR"                                  # le falta resolver su pendiente
    admin(bd, r, "pendiente_resolver", p_tarea=t, p_datos=Jsonb({"num_serie": "VRN-150-7"}))
    assert estado(bd, a) == "VERIFICADO"
    assert bd.execute("select num_serie from articulo where id = %s", (a,)).fetchone()["num_serie"] == "VRN-150-7"


# --- F-15 Pendientes ---------------------------------------------------------------
def test_resolver_pendientes_por_tipo(taller):
    bd, r, d = taller["bd"], taller["r"], taller["d"]
    caja = insertar(bd, "articulo", nombre="Estuche Dremel", categoria="HERRAMIENTAS_ELECTRICAS", estado_inventario="POR_VERIFICAR")
    mov(bd, caja, "ALTA", 1, r)
    vacio = taller["tarea"](caja, "CONFIRMAR_VACIO")
    falta = taller["tarea"](caja, "FALTA_PIEZA")
    dato = taller["tarea"](caja, "VERIFICAR_DATO")
    etiq = taller["tarea"](caja, "IDENTIFICAR_ETIQUETAR")

    with rechazo("PT403", "ROL"):
        admin(bd, d, "pendiente_resolver", p_tarea=vacio, p_datos=Jsonb({"vacio": True}))
    archivo(bd, f"articulos/{caja}/abierto.jpg")
    admin(bd, d, "pendiente_aportar", nivel="PIN", p_tarea=vacio, p_nota="Lo abrí: no trae nada", p_foto=f"articulos/{caja}/abierto.jpg")
    assert [(x["autor"], x["nota"]) for x in tabla(bd, r, "pendiente_aportes", vacio)] == [("Ruth Canché", "Lo abrí: no trae nada")]
    assert bd.execute("select es_principal from foto where articulo_id = %s", (caja,)).fetchone()["es_principal"]

    admin(bd, r, "pendiente_resolver", p_tarea=vacio, p_datos=Jsonb({"vacio": True}))
    fila = bd.execute("select estado_fisico from articulo where id = %s", (caja,)).fetchone()
    assert fila["estado_fisico"] == "VACIO"
    assert bd.execute("select count(*) as n from tarea_pendiente where articulo_id = %s and tipo = 'LOCALIZAR_CONTENIDO' and not resuelta",
                      (caja,)).fetchone()["n"] == 1
    with rechazo("P0001", contiene="ya se resolvió"):
        admin(bd, r, "pendiente_resolver", p_tarea=vacio, p_datos=Jsonb({"vacio": True}))

    with rechazo("P0001", contiene="Escribe qué se encontró"):
        admin(bd, r, "pendiente_resolver", p_tarea=falta, p_datos=Jsonb({"resultado": "INCOMPLETO"}))
    admin(bd, r, "pendiente_resolver", p_tarea=falta, p_datos=Jsonb({"resultado": "INCOMPLETO", "nota": "Faltan 3 puntas"}))
    assert bd.execute("select estado_fisico from articulo where id = %s", (caja,)).fetchone()["estado_fisico"] == "INCOMPLETO"

    admin(bd, r, "pendiente_resolver", p_tarea=dato, p_datos=Jsonb({"cambios": {"marca_modelo": "Dremel 3000"}}))
    assert bd.execute("select marca_modelo from articulo where id = %s", (caja,)).fetchone()["marca_modelo"] == "Dremel 3000"

    admin(bd, r, "pendiente_resolver", p_tarea=etiq, p_datos=Jsonb({"contenedor_id": str(taller["cajon"]), "etiquetado": "INDIVIDUAL"}))
    a = bd.execute("select contenedor_id, etiquetado from articulo where id = %s", (caja,)).fetchone()
    assert (a["contenedor_id"], a["etiquetado"]) == (taller["cajon"], "INDIVIDUAL")

    contar = taller["tarea"](taller["llaves"], "CONTAR")
    with rechazo("P0001", contiene="al aplicar un conteo"):
        admin(bd, r, "pendiente_resolver", p_tarea=contar, p_datos=Jsonb({}))
    with rechazo("P0001", contiene="al menos 10 letras"):
        admin(bd, r, "pendiente_resolver", p_tarea=contar, p_datos=Jsonb({"accion": "DESCARTAR", "motivo": "no"}))
    admin(bd, r, "pendiente_resolver", p_tarea=contar, p_datos=Jsonb({"accion": "DESCARTAR", "motivo": "Duplicado de otro renglón"}))


def test_definir_vex_o_ftc_pide_reconfirmar_y_saca_del_contenedor_incompatible(taller):
    bd, r = taller["bd"], taller["r"]
    piezas = insertar(bd, "articulo", nombre="Piezas hexagonales blancas", categoria="SIN_CLASIFICAR", estado_inventario="SIN_CLASIFICAR",
                      contenedor_id=taller["cajon"])
    t = taller["tarea"](piezas, "DEFINIR_VEX_FTC")
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        admin(bd, r, "pendiente_resolver", p_tarea=t, p_datos=Jsonb({"categoria": "VEX"}))
    admin(bd, r, "pendiente_resolver", confirmada=True, p_tarea=t, p_datos=Jsonb({"categoria": "VEX", "nota": "Son de VEX IQ"}))
    a = bd.execute("select categoria, estado_inventario, contenedor_id from articulo where id = %s", (piezas,)).fetchone()
    assert (a["categoria"], a["estado_inventario"], a["contenedor_id"]) == ("VEX", "POR_VERIFICAR", None)


# --- F-13 Conteos en lote ---------------------------------------------------------------
def test_docente_cuenta_y_el_responsable_aplica_en_lote(taller):
    bd, r, d, llaves = taller["bd"], taller["r"], taller["d"], taller["llaves"]
    taller["tarea"](llaves, "CONTAR")
    pinzas = insertar(bd, "articulo", nombre="Pinzas", categoria="HERRAMIENTAS")
    mov(bd, pinzas, "ALTA", 4, r)
    mov(bd, llaves, "PRESTAMO", 2, r)                                        # 8 en el taller

    c1 = admin(bd, d, "conteo_proponer", nivel="PIN", p_articulo=llaves, p_en_taller=7, p_nota=None)
    assert (c1["sistema"], c1["diferencia"]) == (8, -1)
    c2 = admin(bd, d, "conteo_proponer", nivel="PIN", p_articulo=pinzas, p_en_taller=4, p_nota=None)
    assert [x["nombre"] for x in tabla(bd, d, "conteos_por_aplicar", nivel="PIN")] == ["Llaves combinadas", "Pinzas"]
    with rechazo("PT403", "ROL"):
        admin(bd, d, "conteos_aplicar", confirmada=True, p_ids=[uuid.UUID(c1["id"])], p_notas=Jsonb({}))

    ids = [uuid.UUID(c1["id"]), uuid.UUID(c2["id"])]
    with rechazo("P0001", contiene="Falta explicar la diferencia"):
        admin(bd, r, "conteos_aplicar", confirmada=True, p_ids=ids, p_notas=Jsonb({}))
    # Mientras tanto se devolvió lo prestado: el ajuste compara contra lo que había al contar.
    p = bd.execute("select id from movimiento where tipo = 'PRESTAMO'").fetchone()["id"]
    mov(bd, llaves, "DEVOLUCION", 2, r, movimiento_origen_id=p)
    res = admin(bd, r, "conteos_aplicar", confirmada=True, p_ids=ids, p_notas=Jsonb({c1["id"]: "Una se perdió hace meses"}))
    assert res == {"aplicados": 2, "ajustes": 1}
    assert (existencias(bd, llaves)["existencia"], existencias(bd, llaves)["en_taller"]) == (9, 9)
    a = bd.execute("select cantidad_estimada, estado_inventario from articulo where id = %s", (llaves,)).fetchone()
    assert (a["cantidad_estimada"], a["estado_inventario"]) == (False, "POR_VERIFICAR")
    assert bd.execute("select resuelta from tarea_pendiente where articulo_id = %s", (llaves,)).fetchone()["resuelta"]
    ajuste = bd.execute("select autorizado_por, registrado_por, nota from movimiento where tipo = 'AJUSTE_CONTEO'").fetchone()
    assert (ajuste["autorizado_por"], ajuste["registrado_por"]) == (r, d) and "Ruth Canché" in ajuste["nota"]


# --- Desglose de kits ----------------------------------------------------------------
@pytest.fixture
def kit(taller):
    bd, r = taller["bd"], taller["r"]
    ftc = insertar(bd, "contenedor", nombre="Caja FTC", categoria_exclusiva="FTC")
    k = insertar(bd, "articulo", nombre="Cajas REV adicionales", categoria="FTC", unidad="caja", contenedor_id=ftc)
    mov(bd, k, "ALTA", 3, r)
    abrir = taller["tarea"](k, "ABRIR_REVISAR")
    servos = insertar(bd, "articulo", nombre="Smart Robot Servo", categoria="FTC", contenedor_id=ftc)
    mov(bd, servos, "ALTA", 2, r)
    plantilla = insertar(bd, "plantilla_kit", nombre="REV Starter Kit V3", sku="REV-45-1883", categoria="FTC")
    for orden, (desc, cant) in enumerate([("Smart Robot Servo", 4), ("Core Hex Motor", 2), ("Tornillería surtida", None)], start=1):
        insertar(bd, "plantilla_kit_linea", plantilla_id=plantilla, orden=orden, descripcion=desc, cantidad=cant)
    return dict(taller, ftc=ftc, kit=k, abrir=abrir, servos=servos, plantilla=plantilla)


def test_desglose_de_una_caja_con_plantilla(kit):
    bd, r, k = kit["bd"], kit["r"], kit["kit"]
    with rechazo("P0001", contiene="de 1 a 3 unidades"):
        admin(bd, r, "desglose_iniciar", p_articulo=k, p_unidades=4, p_plantilla=kit["plantilla"])
    b = admin(bd, r, "desglose_iniciar", p_articulo=k, p_unidades=1, p_plantilla=kit["plantilla"])
    assert [(l["descripcion"], l["esperada"]) for l in b["lineas"]] == [("Smart Robot Servo", 4), ("Core Hex Motor", 2), ("Tornillería surtida", None)]
    assert admin(bd, r, "desglose_iniciar", p_articulo=k, p_unidades=2, p_plantilla=None)["id"] == b["id"]      # retoma el borrador

    lineas = [dict(l) for l in b["lineas"]]
    lineas[0].update(encontrada=3, articulo_destino_id=str(kit["servos"]))
    lineas[1].update(encontrada=1)
    lineas[2].update(encontrada=1, unidad="bolsa", es_consumible=True)
    guardado = admin(bd, r, "desglose_guardar", p_id=uuid.UUID(b["id"]), p_unidades=1, p_lineas=Jsonb(lineas), p_nota=None)
    assert guardado["lineas"][0]["articulo_destino"].endswith("Smart Robot Servo")

    with rechazo("P0001", contiene="Solo se deja como empaque"):
        admin(bd, r, "desglose_terminar", confirmada=True, p_id=uuid.UUID(b["id"]), p_destino="EMPAQUE")
    with rechazo("PT403", "CONFIRMAR_CONTRASENA"):
        admin(bd, r, "desglose_terminar", p_id=uuid.UUID(b["id"]), p_destino="DESGLOSADO")
    res = admin(bd, r, "desglose_terminar", confirmada=True, p_id=uuid.UUID(b["id"]), p_destino="DESGLOSADO")
    assert res == {"creados": 2, "sumados": 1, "faltantes": 2}

    assert existencias(bd, kit["servos"])["existencia"] == 5
    assert existencias(bd, k)["existencia"] == 2
    nuevos = bd.execute("select nombre, categoria, contenedor_id, desglosado_de, es_consumible, etiquetado, cantidad from articulo "
                        "where desglosado_de is not null order by nombre").fetchall()
    assert [(n["nombre"], n["categoria"], n["contenedor_id"], n["cantidad"], n["etiquetado"]) for n in nuevos] == [
        ("Core Hex Motor", "FTC", kit["ftc"], 1, "CONTENEDOR"), ("Tornillería surtida", "FTC", kit["ftc"], 1, "LOTE")]
    k_fila = bd.execute("select activo, estado_inventario from articulo where id = %s", (k,)).fetchone()
    assert k_fila["activo"] and not bd.execute("select resuelta from tarea_pendiente where id = %s", (kit["abrir"],)).fetchone()["resuelta"]
    with rechazo("P0001", contiene="ya no se modifica"):
        bd.execute("update desglose_linea set encontrada = 9 where desglose_id = %s", (uuid.UUID(b["id"]),))
    historial = tabla(bd, r, "desgloses_de_articulo", k)
    assert [(h["estado"], h["faltantes"]) for h in historial] == [("TERMINADO", 2)]


def test_desglose_de_todas_las_cajas(kit):
    bd, r, k = kit["bd"], kit["r"], kit["kit"]
    b = admin(bd, r, "desglose_iniciar", p_articulo=k, p_unidades=3, p_plantilla=None)
    lineas = [{"descripcion": "Llantas mecanum", "encontrada": 4}]
    admin(bd, r, "desglose_guardar", p_id=uuid.UUID(b["id"]), p_unidades=3, p_lineas=Jsonb(lineas), p_nota=None)
    admin(bd, r, "desglose_terminar", confirmada=True, p_id=uuid.UUID(b["id"]), p_destino="DESGLOSADO")
    k_fila = bd.execute("select activo, estado_inventario from articulo where id = %s", (k,)).fetchone()
    assert (k_fila["activo"], k_fila["estado_inventario"]) == (False, "DESGLOSADO")
    assert bd.execute("select resuelta from tarea_pendiente where id = %s", (kit["abrir"],)).fetchone()["resuelta"]


def test_piezas_de_un_kit_ftc_no_se_suman_a_vex(kit):
    bd, r = kit["bd"], kit["r"]
    vex = insertar(bd, "articulo", nombre="Motor 393", categoria="VEX")
    b = admin(bd, r, "desglose_iniciar", p_articulo=kit["kit"], p_unidades=1, p_plantilla=None)
    admin(bd, r, "desglose_guardar", p_id=uuid.UUID(b["id"]), p_unidades=1,
          p_lineas=Jsonb([{"descripcion": "Motor", "encontrada": 1, "articulo_destino_id": str(vex)}]), p_nota=None)
    with rechazo("P0001", contiene="misma categoría"):
        admin(bd, r, "desglose_terminar", confirmada=True, p_id=uuid.UUID(b["id"]), p_destino="DESGLOSADO")


# --- F-16 Inventario periódico ------------------------------------------------------------
def test_inventario_periodico_completo(taller):
    bd, r, s, d = taller["bd"], taller["r"], taller["s"], taller["d"]
    llaves = taller["llaves"]
    taller["tarea"](llaves, "CONTAR")
    pinzas = insertar(bd, "articulo", nombre="Pinzas", categoria="HERRAMIENTAS", contenedor_id=taller["cajon"])
    mov(bd, pinzas, "ALTA", 5, r)
    cautin = insertar(bd, "articulo", nombre="Cautín", categoria="HERRAMIENTAS")
    mov(bd, cautin, "ALTA", 2, r)
    cinta = insertar(bd, "articulo", nombre="Cinta", categoria="CONSUMIBLES", es_consumible=True)
    mov(bd, cinta, "ALTA", 3, r)

    inv = admin(bd, s, "inventario_abrir", p_nombre="Fin de semestre", p_alcance=Jsonb({"categorias": ["HERRAMIENTAS"]}))
    with rechazo("P0001", contiene="Ya hay un inventario abierto"):
        admin(bd, r, "inventario_abrir", p_nombre="Otro", p_alcance=Jsonb({"todo": True}))
    assert {a["nombre"] for a in tabla(bd, d, "inventario_articulos", inv, nivel="PIN")} == {"Llaves combinadas", "Pinzas", "Cautín"}

    def contar(yo, a, n, nivel="PIN"):
        admin(bd, yo, "inventario_contar", nivel=nivel, p_inventario=inv, p_articulo=a, p_cantidad=n, p_contenedor=None, p_nota=None)

    with rechazo("P0001", contiene="no está en el alcance"):
        contar(d, cinta, 3)
    contar(d, llaves, 10)            # coincide
    mov(bd, pinzas, "PRESTAMO", 1, r)  # el taller sigue trabajando: 4 en el taller
    contar(d, pinzas, 3)             # falta 1
    contar(r, pinzas, 2)             # otra persona cuenta distinto
    admin(bd, d, "inventario_hallazgo_registrar", nivel="PIN", p_inventario=inv, p_descripcion="Caja de brocas sin registrar",
          p_contenedor=taller["cajon"], p_articulo=None, p_cantidad=1, p_foto=None)

    difs = {x["nombre"]: x for x in tabla(bd, s, "inventario_diferencias", inv)}
    assert (difs["Llaves combinadas"]["diferencia"], difs["Pinzas"]["conflicto"], difs["Cautín"]["contados"]) == (0, True, 0)
    with rechazo("P0001", contiene="Hay conteos que no coinciden"):
        admin(bd, s, "inventario_cerrar", confirmada=True, p_inventario=inv)
    with rechazo("P0001", contiene="mándalo a recontar"):
        admin(bd, s, "inventario_decidir", p_inventario=inv, p_articulo=pinzas, p_decision="AJUSTE", p_nota="x")
    admin(bd, s, "inventario_decidir", p_inventario=inv, p_articulo=pinzas, p_decision="RECONTAR", p_nota=None)
    contar(r, pinzas, 3, nivel="CONTRASENA")
    with rechazo("P0001", contiene="Faltan decisiones en las diferencias de"):
        admin(bd, s, "inventario_cerrar", confirmada=True, p_inventario=inv)
    admin(bd, s, "inventario_decidir", p_inventario=inv, p_articulo=pinzas, p_decision="AJUSTE", p_nota="Se rompió una y se tiró")
    with rechazo("P0001", contiene="ya se revisó"):
        contar(d, pinzas, 4)

    res = admin(bd, s, "inventario_cerrar", confirmada=True, p_inventario=inv)
    assert res == {"contados": 2, "ajustes": 1, "reportes": 0, "no_contados": 1}
    assert existencias(bd, pinzas)["existencia"] == 4 and existencias(bd, llaves)["existencia"] == 10
    ajuste = bd.execute("select inventario_id, origen from movimiento where tipo = 'AJUSTE_CONTEO'").fetchone()
    assert (ajuste["inventario_id"], ajuste["origen"]) == (inv, "INVENTARIO")
    assert bd.execute("select cantidad_estimada from articulo where id = %s", (llaves,)).fetchone()["cantidad_estimada"] is False
    assert bd.execute("select resuelta from tarea_pendiente where articulo_id = %s and tipo = 'CONTAR'", (llaves,)).fetchone()["resuelta"]
    assert existencias(bd, cautin)["existencia"] == 2                         # no contado no es cero
    assert [(h["descripcion"], h["decision"]) for h in tabla(bd, r, "inventario_hallazgos", inv)] == [("Caja de brocas sin registrar", None)]
    assert [i["estado"] for i in tabla(bd, d, "inventarios_listar", nivel="PIN")] == ["CERRADO"]


def test_faltante_del_inventario_como_reporte_de_perdida(taller):
    bd, r = taller["bd"], taller["r"]
    pinzas = insertar(bd, "articulo", nombre="Pinzas", categoria="HERRAMIENTAS", contenedor_id=taller["cajon"])
    mov(bd, pinzas, "ALTA", 5, r)
    inv = admin(bd, r, "inventario_abrir", p_nombre="Por contenedor", p_alcance=Jsonb({"contenedores": [str(taller["cajon"])]}))
    admin(bd, r, "inventario_contar", p_inventario=inv, p_articulo=pinzas, p_cantidad=3, p_contenedor=taller["cajon"], p_nota=None)
    with rechazo("P0001", contiene="al menos 15 letras"):
        admin(bd, r, "inventario_decidir", p_inventario=inv, p_articulo=pinzas, p_decision="INCIDENCIA", p_nota="faltan")
    admin(bd, r, "inventario_decidir", p_inventario=inv, p_articulo=pinzas, p_decision="INCIDENCIA", p_nota="No aparecen dos pinzas del cajón A")
    inc = bd.execute("select tipo, cantidad, estado, en_taller from incidencia").fetchone()
    assert (inc["tipo"], inc["cantidad"], inc["estado"], inc["en_taller"]) == ("PERDIDA", 2, "PENDIENTE", True)
    assert admin(bd, r, "inventario_cerrar", confirmada=True, p_inventario=inv) == {"contados": 1, "ajustes": 0, "reportes": 1, "no_contados": 0}
    assert existencias(bd, pinzas)["existencia"] == 5                         # la pérdida se aplica al confirmar el reporte


# --- "Avísame cuando regrese" ------------------------------------------------------------------
def test_avisame_cuando_regrese(taller):
    bd, r = taller["bd"], taller["r"]
    impresora = insertar(bd, "articulo", nombre="Impresora 3D", categoria="HERRAMIENTAS_ELECTRICAS")
    mov(bd, impresora, "ALTA", 1, r)

    def pedir(correo, dispositivo="cel-1"):
        with como_servidor(bd):
            return rpc(bd, "aviso_disponible_crear", p_articulo=impresora, p_correo=correo, p_ip="1.2.3.4", p_dispositivo=dispositivo)

    with rechazo("P0001", contiene="Ya hay disponible"):
        pedir("ana@gmail.com")
    p = mov(bd, impresora, "PRESTAMO", 1, r)
    assert "a***@gmail.com" in pedir("ana@gmail.com")["mensaje"]
    assert "Ya estaba registrado" in pedir("ana@gmail.com")["mensaje"]
    for i in range(4):
        pedir(f"x{i}@gmail.com")
    with rechazo("P0001", contiene="demasiados avisos"):
        pedir("otro@gmail.com")

    assert bd.execute("select app.revisar_avisos_disponible() as n").fetchone()["n"] == 0
    mov(bd, impresora, "DEVOLUCION", 1, r, movimiento_origen_id=p)
    assert bd.execute("select app.revisar_avisos_disponible() as n").fetchone()["n"] == 5
    correo = bd.execute("select asunto, cuerpo from envio where destino = 'ana@gmail.com'").fetchone()
    assert correo["asunto"] == 'Ya hay "Impresora 3D" disponible' and f"/articulo/{impresora}" in correo["cuerpo"]
    assert bd.execute("select app.revisar_avisos_disponible() as n").fetchone()["n"] == 0        # un solo aviso
    with rechazo("42501"), como(bd):
        rpc(bd, "aviso_disponible_crear", p_articulo=impresora, p_correo="a@b.com", p_ip="x", p_dispositivo="x")


# --- Artículos que no se prestan (migración 0011) --------------------------------------------
def test_empaques_y_equipo_fijo_no_se_prestan(taller):
    bd, r, d = taller["bd"], taller["r"], taller["d"]
    cajas = insertar(bd, "articulo", nombre="Cajas de Driver Hub (vacías)", categoria="FTC")
    mov(bd, cajas, "ALTA", 3, r)
    with rechazo("PT403", "ROL"):
        admin(bd, d, "articulo_marcar_prestable", p_articulo=cajas, p_prestable=False, p_motivo="Solo cajas")
    with rechazo("P0001", contiene="Escribe por qué"):
        admin(bd, r, "articulo_marcar_prestable", p_articulo=cajas, p_prestable=False, p_motivo=None)
    admin(bd, r, "articulo_marcar_prestable", p_articulo=cajas, p_prestable=False, p_motivo="Son cajas vacías")
    fila = bd.execute("select prestable, disponible from v_existencias where articulo_id = %s", (cajas,)).fetchone()
    assert (fila["prestable"], fila["disponible"]) == (False, 3)
    with rechazo("P0001", contiene="no se presta: Son cajas vacías"):
        mov(bd, cajas, "PRESTAMO", 1, r)
    admin(bd, r, "articulo_marcar_prestable", p_articulo=cajas, p_prestable=True, p_motivo=None)
    mov(bd, cajas, "PRESTAMO", 1, r)


def test_kit_como_empaque_ya_no_se_presta(kit):
    bd, r, k = kit["bd"], kit["r"], kit["kit"]
    b = admin(bd, r, "desglose_iniciar", p_articulo=k, p_unidades=3, p_plantilla=None)
    admin(bd, r, "desglose_guardar", p_id=uuid.UUID(b["id"]), p_unidades=3, p_lineas=Jsonb([{"descripcion": "Llantas", "encontrada": 4}]), p_nota=None)
    admin(bd, r, "desglose_terminar", confirmada=True, p_id=uuid.UUID(b["id"]), p_destino="EMPAQUE")
    a = bd.execute("select activo, no_se_presta, estado_fisico from articulo where id = %s", (k,)).fetchone()
    assert (a["activo"], a["no_se_presta"], a["estado_fisico"]) == (True, True, "VACIO")
