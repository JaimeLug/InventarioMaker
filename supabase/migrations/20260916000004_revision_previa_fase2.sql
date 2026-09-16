-- =====================================================================
-- 0004 · Revisión de la base antes de la Fase 2
--
--   1. Fotos: sin sesión solo se ven las del catálogo.
--   2. Códigos internos sin Ñ: DAÑO -> DANO, DAÑADO -> DANADO.
--      (En pantalla sigue diciendo "Daño"; esto evita errores en Flutter y en la API web.)
--   3. El respaldo es un script aparte: scripts/respaldo.py.
--   4. Funciones internas con search_path fijo (lo marca el asesor de seguridad de Supabase).
--   5. Zona horaria de Mérida para vencimientos, jornada y días hábiles.
--   6. Índices para las consultas frecuentes (adeudos, solicitudes, incidencias).
--   7. Vistas internas de cálculo al esquema app (fuera de la API).
--   +  Portabilidad: las fotos guardan rutas relativas, no direcciones completas,
--      para poder mudar el almacén de archivos sin reescribir datos.
-- =====================================================================

-- 2. Códigos sin Ñ ------------------------------------------------------
-- Las vistas y restricciones guardan el valor por referencia y se actualizan solas;
-- las funciones guardan texto, por eso validar_movimiento se vuelve a crear abajo.
alter type public.tipo_movimiento rename value 'DAÑO' to 'DANO';
alter type public.tipo_foto       rename value 'DAÑO' to 'DANO';
alter type public.tipo_incidencia rename value 'DAÑO' to 'DANO';
alter type public.estado_fisico   rename value 'DAÑADO' to 'DANADO';

-- 7. Vistas internas fuera de la API --------------------------------------
alter view public.v_mov_totales        set schema app;
alter view public.v_apartado           set schema app;
alter view public.v_retenido           set schema app;
alter view public.v_prestamos_abiertos set schema app;
alter view public.v_descuadres         set schema app;

-- 4. search_path fijo -----------------------------------------------------
-- Con search_path vacío, todo lo que no sea del sistema debe ir con su esquema;
-- las funciones ya lo hacen. Las pruebas ejercitan cada una.
alter function app.tocar()                      set search_path = '';
alter function app.versionar()                  set search_path = '';
alter function app.prohibir_borrado()           set search_path = '';
alter function app.prohibir_edicion()           set search_path = '';
alter function app.proteger_cantidad()          set search_path = '';
alter function app.validar_categoria_articulo() set search_path = '';
alter function app.validar_contenedor()         set search_path = '';
alter function app.aplicar_movimiento()         set search_path = '';

create or replace function app.validar_movimiento() returns trigger
language plpgsql set search_path = '' as $$
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
    from app.v_mov_totales where articulo_id = new.articulo_id;
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

    when 'DANO' then
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

-- 1. Fotos privadas -------------------------------------------------------
-- Sin sesión (y por ahora con sesión, hasta la Fase 2) solo las fotos del catálogo.
-- Las de solicitudes (entrega, credencial), incidencias y movimientos se verán
-- únicamente a través de funciones que revisen el rol.
drop policy lectura_publica on public.foto;
create policy lectura_publica on public.foto for select to anon, authenticated
  using (solicitud_id is null and incidencia_id is null and movimiento_id is null);

-- + Rutas relativas -------------------------------------------------------
alter table public.foto        add constraint foto_url_relativa            check (url !~* '^[a-z][a-z0-9+.-]*://');
alter table public.contenedor  add constraint contenedor_foto_url_relativa check (foto_url !~* '^[a-z][a-z0-9+.-]*://');
alter table public.movimiento  add constraint movimiento_foto_url_relativa check (foto_url !~* '^[a-z][a-z0-9+.-]*://');
alter table public.solicitud   add constraint solicitud_firma_url_relativa check (firma_url !~* '^[a-z][a-z0-9+.-]*://');
alter table public.solicitud   add constraint solicitud_foto_entrega_relativa check (foto_entrega_url !~* '^[a-z][a-z0-9+.-]*://');

comment on column public.foto.url is
  'Ruta dentro del almacén de archivos (ej. articulos/A-0101/2026-09-16_ab12.jpg), nunca la dirección completa: así se puede mudar el almacén sin reescribir datos.';

-- 5. Zona horaria ---------------------------------------------------------
insert into public.configuracion (clave, valor, descripcion)
values ('zona_horaria', '"America/Merida"', 'Zona horaria para vencimientos, jornada y días hábiles')
on conflict (clave) do nothing;

create function app.zona_horaria() returns text
language sql stable set search_path = '' as $$
  select coalesce((select valor #>> '{}' from public.configuracion where clave = 'zona_horaria'), 'America/Merida')
$$;

create function app.hoy() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone app.zona_horaria())::date
$$;
comment on function app.hoy() is 'La fecha de hoy en Mérida. Las fechas se guardan en UTC; los cálculos por día usan esta.';

revoke execute on function app.zona_horaria(), app.hoy() from public;
grant execute on function app.zona_horaria(), app.hoy() to anon, authenticated;

-- 6. Índices ---------------------------------------------------------------
create index movimiento_resp_solicitante_idx on public.movimiento (responsable_solicitante_id) where responsable_solicitante_id is not null;
create index movimiento_resp_usuario_idx     on public.movimiento (responsable_usuario_id) where responsable_usuario_id is not null;
create index movimiento_solicitud_idx        on public.movimiento (solicitud_id) where solicitud_id is not null;
create index movimiento_prestamos_idx        on public.movimiento (articulo_id) where tipo = 'PRESTAMO';
create index solicitud_solicitante_idx       on public.solicitud (solicitante_id);
create index solicitud_abiertas_idx          on public.solicitud (estado) where estado in ('PENDIENTE', 'APROBADA', 'ENTREGADO', 'VENCIDA');
create index solicitud_linea_articulo_idx    on public.solicitud_linea (articulo_id);
create index incidencia_articulo_idx         on public.incidencia (articulo_id);
create index incidencia_prestamo_idx         on public.incidencia (prestamo_id) where prestamo_id is not null;
create index contenedor_padre_idx            on public.contenedor (padre_id) where padre_id is not null;
create index conteo_linea_inventario_idx     on public.conteo_linea (inventario_id, articulo_id);
create index foto_contenedor_idx             on public.foto (contenedor_id) where contenedor_id is not null;

-- Documentación de lo que el asesor de Supabase marca pero es a propósito --------
comment on view public.v_inventario is
  'Catálogo público. A propósito corre con permisos del dueño (el asesor de Supabase lo marca como "security definer view"): así muestra disponibilidad sin exponer los movimientos con nombres de personas.';
comment on view public.v_existencias is
  'Cifras por artículo. Mismo criterio que v_inventario: corre con permisos del dueño a propósito.';
comment on view public.v_historial_publico is
  'Historial sin nombres ni notas. Corre con permisos del dueño a propósito.';
comment on view public.v_resumen_categoria is
  'Equivalente a la hoja Resumen del Excel. Corre con permisos del dueño a propósito.';
