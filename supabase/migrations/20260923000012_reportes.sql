-- =====================================================================
-- 0012 · Reportes, Excel para Contraloría, actas y faltantes de kits (Fase 5)
--
-- Los documentos (Excel y PDF) se arman en el dispositivo: aquí solo están los datos, con nombres de personas
-- solo para responsable y sub administración, y el registro de quién generó qué (bitácora, folio de actas).
-- Nada de lo generado se guarda en el servidor.
--
-- Decisiones de la Fase 5 (aprobadas el 2026-09-17):
--   * Datos de alumnos en reportes: nombre, matrícula y grupo. Nunca teléfono, correo ni identificaciones.
--   * Encabezado: Escuela Preparatoria Número 13 · Programa Renacimiento Maya · Laboratorio Maker.
--   * Faltantes de kits: además del desglose, una "revisión de kit" (como las hojas BOM del Excel) que compara
--     lo esperado de N kits contra lo encontrado, sin mover el inventario.
-- =====================================================================

insert into public.configuracion (clave, valor, descripcion) values
  ('nombre_escuela',     '"Escuela Preparatoria Número 13"', 'Nombre oficial de la escuela, para el encabezado de los reportes'),
  ('programa_escuela',   '"Programa Renacimiento Maya"',     'Programa, para el encabezado de los reportes'),
  ('nombre_laboratorio', '"Laboratorio Maker"',              'Nombre del laboratorio, para el encabezado de los reportes'),
  ('logo_url',           'null',                             'Ruta del logo oficial en el almacén de fotos (cuando lo haya)')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------------
-- Revisión de kit: lo esperado de fábrica contra lo encontrado (no mueve existencias)
-- ---------------------------------------------------------------------
create table public.revision_kit (
  id              uuid primary key default gen_random_uuid(),
  plantilla_id    uuid not null references public.plantilla_kit (id),
  nombre          text not null check (btrim(nombre) <> ''),
  kits            integer not null check (kits > 0),
  articulo_id     uuid references public.articulo (id),
  nota            text,
  creada_por      uuid references public.usuario (id),
  creada_en       timestamptz not null default now(),
  actualizada_por uuid references public.usuario (id),
  actualizada_en  timestamptz not null default now()
);

create table public.revision_kit_linea (
  revision_id         uuid not null references public.revision_kit (id),
  plantilla_linea_id  uuid not null references public.plantilla_kit_linea (id),
  encontrada          integer check (encontrada is null or encontrada >= 0),
  no_aplica           boolean not null default false,
  nota                text,
  primary key (revision_id, plantilla_linea_id)
);

do $$
declare
  t text;
begin
  foreach t in array array['revision_kit', 'revision_kit_linea'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('create trigger sin_borrado before delete on public.%I for each row execute function app.prohibir_borrado()', t);
  end loop;
end $$;

create function app.revision_kit_json(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'nombre', r.nombre, 'kits', r.kits, 'nota', r.nota,
    'plantilla', jsonb_build_object('id', p.id, 'nombre', p.nombre, 'sku', p.sku, 'categoria', p.categoria),
    'articulo', (select jsonb_build_object('id', a.id, 'codigo', a.codigo, 'nombre', a.nombre) from public.articulo a where a.id = r.articulo_id),
    'actualizada_por', app.nombre_usuario(r.actualizada_por), 'actualizada_en', r.actualizada_en,
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                 'plantilla_linea_id', l.id, 'seccion', l.seccion, 'sku', l.sku, 'descripcion', l.descripcion, 'unidad', l.unidad,
                 'por_kit', l.cantidad, 'esperada', l.cantidad * r.kits, 'nota_plantilla', l.nota,
                 'encontrada', x.encontrada, 'no_aplica', coalesce(x.no_aplica, false), 'nota', x.nota)
               order by l.orden), '[]'::jsonb)
               from public.plantilla_kit_linea l
               left join public.revision_kit_linea x on x.revision_id = r.id and x.plantilla_linea_id = l.id
               where l.plantilla_id = r.plantilla_id))
  from public.revision_kit r join public.plantilla_kit p on p.id = r.plantilla_id
  where r.id = p_id
$$;

