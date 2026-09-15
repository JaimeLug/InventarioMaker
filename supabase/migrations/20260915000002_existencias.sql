-- =====================================================================
-- 0002 · Cálculo de existencias y validación de movimientos (Fase 1)
--
-- Implementa la sección 1 de docs/flujos.md:
--   Existencia        = ALTA + AJUSTE(±) − CONSUMO − PERDIDA − BAJA
--   Prestado          = PRESTAMO − DEVOLUCION − PERDIDA de lo prestado
--   Fuera de servicio = DAÑO − REPARACION − BAJA/PERDIDA de unidades dañadas
--   Apartado          = líneas de solicitudes APROBADAS
--   Retenido          = incidencias PENDIENTES sobre unidades en el taller
--   Disponible        = Existencia − Prestado − Fuera − Apartado − Retenido
-- =====================================================================

-- Totales que salen solo de los movimientos -----------------------------
create view public.v_mov_totales as
select
  articulo_id,
  sum(case when tipo in ('ALTA', 'AJUSTE_CONTEO') then cantidad
           when tipo in ('CONSUMO', 'PERDIDA', 'BAJA') then -cantidad
           else 0 end)::integer as existencia,
  sum(case when tipo = 'PRESTAMO' then cantidad
           when tipo = 'DEVOLUCION' then -cantidad
           when tipo = 'PERDIDA' and movimiento_origen_id is not null then -cantidad
           else 0 end)::integer as prestado,
  sum(case when tipo = 'DAÑO' then cantidad
           when tipo = 'REPARACION' then -cantidad
           when tipo in ('BAJA', 'PERDIDA') and de_fuera_de_servicio then -cantidad
           else 0 end)::integer as fuera_servicio
from public.movimiento
group by articulo_id;

create view public.v_apartado as
select l.articulo_id, sum(coalesce(l.cantidad_aprobada, l.cantidad))::integer as apartado
from public.solicitud_linea l
join public.solicitud s on s.id = l.solicitud_id
where s.estado = 'APROBADA'
group by l.articulo_id;

create view public.v_retenido as
select articulo_id, sum(cantidad)::integer as retenido
from public.incidencia
where estado = 'PENDIENTE' and en_taller
group by articulo_id;

-- Las cinco cifras de cada artículo -------------------------------------
create view public.v_existencias as
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
  (a.activo and a.estado_inventario <> 'SIN_CLASIFICAR' and not a.conteo_desconocido)
                                                         as prestable
from public.articulo a
left join public.v_mov_totales m on m.articulo_id = a.id
left join public.v_apartado ap  on ap.articulo_id = a.id
left join public.v_retenido r   on r.articulo_id = a.id;

create view public.v_descuadres as
select a.id as articulo_id, a.codigo, a.nombre, e.cantidad_registrada, e.existencia,
       coalesce(e.cantidad_registrada, 0) - e.existencia as diferencia
from public.v_existencias e
join public.articulo a on a.id = e.articulo_id
where not e.cuadra;
comment on view public.v_descuadres is
  'Artículos cuya cantidad guardada no coincide con la suma de movimientos. Debe estar vacía.';

-- Préstamos abiertos ----------------------------------------------------
create view public.v_prestamos_abiertos as
select
  p.id                              as prestamo_id,
  p.articulo_id,
  p.cantidad                        as cantidad_prestada,
  p.cantidad - coalesce(c.cerrado, 0) as pendiente,
  p.fecha,
  coalesce(p.fecha_compromiso, s.fecha_devolucion_comprometida,
           p.fecha + make_interval(days => app.config_int('dias_vencimiento'))) as vence_en,
  now() > coalesce(p.fecha_compromiso, s.fecha_devolucion_comprometida,
                   p.fecha + make_interval(days => app.config_int('dias_vencimiento'))) as vencido,
  p.responsable_usuario_id,
  p.responsable_solicitante_id,
  p.autorizado_por,
  p.solicitud_id,
  p.conflicto
from public.movimiento p
left join lateral (
  select sum(h.cantidad) as cerrado
  from public.movimiento h
  where h.movimiento_origen_id = p.id and h.tipo in ('DEVOLUCION', 'PERDIDA')
) c on true
left join public.solicitud s on s.id = p.solicitud_id
where p.tipo = 'PRESTAMO' and p.cantidad - coalesce(c.cerrado, 0) > 0;

-- ---------------------------------------------------------------------
-- Validación de cada movimiento (antes de guardarlo)
-- ---------------------------------------------------------------------
create function app.validar_movimiento() returns trigger
language plpgsql as $$
declare
  a            public.articulo%rowtype;
  o            public.movimiento%rowtype;
  v_exist      integer;
  v_prest      integer;
  v_fuera      integer;
  v_en_taller  integer;
  v_apartado   integer;
  v_retenido   integer;
  v_disponible integer;
  v_pendiente  integer;
