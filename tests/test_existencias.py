"""Cálculo de existencias (docs/flujos.md, sección 1).

Aquí es donde un error se traduce en que al responsable le cobren una herramienta.
"""
import random

import psycopg
import pytest

from ayudantes import articulo, existencias, insertar, mov, pendiente_de, solicitante, usuario

Rechazo = psycopg.errors.RaiseException


@pytest.fixture
def taller(bd):
    """Un artículo con 10 piezas dadas de alta, un responsable y un docente."""
    r = usuario(bd, "RESPONSABLE")
    d = usuario(bd, "DOCENTE")
    a = articulo(bd)
    mov(bd, a, "ALTA", 10, r)
    return bd, r, d, a


def cifras(conn, a, *campos):
    e = existencias(conn, a)
    return tuple(e[c] for c in campos)


def test_alta_suma_existencia(taller):
    bd, r, d, a = taller
    e = existencias(bd, a)
    assert (e["existencia"], e["disponible"], e["cantidad_registrada"], e["cuadra"]) == (10, 10, 10, True)


def test_prestamo_baja_disponible_pero_no_existencia(taller):
    bd, r, d, a = taller
    mov(bd, a, "PRESTAMO", 3, d)
    assert cifras(bd, a, "existencia", "prestado", "en_taller", "disponible", "cantidad_registrada") == (10, 3, 7, 7, 10)


def test_devolucion_parcial_deja_abierto_lo_pendiente(taller):
    bd, r, d, a = taller
    p = mov(bd, a, "PRESTAMO", 3, d)
    mov(bd, a, "DEVOLUCION", 2, d, movimiento_origen_id=p)
    assert cifras(bd, a, "prestado", "disponible") == (1, 9)
    assert pendiente_de(bd, p) == 1


def test_devolucion_mayor_a_lo_pendiente_se_rechaza(taller):
    bd, r, d, a = taller
    p = mov(bd, a, "PRESTAMO", 3, d)
    mov(bd, a, "DEVOLUCION", 2, d, movimiento_origen_id=p)
    with pytest.raises(Rechazo, match="solo quedan 1 pendientes"):
        mov(bd, a, "DEVOLUCION", 2, d, movimiento_origen_id=p)


def test_devolucion_debe_ligarse_a_un_prestamo(taller):
    bd, r, d, a = taller
    alta = bd.execute("select id from movimiento where articulo_id = %s and tipo = 'ALTA'", (a,)).fetchone()["id"]
    with pytest.raises(Rechazo, match="solo puede ligarse a un préstamo"):
        mov(bd, a, "DEVOLUCION", 1, d, movimiento_origen_id=alta)


def test_perdida_de_algo_prestado_baja_existencia_y_prestado(taller):
    """Corrección 2.1 de la revisión: la pérdida de lo prestado también resta de Prestado."""
    bd, r, d, a = taller
    p = mov(bd, a, "PRESTAMO", 2, d)
    mov(bd, a, "PERDIDA", 2, r, movimiento_origen_id=p)
    assert cifras(bd, a, "existencia", "prestado", "disponible", "cantidad_registrada") == (8, 0, 8, 8)
    assert pendiente_de(bd, p) == 0


def test_perdida_en_el_taller(taller):
    bd, r, d, a = taller
    mov(bd, a, "PERDIDA", 1, r)
    assert cifras(bd, a, "existencia", "prestado", "disponible") == (9, 0, 9)


def test_dano_reparacion_y_baja_de_danados(taller):
    bd, r, d, a = taller
    mov(bd, a, "DAÑO", 2, r)
    assert cifras(bd, a, "existencia", "fuera_servicio", "disponible") == (10, 2, 8)
    mov(bd, a, "REPARACION", 1, r)
    assert cifras(bd, a, "fuera_servicio", "disponible") == (1, 9)
    with pytest.raises(Rechazo, match="Solo hay 1 fuera de servicio"):
        mov(bd, a, "REPARACION", 5, r)
    mov(bd, a, "BAJA", 1, r, de_fuera_de_servicio=True)
    assert cifras(bd, a, "existencia", "fuera_servicio", "disponible", "cantidad_registrada") == (9, 0, 9, 9)


def test_prestamo_mayor_a_lo_disponible_se_rechaza(taller):
    bd, r, d, a = taller
    mov(bd, a, "PRESTAMO", 8, d)
    with pytest.raises(Rechazo, match="Solo hay 2 disponibles"):
        mov(bd, a, "PRESTAMO", 3, d)


