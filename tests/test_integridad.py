"""Reglas que la base hace cumplir aunque la app tenga un error."""
import threading

import psycopg
import pytest

from ayudantes import articulo, contenedor, existencias, mov, solicitante, usuario

Rechazo = psycopg.errors.RaiseException


@pytest.fixture
def base(bd):
    r = usuario(bd)
    a = articulo(bd)
    m = mov(bd, a, "ALTA", 5, r)
    return bd, r, a, m


# --- Nada se borra, los movimientos no se editan ---------------------------
def test_movimiento_no_se_edita(base):
    bd, r, a, m = base
    with pytest.raises(Rechazo, match="no se editan ni se borran"):
        bd.execute("update movimiento set cantidad = 50 where id = %s", (m,))


def test_movimiento_no_se_borra(base):
    bd, r, a, m = base
    with pytest.raises(Rechazo, match="no se editan ni se borran"):
        bd.execute("delete from movimiento where id = %s", (m,))
    with pytest.raises(Rechazo, match="no se editan ni se borran"):
        bd.execute("truncate movimiento cascade")


def test_articulo_no_se_borra(base):
    bd, r, a, m = base
    with pytest.raises(Rechazo, match="No se borran registros de articulo"):
        bd.execute("delete from articulo where id = %s", (a,))


# --- La cantidad solo cambia con movimientos ---------------------------------
def test_cantidad_no_se_edita_a_mano(base):
    bd, r, a, m = base
    with pytest.raises(Rechazo, match="no se edita: registra un movimiento"):
        bd.execute("update articulo set cantidad = 99 where id = %s", (a,))
    with pytest.raises(Rechazo, match="registra un movimiento de alta"):
        articulo(bd, "Otro", cantidad=3)


def test_descuadre_se_detecta(base):
    """Si alguien con acceso total a la base cambia la cantidad saltándose las reglas, se nota."""
    bd, r, a, m = base
    bd.execute("set session_replication_role = replica")   # desactiva disparadores (solo superusuario)
    bd.execute("update articulo set cantidad = 7 where id = %s", (a,))
    bd.execute("set session_replication_role = origin")
    fila = bd.execute("select * from v_descuadres").fetchone()
    assert (fila["codigo"], fila["cantidad_registrada"], fila["existencia"], fila["diferencia"]) == (
        bd.execute("select codigo from articulo where id = %s", (a,)).fetchone()["codigo"], 7, 5, 2)
    assert existencias(bd, a)["cuadra"] is False


# --- Responsable nominal y autorización --------------------------------------
def test_prestamo_sin_responsable_se_rechaza(base):
    bd, r, a, m = base
    with pytest.raises(psycopg.errors.CheckViolation):
        mov(bd, a, "PRESTAMO", 1, r, responsable_usuario_id=None)


def test_prestamo_con_dos_responsables_se_rechaza(base):
    bd, r, a, m = base
    with pytest.raises(psycopg.errors.CheckViolation):
        mov(bd, a, "PRESTAMO", 1, r, responsable_usuario_id=r, responsable_solicitante_id=solicitante(bd))


def test_movimiento_sin_autorizacion_se_rechaza(base):
    bd, r, a, m = base
    with pytest.raises(psycopg.errors.CheckViolation):
        mov(bd, a, "PRESTAMO", 1, None, responsable_usuario_id=r)


def test_perdida_sin_justificacion_se_rechaza(base):
    bd, r, a, m = base
    with pytest.raises(psycopg.errors.CheckViolation):
        mov(bd, a, "PERDIDA", 1, r, nota="  ")


def test_mismo_comando_no_se_aplica_dos_veces(base):
    bd, r, a, m = base
    import uuid
    comando = uuid.uuid4()
    mov(bd, a, "PRESTAMO", 1, r, comando_id=comando)
    with pytest.raises(psycopg.errors.UniqueViolation):
        mov(bd, a, "PRESTAMO", 1, r, comando_id=comando)
    assert existencias(bd, a)["prestado"] == 1


# --- VEX y FTC no se mezclan ---------------------------------------------------
def test_pieza_vex_no_entra_en_contenedor_ftc(bd):
    ftc = contenedor(bd, "Bolsas REV", categoria_exclusiva="FTC")
    with pytest.raises(Rechazo, match="VEX y FTC no se mezclan"):
        articulo(bd, "Batería VEX V5", categoria="VEX", contenedor_id=ftc)


def test_pieza_vex_solo_en_contenedor_exclusivo_vex(bd):
    mixto = contenedor(bd, "Cajón general")
    vex = contenedor(bd, "Gaveta VEX", categoria_exclusiva="VEX")
    with pytest.raises(Rechazo, match="no es exclusivo de VEX"):
        articulo(bd, "Batería VEX V5", categoria="VEX", contenedor_id=mixto)
    articulo(bd, "Batería VEX V5", categoria="VEX", contenedor_id=vex)
    articulo(bd, "Desarmador", categoria="HERRAMIENTAS", contenedor_id=mixto)


