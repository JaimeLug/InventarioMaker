-- =====================================================================
-- 0011 · Artículos que no se prestan
--
-- Algunas cosas se inventarían pero no salen del laboratorio: empaques vacíos (las cajas de Driver Hub),
-- el campo de competencia, equipo fijo. Quedan en el inventario con su existencia, pero no se prestan
-- ni se piden. Lo marca responsable o sub administración con un motivo.
-- =====================================================================

alter table public.articulo
  add column no_se_presta        boolean not null default false,
  add column no_se_presta_motivo text,
  add constraint articulo_no_se_presta_motivo check (not no_se_presta or btrim(coalesce(no_se_presta_motivo, '')) <> '');

create or replace view public.v_existencias as
select
  a.id                                                   as articulo_id,
  coalesce(m.existencia, 0)                              as existencia,
  coalesce(m.prestado, 0)                                as prestado,
  coalesce(m.fuera_servicio, 0)                          as fuera_servicio,
  coalesce(ap.apartado, 0)                               as apartado,
  coalesce(r.retenido, 0)                                as retenido,
  coalesce(m.existencia, 0) - coalesce(m.prestado, 0) - coalesce(m.fuera_servicio, 0)
                                                         as en_taller,
  coalesce(m.existencia, 0) - coalesce(m.prestado, 0) - coalesce(m.fuera_servicio, 0)
    - coalesce(ap.apartado, 0) - coalesce(r.retenido, 0) as disponible,
  a.cantidad                                             as cantidad_registrada,
  coalesce(a.cantidad, 0) = coalesce(m.existencia, 0)    as cuadra,
  (a.activo and a.estado_inventario <> 'SIN_CLASIFICAR' and not a.conteo_desconocido and not a.no_se_presta)
                                                         as prestable
from public.articulo a
left join app.v_mov_totales m on m.articulo_id = a.id
left join app.v_apartado ap  on ap.articulo_id = a.id
left join app.v_retenido r   on r.articulo_id = a.id;

-- El préstamo lo valida también la base, no solo la pantalla.
create function app.validar_no_se_presta() returns trigger
language plpgsql set search_path = '' as $$
declare
  a public.articulo;
begin
  if new.tipo = 'PRESTAMO' and not new.conflicto then
    select * into a from public.articulo where id = new.articulo_id;
    if a.no_se_presta then
      raise exception '"%" no se presta: %', a.nombre, a.no_se_presta_motivo;
    end if;
  end if;
  return new;
end $$;
create trigger no_se_presta before insert on public.movimiento for each row execute function app.validar_no_se_presta();

create function public.articulo_marcar_prestable(p_articulo uuid, p_prestable boolean, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  if not p_prestable and btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué no se presta.';
  end if;
  update public.articulo
     set no_se_presta = not p_prestable, no_se_presta_motivo = case when p_prestable then null else btrim(p_motivo) end
   where id = p_articulo;
  if not found then
    raise exception 'El artículo no existe.';
  end if;
end $$;

-- Un kit que se queda como empaque vacío tampoco se presta.
create function app.empaque_no_se_presta() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'TERMINADO' and new.destino = 'EMPAQUE' then
    update public.articulo set no_se_presta = true, no_se_presta_motivo = 'Empaque vacío: su contenido se desglosó'
     where id = new.articulo_id and not no_se_presta;
  end if;
  return null;
end $$;
create trigger empaque after update of estado on public.desglose for each row execute function app.empaque_no_se_presta();

-- El catálogo público muestra si se presta y por qué no.
create or replace view public.v_inventario as
select
  a.id, a.codigo, a.ref_foto, a.nombre, a.marca_modelo, a.categoria, a.subcategoria, a.unidad,
  a.cantidad_texto, a.cantidad_estimada, a.conteo_desconocido,
  a.estado_inventario, a.estado_fisico, a.estado_fisico_texto, a.etiquetado,
  a.contenedor_id, c.codigo as contenedor_codigo, app.ruta_contenedor(a.contenedor_id) as ubicacion_ruta,
  a.ubicacion as ubicacion_texto, a.num_resguardo, a.num_serie, a.observaciones,
  a.es_consumible, a.minimo_reposicion, a.activo,
  e.existencia, e.prestado, e.fuera_servicio, e.apartado, e.retenido, e.en_taller, e.disponible, e.prestable,
  (select min(pa.vence_en) from app.v_prestamos_abiertos pa where pa.articulo_id = a.id) as prestado_hasta,
  (select count(*) from public.tarea_pendiente t where t.articulo_id = a.id and not t.resuelta)::integer
    as pendientes_abiertos,
  f.url as foto_principal_url,
  a.version, a.actualizado_en,
  a.baja_oficio,
  (not a.activo and a.estado_inventario = 'DADO_DE_BAJA' and a.num_resguardo is not null and a.baja_oficio is null)
    as baja_en_tramite,
  a.no_se_presta,
  a.no_se_presta_motivo
from public.articulo a
join public.v_existencias e on e.articulo_id = a.id
left join public.contenedor c on c.id = a.contenedor_id
left join public.foto f on f.articulo_id = a.id and f.es_principal;

grant select on public.v_inventario, public.v_existencias to anon, authenticated;
revoke execute on function app.validar_no_se_presta(), app.empaque_no_se_presta() from public;
revoke all on function public.articulo_marcar_prestable(uuid, boolean, text) from public, anon, authenticated, service_role;
grant execute on function public.articulo_marcar_prestable(uuid, boolean, text) to authenticated;