create function public.revision_kit_crear(p_plantilla uuid, p_kits integer, p_nombre text default null, p_articulo uuid default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  p     public.plantilla_kit;
  nueva uuid;
begin
  select * into p from public.plantilla_kit where id = p_plantilla;
  if not found then
    raise exception 'La lista de contenido no existe.';
  end if;
  if p_kits is null or p_kits < 1 then
    raise exception '¿Cuántos kits se compraron? Al menos 1.';
  end if;
  insert into public.revision_kit (plantilla_id, nombre, kits, articulo_id, creada_por, actualizada_por)
  values (p_plantilla, coalesce(nullif(btrim(p_nombre), ''), p.nombre), p_kits, p_articulo, yo.id, yo.id)
  returning id into nueva;
  return app.revision_kit_json(nueva);
end $$;

-- p_lineas: [{plantilla_linea_id, encontrada, no_aplica, nota}]
create function public.revision_kit_guardar(p_id uuid, p_kits integer, p_lineas jsonb, p_nota text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  r  public.revision_kit;
  l  jsonb;
begin
  select * into r from public.revision_kit where id = p_id for update;
  if not found then
    raise exception 'La revisión no existe.';
  end if;
  if p_kits is null or p_kits < 1 then
    raise exception '¿Cuántos kits se compraron? Al menos 1.';
  end if;
  for l in select * from jsonb_array_elements(coalesce(p_lineas, '[]'::jsonb)) loop
    if not exists (select 1 from public.plantilla_kit_linea x where x.id = (l ->> 'plantilla_linea_id')::uuid and x.plantilla_id = r.plantilla_id) then
      raise exception 'Un renglón no pertenece a la lista de este kit.';
    end if;
    insert into public.revision_kit_linea (revision_id, plantilla_linea_id, encontrada, no_aplica, nota)
    values (p_id, (l ->> 'plantilla_linea_id')::uuid, (l ->> 'encontrada')::integer, coalesce((l ->> 'no_aplica')::boolean, false),
            nullif(btrim(l ->> 'nota'), ''))
    on conflict (revision_id, plantilla_linea_id) do update
      set encontrada = excluded.encontrada, no_aplica = excluded.no_aplica, nota = excluded.nota;
  end loop;
  update public.revision_kit set kits = p_kits, nota = nullif(btrim(p_nota), ''), actualizada_por = yo.id, actualizada_en = now() where id = p_id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'REVISION_KIT', 'revision_kit', p_id::text, jsonb_build_object('kits', p_kits, 'renglones', jsonb_array_length(coalesce(p_lineas, '[]'::jsonb))));
  return app.revision_kit_json(p_id);
end $$;

create function public.revision_kit_detalle(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return app.revision_kit_json(p_id);
end $$;

create function public.revisiones_kit()
returns table (id uuid, nombre text, plantilla text, kits integer, renglones integer, revisados integer, con_faltante integer,
               actualizada_en timestamptz, actualizada_por text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select r.id, r.nombre, p.nombre, r.kits,
           (select count(*)::integer from public.plantilla_kit_linea l where l.plantilla_id = r.plantilla_id),
           (select count(*)::integer from public.revision_kit_linea x where x.revision_id = r.id and (x.encontrada is not null or x.no_aplica)),
           (select count(*)::integer from public.revision_kit_linea x join public.plantilla_kit_linea l on l.id = x.plantilla_linea_id
             where x.revision_id = r.id and not x.no_aplica and x.encontrada is not null and l.cantidad is not null
               and x.encontrada < l.cantidad * r.kits),
           r.actualizada_en, app.nombre_usuario(r.actualizada_por)
    from public.revision_kit r join public.plantilla_kit p on p.id = r.plantilla_id
    order by r.actualizada_en desc;
end $$;

-- ---------------------------------------------------------------------
-- Datos de los reportes (responsable y sub administración)
-- ---------------------------------------------------------------------
create function public.reporte_encabezado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  return jsonb_build_object(
    'escuela', app.config_texto('nombre_escuela'),
    'programa', app.config_texto('programa_escuela'),
    'laboratorio', app.config_texto('nombre_laboratorio'),
    'logo_url', app.config_texto('logo_url'),
    'responsable', (select string_agg(u.nombre, ', ' order by u.nombre) from public.usuario u where u.activo and u.rol = 'RESPONSABLE'),
    'subadministracion', (select string_agg(u.nombre, ', ' order by u.nombre) from public.usuario u where u.activo and u.rol = 'SUBADMIN'),
    'generado_por', yo.nombre,
    'fecha_corte', now(),
    'zona_horaria', app.zona_horaria());
end $$;

-- Persona a cargo, con matrícula y grupo si es alumno o maestro sin cuenta. Sin teléfono ni correo.
create function app.persona_reporte(p_usuario uuid, p_solicitante uuid)
returns table (nombre text, tipo text, matricula text, grupo text)
language sql stable security definer set search_path = '' as $$
  select u.nombre, initcap(lower(u.rol::text)), null::text, null::text from public.usuario u where u.id = p_usuario
  union all
  select s.nombre_completo, initcap(lower(s.tipo::text)), s.matricula_o_clave, s.grupo_area from public.solicitante s where s.id = p_solicitante
$$;

create function public.reporte_prestamos_abiertos()
returns table (codigo text, articulo text, categoria text, cantidad integer, unidad text, a_cargo text, tipo_persona text, matricula text,
               grupo text, desde timestamptz, vence_en timestamptz, vencido boolean, dias_vencido integer, autorizo text, folio text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select a.codigo, a.nombre, a.categoria::text, pa.pendiente::integer, a.unidad, p.nombre, p.tipo, p.matricula, p.grupo,
           pa.fecha, pa.vence_en, pa.vencido,
           case when pa.vencido then (app.hoy() - (pa.vence_en at time zone app.zona_horaria())::date) end,
           app.nombre_usuario(pa.autorizado_por),
           (select s.folio from public.solicitud s where s.id = pa.solicitud_id)
    from app.v_prestamos_abiertos pa
    join public.articulo a on a.id = pa.articulo_id
    left join lateral app.persona_reporte(pa.responsable_usuario_id, pa.responsable_solicitante_id) p on true
    order by pa.vencido desc, pa.vence_en;
end $$;

create function public.reporte_incidencias(p_desde date, p_hasta date)
returns table (reportada_en timestamptz, codigo text, articulo text, categoria text, tipo text, cantidad integer, unidad text, estado text,
               en_taller boolean, a_cargo text, matricula text, grupo text, reporto text, resolvio text, resuelta_en timestamptz,
               nota text, motivo_resolucion text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select i.reportada_en, a.codigo, a.nombre, a.categoria::text,
           case i.tipo when 'PERDIDA' then 'Pérdida' else 'Daño' end,
           i.cantidad, a.unidad,
           case i.estado when 'PENDIENTE' then 'En revisión' when 'CONFIRMADA' then 'Confirmada' else 'Descartada' end,
           i.en_taller, p.nombre, p.matricula, p.grupo,
           app.nombre_usuario(i.reportada_por), app.nombre_usuario(i.resuelta_por), i.resuelta_en, i.nota, i.motivo_resolucion
    from public.incidencia i
    join public.articulo a on a.id = i.articulo_id
    left join lateral app.persona_reporte(i.responsable_usuario_id, i.responsable_solicitante_id) p on true
    where i.tipo <> 'CONSUMO'
      and ((i.reportada_en at time zone app.zona_horaria())::date between p_desde and p_hasta or i.estado = 'PENDIENTE')
    order by i.reportada_en;
end $$;

create function public.reporte_bajas(p_desde date, p_hasta date)
returns table (fecha timestamptz, codigo text, articulo text, categoria text, cantidad integer, unidad text, motivo text, num_resguardo text,
               oficio text, en_tramite boolean, total boolean, autorizo text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select m.fecha, a.codigo, a.nombre, a.categoria::text, m.cantidad, a.unidad, m.nota, a.num_resguardo, a.baja_oficio,
           (not a.activo and a.num_resguardo is not null and a.baja_oficio is null), not a.activo,
           app.nombre_usuario(m.autorizado_por)
    from public.movimiento m join public.articulo a on a.id = m.articulo_id
    where m.tipo = 'BAJA' and (m.fecha at time zone app.zona_horaria())::date between p_desde and p_hasta
    order by m.fecha;
end $$;

create function public.reporte_movimientos(p_desde date, p_hasta date)
returns table (fecha timestamptz, codigo text, articulo text, categoria text, tipo text, cantidad integer, unidad text, a_cargo text,
               matricula text, autorizo text, registro text, origen text, nota text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select m.fecha, a.codigo, a.nombre, a.categoria::text, m.tipo::text, m.cantidad, a.unidad, p.nombre, p.matricula,
           app.nombre_usuario(m.autorizado_por), app.nombre_usuario(m.registrado_por), m.origen::text, m.nota
    from public.movimiento m
    join public.articulo a on a.id = m.articulo_id
    left join lateral app.persona_reporte(m.responsable_usuario_id, m.responsable_solicitante_id) p on true
    where (m.fecha at time zone app.zona_horaria())::date between p_desde and p_hasta
    order by m.fecha;
end $$;

-- Faltantes contra las listas de fábrica: revisiones de kit y desgloses terminados.
create function public.reporte_faltantes_kits()
returns table (origen text, kit text, referencia text, fecha timestamptz, seccion text, sku text, descripcion text, unidad text,
               esperada integer, encontrada integer, faltante integer, estado text, nota text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select 'Revisión de kit', p.nombre, r.nombre || ' (' || r.kits || ' kit' || case when r.kits = 1 then '' else 's' end || ')',
           r.actualizada_en, l.seccion, l.sku, l.descripcion, l.unidad,
           l.cantidad * r.kits, x.encontrada,
           case when coalesce(x.no_aplica, false) or l.cantidad is null or x.encontrada is null then null
                else greatest(l.cantidad * r.kits - x.encontrada, 0) end,
           case when coalesce(x.no_aplica, false) then 'No aplica'
                when x.encontrada is null then 'Sin revisar'
                when l.cantidad is null then 'Revisado'
                when x.encontrada >= l.cantidad * r.kits then 'Completo'
                when x.encontrada = 0 then 'Faltante total'
                else 'Faltante parcial' end,
           coalesce(x.nota, l.nota)
    from public.revision_kit r
    join public.plantilla_kit p on p.id = r.plantilla_id
    join public.plantilla_kit_linea l on l.plantilla_id = r.plantilla_id
    left join public.revision_kit_linea x on x.revision_id = r.id and x.plantilla_linea_id = l.id
    union all
    select 'Desglose', coalesce(p.nombre, 'Sin lista'), a.codigo || ' ' || a.nombre || ' (' || d.unidades || ' unidad' || case when d.unidades = 1 then '' else 'es' end || ')',
           d.terminado_en, dl.seccion, dl.sku, dl.descripcion, dl.unidad, dl.esperada, coalesce(dl.encontrada, 0),
           case when dl.esperada is null then null else greatest(dl.esperada - coalesce(dl.encontrada, 0), 0) end,
           case when dl.esperada is null then 'Revisado'
                when coalesce(dl.encontrada, 0) >= dl.esperada then 'Completo'
                when coalesce(dl.encontrada, 0) = 0 then 'Faltante total'
                else 'Faltante parcial' end,
           dl.nota
    from public.desglose d
    join public.articulo a on a.id = d.articulo_id
    left join public.plantilla_kit p on p.id = d.plantilla_id
    join public.desglose_linea dl on dl.desglose_id = d.id
    where d.estado = 'TERMINADO'
    order by 2, 3, 4;
end $$;

-- Todo lo del acta de un inventario periódico.
create function public.reporte_inventario_periodico(p_inventario uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  i public.inventario_periodico;
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  select * into i from public.inventario_periodico where id = p_inventario;
  if not found then
    raise exception 'El inventario no existe.';
  end if;
  return jsonb_build_object(
    'id', i.id, 'nombre', coalesce(i.nombre, 'Inventario periódico'), 'estado', i.estado, 'alcance', i.alcance,
    'alcance_texto', case
      when coalesce((i.alcance ->> 'todo')::boolean, false) then 'Todo el inventario'
      when i.alcance ? 'categorias' then 'Categorías: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(i.alcance -> 'categorias') x)
      else 'Contenedores: ' || (select string_agg(app.ruta_contenedor(x::uuid), '; ') from jsonb_array_elements_text(i.alcance -> 'contenedores') x) end,
    'fecha_inicio', i.fecha_inicio, 'fecha_cierre', i.fecha_cierre,
    'abrio', app.nombre_usuario(i.abierto_por), 'cerro', app.nombre_usuario(i.cerrado_por),
    'contadores', (select coalesce(jsonb_agg(jsonb_build_object('nombre', app.nombre_usuario(c.contado_por), 'renglones', c.n) order by c.n desc), '[]'::jsonb)
                   from (select l.contado_por, count(*) as n from public.conteo_linea l where l.inventario_id = i.id and not l.anulado group by l.contado_por) c),
    'incidencias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'articulo', a.nombre, 'cantidad', inc.cantidad,
                                                                 'estado', inc.estado, 'nota', inc.nota)), '[]'::jsonb)
                    from public.inventario_decision d join public.incidencia inc on inc.id = d.incidencia_id
                    join public.articulo a on a.id = d.articulo_id where d.inventario_id = i.id));
end $$;

-- Registro de cada documento generado; las actas llevan folio consecutivo por año (AER-2026-001, AIP-2026-001).
create function public.reporte_registrar(p_tipo text, p_formato text, p_parametros jsonb default '{}') returns text
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  prefijo text := case p_tipo when 'ACTA_ENTREGA' then 'AER' when 'ACTA_INVENTARIO' then 'AIP' end;
  anio   integer := extract(year from app.hoy());
  n      integer;
  folio  text;
begin
  if p_tipo not in ('INVENTARIO', 'PRESTAMOS', 'INCIDENCIAS', 'BAJAS', 'MOVIMIENTOS', 'FALTANTES_KITS', 'ACTA_ENTREGA', 'ACTA_INVENTARIO') then
    raise exception 'Tipo de reporte desconocido.';
  end if;
  if p_formato not in ('EXCEL', 'PDF') then
    raise exception 'Formato desconocido.';
  end if;
  if p_tipo = 'ACTA_ENTREGA' and yo.rol <> 'SUBADMIN' then
    raise exception 'El acta de entrega-recepción la genera sub administración.' using errcode = 'PT403', detail = 'ROL';
  end if;
  if prefijo is not null then
    perform pg_advisory_xact_lock(hashtext('folio-' || prefijo || anio));
    select count(*) + 1 into n from public.bitacora b
     where b.evento = 'REPORTE_GENERADO' and b.datos ->> 'folio' like prefijo || '-' || anio || '-%';
    folio := format('%s-%s-%s', prefijo, anio, lpad(n::text, 3, '0'));
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'REPORTE_GENERADO', 'reporte', p_tipo,
          jsonb_build_object('tipo', p_tipo, 'formato', p_formato, 'folio', folio, 'parametros', coalesce(p_parametros, '{}'::jsonb)));
  return folio;
end $$;

-- ---------------------------------------------------------------------
-- Ajustes: el encabezado de los reportes también lo cambia sub administración
-- ---------------------------------------------------------------------
create or replace function public.configuracion_cambiar(p_clave text, p_valor jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA', array['SUBADMIN']::public.rol_usuario[]);
  antes  jsonb;
  numero integer;
begin
  if p_clave not in ('fin_ciclo_escolar', 'hora_fin_jornada', 'plazo_default_dias', 'plazo_max_alumno_dias',
                     'plazo_max_maestro_dias', 'url_app', 'nombre_escuela', 'programa_escuela', 'nombre_laboratorio') then
    raise exception 'Ese ajuste no se cambia desde la app.';
  end if;
  if p_clave in ('plazo_default_dias', 'plazo_max_alumno_dias', 'plazo_max_maestro_dias') then
    begin
      numero := (p_valor #>> '{}')::integer;
    exception when others then
      raise exception 'Escribe un número de días.';
    end;
    if numero is null or numero < 1 or numero > 120 then
      raise exception 'Los días deben estar entre 1 y 120.';
    end if;
    p_valor := to_jsonb(numero);
  elsif p_clave = 'fin_ciclo_escolar' then
    begin
      p_valor := to_jsonb(((p_valor #>> '{}')::date)::text);
    exception when others then
      raise exception 'La fecha no es válida.';
    end;
  elsif p_clave = 'hora_fin_jornada' then
    begin
      p_valor := to_jsonb(to_char((p_valor #>> '{}')::time, 'HH24:MI'));
    exception when others then
      raise exception 'La hora no es válida (ejemplo: 15:00).';
    end;
  elsif p_clave = 'url_app' and coalesce(p_valor #>> '{}', '') !~ '^https?://' then
    raise exception 'La dirección debe empezar con https://';
  elsif p_clave in ('nombre_escuela', 'programa_escuela', 'nombre_laboratorio') then
    if length(btrim(coalesce(p_valor #>> '{}', ''))) < 3 then
      raise exception 'Escribe el nombre completo.';
    end if;
    p_valor := to_jsonb(btrim(p_valor #>> '{}'));
  end if;
  perform app.exigir_confirmacion();
  select valor into antes from public.configuracion where clave = p_clave;
  update public.configuracion set valor = p_valor where clave = p_clave;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'CONFIGURACION', 'configuracion', p_clave, jsonb_build_object('antes', antes, 'despues', p_valor));
end $$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on all functions in schema app from public;
grant execute on function app.puede_subir_foto(), app.puede_subir_foto_contenedor(), app.puede_subir_privado(text),
                          app.puede_ver_privado(text), app.ruta_contenedor(uuid) to authenticated;
grant execute on function app.ruta_contenedor(uuid) to anon;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('revision_kit_crear', 'revision_kit_guardar', 'revision_kit_detalle', 'revisiones_kit', 'reporte_encabezado',
                        'reporte_prestamos_abiertos', 'reporte_incidencias', 'reporte_bajas', 'reporte_movimientos',
                        'reporte_faltantes_kits', 'reporte_inventario_periodico', 'reporte_registrar', 'configuracion_cambiar')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to authenticated', f.firma);
  end loop;
end $$;
