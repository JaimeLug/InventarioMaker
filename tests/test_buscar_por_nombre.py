"""Fase 10 (migración 0015): buscar por nombre solo a quien ya pasó por el taller."""
from datetime import datetime, timedelta, timezone

import psycopg
import pytest

from ayudantes import como, insertar, mov, rpc, usuario


@pytest.fixture
def lab(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    taladro = insertar(bd, "articulo", nombre="Taladro", categoria="HERRAMIENTAS_ELECTRICAS")
    mov(bd, taladro, "ALTA", 2, r)
    # Ya pidió prestado antes
    conocido = insertar(bd, "solicitante", nombre_completo="José Rodríguez Canché", tipo="ALUMNO",
                        matricula_o_clave="23-0100", grupo_area="5°B")
    with como(bd, r):
        rpc(bd, "prestamo_registrar", p_lineas=psycopg.types.json.Jsonb([{"articulo_id": str(taladro), "cantidad": 1}]),
            p_responsable_solicitante=conocido, p_responsable_usuario=None,
            p_fecha_compromiso=datetime.now(timezone.utc) + timedelta(hours=3), p_nota=None, p_comando=None)
    # Nunca ha pedido nada
    nuevo = insertar(bd, "solicitante", nombre_completo="José Martín Uc", tipo="ALUMNO",
                     matricula_o_clave="23-0200", grupo_area="5°A")
    return dict(bd=bd, r=r, conocido=conocido, nuevo=nuevo)


def buscar(bd, yo, texto):
    """Como la app: la función devuelve una tabla, así que se consulta con select *."""
    with como(bd, yo):
        return bd.execute("select * from public.solicitante_buscar_conocido(%s)", (texto,)).fetchall()


def test_encuentra_a_quien_ya_paso_por_el_taller(lab):
    filas = buscar(lab["bd"], lab["r"], "jose rodriguez")
    assert [f["nombre_completo"] for f in filas] == ["José Rodríguez Canché"]
    assert filas[0]["matricula_o_clave"] == "23-0100"


def test_no_encuentra_a_un_alumno_que_nunca_ha_pedido(lab):
    assert buscar(lab["bd"], lab["r"], "martin uc") == []


def test_ignora_acentos_y_mayusculas(lab):
    assert len(buscar(lab["bd"], lab["r"], "RODRIGUEZ")) == 1
    assert len(buscar(lab["bd"], lab["r"], "Rodríguez")) == 1


def test_pide_al_menos_tres_letras(lab):
    with pytest.raises(psycopg.errors.RaiseException, match="3 letras"):
        buscar(lab["bd"], lab["r"], "jo")


def test_queda_anotado_en_la_bitacora(lab):
    buscar(lab["bd"], lab["r"], "rodriguez")
    fila = lab["bd"].execute(
        "select datos from public.bitacora where evento = 'BUSQUEDA_POR_NOMBRE' order by en desc limit 1").fetchone()
    assert fila["datos"]["texto"] == "rodriguez"
    assert fila["datos"]["encontrados"] == 1


def test_un_visitante_sin_sesion_no_puede_buscar(lab):
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with como(lab["bd"], None):
            lab["bd"].execute("select * from public.solicitante_buscar_conocido(%s)", ("rodriguez",)).fetchall()