begin
  -- Bloquea el artículo: los movimientos de un mismo artículo se aplican
  -- uno después del otro, nunca al mismo tiempo (F-17, regla 2).
  select * into a from public.articulo where id = new.articulo_id for update;
  if not found then
    raise exception 'El artículo no existe';
  end if;

  if not a.activo and new.tipo <> 'ALTA' and not new.conflicto then
    raise exception '"%" está dado de baja o desglosado', a.nombre;
  end if;

  select coalesce(existencia, 0), coalesce(prestado, 0), coalesce(fuera_servicio, 0)
    into v_exist, v_prest, v_fuera
    from public.v_mov_totales where articulo_id = new.articulo_id;
  v_exist := coalesce(v_exist, 0);
  v_prest := coalesce(v_prest, 0);
  v_fuera := coalesce(v_fuera, 0);
  v_en_taller := v_exist - v_prest - v_fuera;   -- en el taller y en servicio

  -- Devoluciones y pérdidas ligadas a un préstamo ------------------------
  if new.movimiento_origen_id is not null then
    select * into o from public.movimiento where id = new.movimiento_origen_id;
    if o.articulo_id <> new.articulo_id then
      raise exception 'El movimiento de origen es de otro artículo';
    end if;
    if new.tipo in ('DEVOLUCION', 'PERDIDA') then
      if o.tipo <> 'PRESTAMO' then
        raise exception 'Una % solo puede ligarse a un préstamo', lower(new.tipo::text);
      end if;
      select o.cantidad - coalesce(sum(h.cantidad), 0) into v_pendiente
        from public.movimiento h
        where h.movimiento_origen_id = o.id and h.tipo in ('DEVOLUCION', 'PERDIDA');
      if new.cantidad > v_pendiente then
        raise exception 'De ese préstamo solo quedan % pendientes', v_pendiente;
      end if;
    end if;
  end if;

  case new.tipo
    when 'REPARACION' then
      if new.cantidad > v_fuera then
        raise exception 'Solo hay % fuera de servicio', v_fuera;
      end if;

    when 'DAÑO' then
      if new.cantidad > v_en_taller then
        raise exception 'Solo hay % en el taller en servicio', v_en_taller;
      end if;

    when 'BAJA', 'PERDIDA' then
      if new.de_fuera_de_servicio then
        if new.cantidad > v_fuera then
          raise exception 'Solo hay % fuera de servicio', v_fuera;
        end if;
      elsif new.movimiento_origen_id is null and new.cantidad > v_en_taller then
        raise exception 'Solo hay % en el taller', v_en_taller;
      end if;

    when 'AJUSTE_CONTEO' then
      -- Solo se cuenta lo que está en el taller: lo prestado no se toca.
      if v_en_taller + new.cantidad < 0 then
        raise exception 'El ajuste dejaría el taller en %; solo hay % en el taller', v_en_taller + new.cantidad, v_en_taller;
      end if;

    when 'PRESTAMO', 'CONSUMO' then
      if new.tipo = 'CONSUMO' and not a.es_consumible then
        raise exception '"%" no es consumible: se presta, no se consume', a.nombre;
      end if;
      if not new.conflicto then
        if a.estado_inventario = 'SIN_CLASIFICAR' then
          raise exception '"%" no se puede prestar hasta definir si es VEX, FTC o común', a.nombre;
        end if;
        if a.conteo_desconocido then
          raise exception '"%" no se puede prestar hasta contarlo', a.nombre;
        end if;
        -- Lo apartado por la propia solicitud que se entrega no cuenta en contra,
        -- ni lo retenido por la propia incidencia que se confirma.
        select coalesce(sum(coalesce(l.cantidad_aprobada, l.cantidad)), 0) into v_apartado
          from public.solicitud_linea l join public.solicitud s on s.id = l.solicitud_id
          where s.estado = 'APROBADA' and l.articulo_id = new.articulo_id
            and s.id is distinct from new.solicitud_id;
        select coalesce(sum(i.cantidad), 0) into v_retenido
          from public.incidencia i
          where i.estado = 'PENDIENTE' and i.en_taller and i.articulo_id = new.articulo_id
            and i.id is distinct from new.incidencia_id;
        v_disponible := v_en_taller - v_apartado - v_retenido;
        if new.cantidad > v_disponible then
          raise exception 'Solo hay % disponibles de "%"', greatest(v_disponible, 0), a.nombre;
        end if;
      end if;

    else
      null;
  end case;

  return new;