def test_cambiar_de_vex_a_ftc_requiere_justificacion(bd):
    a = articulo(bd, "Pieza dudosa", categoria="VEX")
    with pytest.raises(Rechazo, match="requiere justificación"):
        bd.execute("update articulo set categoria = 'FTC' where id = %s", (a,))
    with bd.transaction():
        bd.execute("select set_config('app.justificacion', 'Tiene logo REV: es FTC', true)")
        bd.execute("update articulo set categoria = 'FTC' where id = %s", (a,))
    evento = bd.execute("select datos from bitacora where registro_id = %s", (str(a),)).fetchone()["datos"]
    assert evento["justificacion"] == "Tiene logo REV: es FTC"
    assert evento["cambios"]["categoria"] == {"antes": "VEX", "despues": "FTC"}


def test_contenedor_no_puede_quedar_dentro_de_si_mismo(bd):
    gabinete = contenedor(bd, "Gabinete 2", tipo="GABINETE")
    cajon = contenedor(bd, "Cajón B", padre_id=gabinete)
    with pytest.raises(Rechazo, match="dentro de sí mismo"):
        bd.execute("update contenedor set padre_id = %s where id = %s", (cajon, gabinete))
    ruta = bd.execute("select app.ruta_contenedor(%s) as r", (cajon,)).fetchone()["r"]
    assert ruta == "Gabinete 2 › Cajón B"


# --- Dos personas prestan la última pieza al mismo tiempo ----------------------
def test_dos_prestamos_simultaneos_de_la_ultima_pieza(url_base):
    with psycopg.connect(url_base, autocommit=True, row_factory=psycopg.rows.dict_row) as bd:
        r = usuario(bd)
        a = articulo(bd, "Control Hub", categoria="FTC")
        mov(bd, a, "ALTA", 1, r)

    resultados = {}
    primero_insertado = threading.Event()
    soltar_primero = threading.Event()

    def prestar(nombre, esperar_antes_de_confirmar):
        with psycopg.connect(url_base) as conn:
            try:
                with conn.transaction():
                    conn.execute(
                        "insert into movimiento (articulo_id, tipo, cantidad, autorizado_por, responsable_usuario_id) "
                        "values (%s, 'PRESTAMO', 1, %s, %s)", (a, r, r))
                    if esperar_antes_de_confirmar:
                        primero_insertado.set()
                        soltar_primero.wait(10)
                resultados[nombre] = "aceptado"
            except Rechazo as e:
                resultados[nombre] = str(e)

    h1 = threading.Thread(target=prestar, args=("laura", True))
    h1.start()
    assert primero_insertado.wait(10)
    h2 = threading.Thread(target=prestar, args=("pedro", False))
    h2.start()
    h2.join(0.5)
    assert h2.is_alive(), "el segundo préstamo debió esperar a que terminara el primero"
    soltar_primero.set()
    h1.join(10)
    h2.join(10)

    assert resultados["laura"] == "aceptado"
    assert "Solo hay 0 disponibles" in resultados["pedro"]


# --- Lectura pública ---------------------------------------------------------
def test_sin_sesion_se_ve_el_catalogo_pero_no_los_movimientos_ni_personas(base):
    bd, r, a, m = base
    mov(bd, a, "PRESTAMO", 1, r)
    with bd.transaction():
        bd.execute("set local role anon")
        fila = bd.execute("select nombre, disponible, prestado from v_inventario").fetchone()
        assert (fila["disponible"], fila["prestado"]) == (4, 1)
        historial = bd.execute("select * from v_historial_publico where articulo_id = %s", (a,)).fetchall()
        assert len(historial) == 2 and "autorizado_por" not in historial[0]
    for tabla in ("movimiento", "usuario", "solicitante"):
        with pytest.raises(psycopg.errors.InsufficientPrivilege), bd.transaction():
            bd.execute("set local role anon")
            bd.execute(f"select * from {tabla}")


def test_sin_sesion_no_se_escribe_nada(base):
    bd, r, a, m = base
    with pytest.raises(psycopg.errors.InsufficientPrivilege), bd.transaction():
        bd.execute("set local role anon")
        bd.execute("insert into articulo (nombre, categoria) values ('x', 'COMUN')")
    with pytest.raises(psycopg.errors.InsufficientPrivilege), bd.transaction():
        bd.execute("set local role authenticated")
        bd.execute("insert into movimiento (articulo_id, tipo, cantidad, autorizado_por) values (%s, 'ALTA', 1, %s)", (a, r))