def test_prestamo_sin_conexion_en_conflicto_se_acepta_marcado(taller):
    """F-17: si el material salió en físico, se registra marcado aunque no alcance."""
    bd, r, d, a = taller
    mov(bd, a, "PRESTAMO", 10, d)
    mov(bd, a, "PRESTAMO", 1, d, conflicto=True, conflicto_motivo="Capturado sin conexión, no alcanzaba",
        origen="SIN_CONEXION")
    assert cifras(bd, a, "prestado", "disponible", "cuadra") == (11, -1, True)


def test_lo_apartado_por_solicitudes_aprobadas_no_se_puede_prestar(taller):
    bd, r, d, a = taller
    s = insertar(bd, "solicitud", solicitante_id=solicitante(bd), motivo="Proyecto",
                 fecha_devolucion_comprometida="2026-09-30", estado="APROBADA", autorizada_por=r)
    insertar(bd, "solicitud_linea", solicitud_id=s, articulo_id=a, cantidad=4)
    assert cifras(bd, a, "apartado", "disponible") == (4, 6)
    with pytest.raises(Rechazo, match="Solo hay 6 disponibles"):
        mov(bd, a, "PRESTAMO", 7, d)
    # La entrega de esa misma solicitud sí puede usar lo que tiene apartado.
    mov(bd, a, "PRESTAMO", 4, r, responsable_solicitante_id=bd.execute(
        "select solicitante_id from solicitud where id = %s", (s,)).fetchone()["solicitante_id"],
        responsable_usuario_id=None, solicitud_id=s, origen="SOLICITUD")
    bd.execute("update solicitud set estado = 'ENTREGADO' where id = %s", (s,))
    assert cifras(bd, a, "apartado", "prestado", "disponible") == (0, 4, 6)


def test_lo_retenido_por_una_incidencia_pendiente_no_se_presta(taller):
    bd, r, d, a = taller
    insertar(bd, "incidencia", articulo_id=a, tipo="DAÑO", cantidad=3, nota="Cable pelado",
             en_taller=True, reportada_por=d)
    assert cifras(bd, a, "existencia", "retenido", "disponible") == (10, 3, 7)
    with pytest.raises(Rechazo, match="Solo hay 7 disponibles"):
        mov(bd, a, "PRESTAMO", 8, d)


def test_ajuste_de_conteo_quita_la_marca_de_estimado(bd):
    r = usuario(bd)
    a = articulo(bd, "Destornilladores surtidos", cantidad_estimada=True, estado_inventario="POR_CONTAR")
    mov(bd, a, "ALTA", 17, r)
    mov(bd, a, "AJUSTE_CONTEO", -2, r, nota="Conteo físico: había 15")
    fila = bd.execute("select cantidad, cantidad_estimada from articulo where id = %s", (a,)).fetchone()
    assert (fila["cantidad"], fila["cantidad_estimada"]) == (15, False)
    assert cifras(bd, a, "existencia", "cuadra") == (15, True)


def test_ajuste_no_puede_contar_lo_que_esta_prestado(taller):
    bd, r, d, a = taller
    mov(bd, a, "PRESTAMO", 5, d)
    with pytest.raises(Rechazo, match="solo hay 5 en el taller"):
        mov(bd, a, "AJUSTE_CONTEO", -6, r)
    mov(bd, a, "AJUSTE_CONTEO", -5, r)
    assert cifras(bd, a, "existencia", "prestado", "en_taller") == (5, 5, 0)


def test_sin_conteo_no_se_presta_hasta_contarlo(bd):
    r = usuario(bd)
    a = articulo(bd, "Bandas dentadas", categoria="FTC", conteo_desconocido=True, cantidad_estimada=True,
                 estado_inventario="POR_CONTAR")
    assert existencias(bd, a)["prestable"] is False
    with pytest.raises(Rechazo, match="hasta contarlo"):
        mov(bd, a, "PRESTAMO", 1, r)
    mov(bd, a, "AJUSTE_CONTEO", 6, r, nota="Primer conteo")
    assert existencias(bd, a)["prestable"] is True
    mov(bd, a, "PRESTAMO", 1, r)
    assert cifras(bd, a, "existencia", "disponible") == (6, 5)


def test_sin_clasificar_no_se_presta(bd):
    r = usuario(bd)
    a = articulo(bd, "Caja de madera", categoria="SIN_CLASIFICAR")
    mov(bd, a, "ALTA", 1, r)
    with pytest.raises(Rechazo, match="definir si es VEX, FTC o común"):
        mov(bd, a, "PRESTAMO", 1, r)