end $$;

create trigger validar before insert on public.movimiento
  for each row execute function app.validar_movimiento();

-- ---------------------------------------------------------------------
-- Después de guardar: actualiza la copia de la cantidad en el artículo
-- ---------------------------------------------------------------------
create function app.aplicar_movimiento() returns trigger
language plpgsql as $$
declare
  delta integer := case
    when new.tipo in ('ALTA', 'AJUSTE_CONTEO') then new.cantidad
    when new.tipo in ('CONSUMO', 'PERDIDA', 'BAJA') then -new.cantidad
    else 0 end;
begin
  if delta = 0 and new.tipo <> 'AJUSTE_CONTEO' then
    return new;
  end if;

  perform set_config('app.cambio_cantidad', 'si', true);
  update public.articulo
     set cantidad = coalesce(cantidad, 0) + delta,
         -- Un ajuste es un conteo físico: la cantidad deja de ser estimada.
         cantidad_estimada  = case when new.tipo = 'AJUSTE_CONTEO' then false else cantidad_estimada end,
         conteo_desconocido = case when new.tipo = 'AJUSTE_CONTEO' then false else conteo_desconocido end
   where id = new.articulo_id;
  perform set_config('app.cambio_cantidad', 'no', true);
  return new;
end $$;

create trigger aplicar after insert on public.movimiento
  for each row execute function app.aplicar_movimiento();

-- ---------------------------------------------------------------------
-- Vistas de consulta
-- ---------------------------------------------------------------------
create function app.ruta_contenedor(p_id uuid) returns text
language sql stable security definer set search_path = public as $$
  with recursive r as (
    select id, nombre, padre_id, 1 as nivel from public.contenedor where id = p_id
    union all
    select c.id, c.nombre, c.padre_id, r.nivel + 1
    from public.contenedor c join r on c.id = r.padre_id
    where r.nivel < 20
  )
  select string_agg(nombre, ' › ' order by nivel desc) from r
$$;

-- Lo que ve cualquiera, sin sesión. No incluye nombres de personas.
create view public.v_inventario as
select
  a.id, a.codigo, a.ref_foto, a.nombre, a.marca_modelo, a.categoria, a.subcategoria, a.unidad,
  a.cantidad_texto, a.cantidad_estimada, a.conteo_desconocido,
  a.estado_inventario, a.estado_fisico, a.estado_fisico_texto, a.etiquetado,
  a.contenedor_id, c.codigo as contenedor_codigo, app.ruta_contenedor(a.contenedor_id) as ubicacion_ruta,
  a.ubicacion as ubicacion_texto, a.num_resguardo, a.num_serie, a.observaciones,
  a.es_consumible, a.minimo_reposicion, a.activo,
  e.existencia, e.prestado, e.fuera_servicio, e.apartado, e.retenido, e.en_taller, e.disponible, e.prestable,
  (select min(pa.vence_en) from public.v_prestamos_abiertos pa where pa.articulo_id = a.id) as prestado_hasta,
  (select count(*) from public.tarea_pendiente t where t.articulo_id = a.id and not t.resuelta)::integer
    as pendientes_abiertos,
  f.url as foto_principal_url,
  a.version, a.actualizado_en
from public.articulo a
join public.v_existencias e on e.articulo_id = a.id
left join public.contenedor c on c.id = a.contenedor_id
left join public.foto f on f.articulo_id = a.id and f.es_principal;

-- Historial sin nombres ni notas (las notas pueden traer nombres).
create view public.v_historial_publico as
select m.id, m.articulo_id, m.tipo, m.cantidad, m.fecha,
       case when m.tipo = 'PRESTAMO' then pa.vence_en end as prestado_hasta
from public.movimiento m
left join public.v_prestamos_abiertos pa on pa.prestamo_id = m.id;

-- Equivalente a la hoja "Resumen" del Excel.
create view public.v_resumen_categoria as
select
  a.categoria,
  count(*) filter (where a.activo)::integer                                     as articulos,
  count(*) filter (where a.activo and exists (
    select 1 from public.tarea_pendiente t where t.articulo_id = a.id and not t.resuelta))::integer
                                                                                as con_pendientes,
  count(*) filter (where a.activo and a.cantidad_estimada)::integer             as estimados,
  count(*) filter (where a.activo and a.conteo_desconocido)::integer            as sin_conteo,
  count(*) filter (where a.activo and a.estado_inventario = 'VERIFICADO')::integer as verificados,
  coalesce(sum(e.prestado) filter (where a.activo), 0)::integer                 as piezas_prestadas
from public.articulo a
join public.v_existencias e on e.articulo_id = a.id
group by a.categoria;
