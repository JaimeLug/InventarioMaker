"""Revisión previa a la Fase 2 (migración 0004) y respaldo/restauración."""
import uuid
from pathlib import Path

import psycopg
import pytest
from psycopg.rows import dict_row

import respaldo
from ayudantes import articulo, existencias, insertar, mov, solicitante, usuario
from import_excel import importar
from inventario_excel import leer_excel

EXCEL = Path(__file__).resolve().parent.parent / "InventarioRobotica1erFaltaVerificarCant.xlsx"


def test_sin_sesion_solo_se_ven_las_fotos_del_catalogo(bd):
    r = usuario(bd)
    a = articulo(bd)
    s = insertar(bd, "solicitud", solicitante_id=solicitante(bd), motivo="Proyecto",
                 fecha_devolucion_comprometida="2026-09-30", estado="APROBADA", autorizada_por=r)
    insertar(bd, "foto", articulo_id=a, url="articulos/A-1001/principal.jpg", es_principal=True)
    insertar(bd, "foto", articulo_id=a, solicitud_id=s, url="solicitudes/LM-0001/credencial.jpg", tipo="ENTREGA")
    with bd.transaction():
        bd.execute("set local role anon")
        visibles = [f["url"] for f in bd.execute("select url from foto").fetchall()]
    assert visibles == ["articulos/A-1001/principal.jpg"]


def test_las_fotos_guardan_rutas_no_direcciones(bd):
    a = articulo(bd)
    with pytest.raises(psycopg.errors.CheckViolation):
        insertar(bd, "foto", articulo_id=a, url="https://eirouznbikpvnuhdmbnm.supabase.co/storage/v1/x.jpg")


def test_codigos_internos_sin_enie(bd):
    raros = bd.execute(r"""select t.typname || '.' || e.enumlabel as v from pg_enum e
                           join pg_type t on t.oid = e.enumtypid
                           where t.typnamespace = 'public'::regnamespace and e.enumlabel ~ '[^\x01-\x7F]'""").fetchall()
    assert raros == []


def test_funciones_internas_con_search_path_fijo(bd):
    sueltas = bd.execute("""select p.proname from pg_proc p
                            where p.pronamespace = 'app'::regnamespace
                              and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c
                                              where c like 'search_path=%')""").fetchall()
    assert sueltas == []


def test_vistas_internas_fuera_de_la_api(bd):
    publicas = {r["viewname"] for r in bd.execute("select viewname from pg_views where schemaname = 'public'").fetchall()}
    assert publicas == {"v_inventario", "v_existencias", "v_historial_publico", "v_resumen_categoria", "v_contenedores"}


def test_hoy_es_la_fecha_de_merida(bd):
    fila = bd.execute("select app.hoy() = (now() at time zone 'America/Merida')::date as ok").fetchone()
    assert fila["ok"]


def test_el_dano_sigue_validandose_con_el_codigo_nuevo(bd):
    r = usuario(bd)
    a = articulo(bd)
    mov(bd, a, "ALTA", 2, r)
    mov(bd, a, "DANO", 1, r)
    with pytest.raises(psycopg.errors.RaiseException, match="Solo hay 1 en el taller en servicio"):
        mov(bd, a, "DANO", 2, r)
    assert existencias(bd, a)["fuera_servicio"] == 1


# ---------------------------------------------------------------------------
# Respaldo y restauración: la ruta para mudarse a otro servidor
# ---------------------------------------------------------------------------
def test_respaldo_y_restauracion_en_una_base_nueva(cluster, url_base, tmp_path):
    with psycopg.connect(url_base, autocommit=True, row_factory=dict_row) as bd:
        importar(bd, leer_excel(EXCEL))
        r = usuario(bd, nombre="Jaime Lugo")
        multimetro = bd.execute("select id from articulo where ref_foto = 101").fetchone()["id"]
        p = mov(bd, multimetro, "PRESTAMO", 1, r)
        mov(bd, multimetro, "DEVOLUCION", 1, r, movimiento_origen_id=p)
        insertar(bd, "foto", articulo_id=multimetro, url="articulos/A-0101/principal.jpg", es_principal=True)
        with bd.transaction():
            bd.execute("select set_config('app.justificacion', 'Prueba de bitácora', true)")
            bd.execute("update articulo set observaciones = 'Revisado' where id = %s", (multimetro,))
        antes = bd.execute("select * from v_existencias order by articulo_id").fetchall()

    with psycopg.connect(url_base) as conn:
        archivo = respaldo.crear(conn, tmp_path, "prueba")

    nombre = f"restaurada_{uuid.uuid4().hex[:8]}"
    cluster.crear_base(nombre)
    try:
        with psycopg.connect(cluster.url(nombre)) as conn:
            resultado = respaldo.restaurar(conn, archivo, es_supabase=False)
        assert resultado["migraciones_posteriores"] == []

        with psycopg.connect(cluster.url(nombre), autocommit=True, row_factory=dict_row) as bd:
            assert bd.execute("select * from v_existencias order by articulo_id").fetchall() == antes
            assert bd.execute("select count(*) as n from bitacora").fetchone()["n"] == 1
            assert bd.execute("select nombre from usuario").fetchone()["nombre"] == "Jaime Lugo"

            # Después de restaurar, las reglas siguen vivas y las secuencias no chocan.
            mov(bd, multimetro, "PRESTAMO", 1, r)
            with pytest.raises(psycopg.errors.RaiseException, match="Solo hay 0 disponibles"):
                mov(bd, multimetro, "PRESTAMO", 1, r)
            nuevo = articulo(bd, "Artículo nuevo después de restaurar")
            assert bd.execute("select codigo from articulo where id = %s", (nuevo,)).fetchone()["codigo"] == "A-1001"
            bd.execute("insert into bitacora (evento) values ('prueba')")
            assert bd.execute("select count(*) as n from app.v_descuadres").fetchone()["n"] == 0

            # No se restaura encima de datos existentes.
            with pytest.raises(ValueError, match="ya tiene artículos"):
                respaldo.restaurar(bd, archivo, es_supabase=False)
    finally:
        with psycopg.connect(cluster.url("postgres"), autocommit=True) as conn:
            conn.execute(f'drop database "{nombre}" with (force)')


def test_el_respaldo_incluye_fotos_pero_nunca_identificaciones(url_base, tmp_path):
    import zipfile
    with psycopg.connect(url_base, autocommit=True, row_factory=dict_row) as bd:
        for almacen, ruta in (("fotos", "articulos/a1/principal.jpg"), ("privado", "incidencias/i1/dano.jpg"),
                              ("privado", "identificaciones/s1/credencial.jpg")):
            bd.execute("insert into storage.objects (bucket_id, name) values (%s, %s)", (almacen, ruta))
    pedidos = []

    def descargar(almacen, ruta):
        pedidos.append(ruta)
        return b"jpg"

    with psycopg.connect(url_base) as conn:
        archivo = respaldo.crear(conn, tmp_path, "prueba", descargar)
    nombres = zipfile.ZipFile(archivo).namelist()
    assert "archivos/fotos/articulos/a1/principal.jpg" in nombres
    assert "archivos/privado/incidencias/i1/dano.jpg" in nombres
    assert not any("identificaciones" in n for n in nombres)
    assert "identificaciones/s1/credencial.jpg" not in pedidos        # ni siquiera se descarga