def test_consumo_solo_en_consumibles(bd):
    r = usuario(bd)
    herramienta = articulo(bd)
    cinta = articulo(bd, "Cinta masking", categoria="CONSUMIBLES", es_consumible=True, unidad="rollo")
    mov(bd, herramienta, "ALTA", 3, r)
    mov(bd, cinta, "ALTA", 5, r)
    with pytest.raises(Rechazo, match="no es consumible"):
        mov(bd, herramienta, "CONSUMO", 1, r)
    mov(bd, cinta, "CONSUMO", 2, r)
    assert cifras(bd, cinta, "existencia", "disponible", "cantidad_registrada") == (3, 3, 3)


def test_articulo_dado_de_baja_no_acepta_movimientos(taller):
    bd, r, d, a = taller
    mov(bd, a, "BAJA", 10, r)
    bd.execute("update articulo set activo = false, estado_inventario = 'DADO_DE_BAJA' where id = %s", (a,))
    with pytest.raises(Rechazo, match="dado de baja"):
        mov(bd, a, "PRESTAMO", 1, d)


# ---------------------------------------------------------------------------
# Prueba de escenarios al azar contra un modelo en Python de la sección 1
# ---------------------------------------------------------------------------
class Modelo:
    def __init__(self):
        self.existencia = self.fuera = 0
        self.prestamos: dict = {}   # id -> pendiente

    @property
    def prestado(self):
        return sum(self.prestamos.values())

    @property
    def en_taller(self):
        return self.existencia - self.prestado - self.fuera


@pytest.mark.parametrize("semilla", range(5))
def test_escenarios_al_azar_coinciden_con_el_modelo(bd, semilla):
    rnd = random.Random(semilla)
    r = usuario(bd)
    a = articulo(bd, "Pieza de prueba")
    m = Modelo()

    for _ in range(120):
        op = rnd.choice(["ALTA", "PRESTAMO", "DEVOLUCION", "PERDIDA_PRESTADA", "DAÑO", "REPARACION", "AJUSTE", "BAJA"])
        q = rnd.randint(1, 6)
        abiertos = [p for p, pend in m.prestamos.items() if pend > 0]
        origen = rnd.choice(abiertos) if abiertos else None

        permitido = {
            "ALTA": True,
            "PRESTAMO": q <= m.en_taller,
            "DEVOLUCION": origen is not None and q <= m.prestamos.get(origen, 0),
            "PERDIDA_PRESTADA": origen is not None and q <= m.prestamos.get(origen, 0),
            "DAÑO": q <= m.en_taller,
            "REPARACION": q <= m.fuera,
            "AJUSTE": True,
            "BAJA": q <= m.en_taller,
        }[op]
        if op in ("DEVOLUCION", "PERDIDA_PRESTADA") and origen is None:
            continue
        ajuste = q if rnd.random() < 0.5 else -q
        if op == "AJUSTE":
            permitido = m.en_taller + ajuste >= 0

        try:
            match op:
                case "ALTA": mov(bd, a, "ALTA", q, r)
                case "PRESTAMO": nuevo = mov(bd, a, "PRESTAMO", q, r)
                case "DEVOLUCION": mov(bd, a, "DEVOLUCION", q, r, movimiento_origen_id=origen)
                case "PERDIDA_PRESTADA": mov(bd, a, "PERDIDA", q, r, movimiento_origen_id=origen)
                case "DAÑO": mov(bd, a, "DAÑO", q, r)
                case "REPARACION": mov(bd, a, "REPARACION", q, r)
                case "AJUSTE": mov(bd, a, "AJUSTE_CONTEO", ajuste, r)
                case "BAJA": mov(bd, a, "BAJA", q, r)
            aceptado = True
        except Rechazo:
            aceptado = False
        assert aceptado == permitido, f"{op} {q}: la base {'aceptó' if aceptado else 'rechazó'}"

        if aceptado:
            match op:
                case "ALTA": m.existencia += q
                case "PRESTAMO": m.prestamos[nuevo] = q
                case "DEVOLUCION": m.prestamos[origen] -= q
                case "PERDIDA_PRESTADA": m.prestamos[origen] -= q; m.existencia -= q
                case "DAÑO": m.fuera += q
                case "REPARACION": m.fuera -= q
                case "AJUSTE": m.existencia += ajuste
                case "BAJA": m.existencia -= q

        e = existencias(bd, a)
        assert (e["existencia"], e["prestado"], e["fuera_servicio"], e["disponible"]) == \
               (m.existencia, m.prestado, m.fuera, m.en_taller)
        assert e["cuadra"], "la cantidad guardada dejó de coincidir con los movimientos"
