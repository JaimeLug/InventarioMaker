-- =====================================================================
-- 0006 · Movimientos y bitácora (Fase 3)
--
-- Flujos: F-07 préstamo directo (con extensión), F-08 devolución, F-09 reporte de
-- pérdida o daño y su confirmación, F-10 consumo, reparación, F-13 ajuste de conteo,
-- F-14 baja definitiva, y lecturas con nombres (solo responsable y sub administración).
--
-- Las cifras las siguen validando los disparadores de 0002: estas funciones deciden
-- QUIÉN puede hacer QUÉ y arman los movimientos.
-- =====================================================================

insert into public.configuracion (clave, valor, descripcion) values
  ('hora_fin_jornada',          '"15:00"',               'Hora en que termina la jornada: vencimiento por defecto de un préstamo directo'),
  ('dominio_correo_alumnos',    '"prepasoficiales.net"', 'Dominio obligatorio del correo de los alumnos'),
  ('ventana_deshacer_segundos', '120',                   'Margen del servidor para deshacer un préstamo recién hecho (la app ofrece 10 segundos)'),
  ('prestamo_directo_max_dias', '30',                    'Máximo de días hacia adelante para la fecha de devolución de un préstamo directo')
on conflict (clave) do nothing;

create function app.config_texto(p_clave text) returns text
language sql stable security definer set search_path = '' as $$
  select valor #>> '{}' from public.configuracion where clave = p_clave
$$;

-- Fin de la jornada de hoy en Mérida; si ya pasó, la de mañana.
create function app.fin_jornada() returns timestamptz
language sql stable set search_path = '' as $$
  select case when t > now() then t else t + interval '1 day' end
  from (select ((app.hoy() + app.config_texto('hora_fin_jornada')::time)::timestamp
                at time zone app.zona_horaria()) as t) x
$$;

create function app.hora_local(p timestamptz) returns text
language sql stable set search_path = '' as $$
  select to_char(p at time zone app.zona_horaria(), 'DD/MM/YYYY HH24:MI')
$$;

-- Primero el rol y luego la contraseña: a un docente no se le pide contraseña para algo que
-- su cuenta nunca podría hacer (así decide también la app). Corrige el orden de 0005.
create or replace function app.exigir(p_nivel text default 'SESION', p_roles public.rol_usuario[] default null)
returns public.usuario
language plpgsql stable security definer set search_path = '' as $$
declare
  u      public.usuario;
  expira timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Identifícate para continuar.' using errcode = 'PT401', detail = 'SIN_SESION';
  end if;
  select * into u from public.usuario where id = auth.uid();
  if not found or not u.activo then
    raise exception 'Tu cuenta no está activa. Habla con el responsable del laboratorio.'
      using errcode = 'PT403', detail = 'CUENTA_INACTIVA';
  end if;
  expira := app.sesion_expira_en();
  if expira is null or expira <= now() then
    raise exception 'Tu sesión terminó. Vuelve a identificarte.' using errcode = 'PT401', detail = 'SESION_VENCIDA';
  end if;
  if p_roles is not null and not (u.rol = any (p_roles)) then
    raise exception 'Tu cuenta no puede hacer esto.' using errcode = 'PT403', detail = 'ROL';
  end if;
  if p_nivel = 'CONTRASENA' and app.nivel_sesion() <> 'CONTRASENA' then
    raise exception 'Esta acción necesita que entres con tu contraseña.'
      using errcode = 'PT403', detail = 'NIVEL_CONTRASENA';
  end if;
  return u;
end $$;

-- ---------------------------------------------------------------------
-- Estructura nueva
-- ---------------------------------------------------------------------

-- Los artículos que salen juntos en un mismo préstamo.
alter table public.movimiento add column grupo uuid;
create index movimiento_grupo_idx on public.movimiento (grupo) where grupo is not null;

-- Los movimientos no se editan: extender la fecha de un préstamo queda aparte.
create table public.prestamo_extension (
  id              uuid primary key default gen_random_uuid(),
  prestamo_id     uuid not null references public.movimiento (id),
  fecha_anterior  timestamptz not null,
  fecha_nueva     timestamptz not null,
  motivo          text not null check (btrim(motivo) <> ''),
  extendida_por   uuid not null references public.usuario (id),
  extendida_en    timestamptz not null default now(),
  check (fecha_nueva > fecha_anterior)
);
create index prestamo_extension_idx on public.prestamo_extension (prestamo_id, extendida_en desc);

-- "Pedir más información" sobre un reporte, y la respuesta de quien lo levantó.
create table public.incidencia_comentario (
  id             uuid primary key default gen_random_uuid(),
  incidencia_id  uuid not null references public.incidencia (id),
  autor_id       uuid not null references public.usuario (id),
  texto          text not null check (btrim(texto) <> ''),
  en             timestamptz not null default now()
);
create index incidencia_comentario_idx on public.incidencia_comentario (incidencia_id, en);

-- Ficha verificada en persona (F-04b, medida 2).
alter table public.solicitante
  add column verificada_por uuid references public.usuario (id),
  add column verificada_en  timestamptz,
  add constraint solicitante_verificada check ((verificada_por is null) = (verificada_en is null));

-- Número de oficio de la baja institucional (P-9). Sin oficio y con resguardo: "baja en trámite".
alter table public.articulo add column baja_oficio text;

do $$
declare
  t text;
begin
  foreach t in array array['prestamo_extension', 'incidencia_comentario'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('create trigger solo_agregar before update or delete on public.%I for each row execute function app.prohibir_edicion()', t);
  end loop;
end $$;

-- Préstamos abiertos: la fecha que manda es la última extensión, si la hay.
create or replace view app.v_prestamos_abiertos as
select
  p.id                                  as prestamo_id,
  p.articulo_id,
  p.cantidad                            as cantidad_prestada,
  p.cantidad - coalesce(c.cerrado, 0)   as pendiente,
  p.fecha,
  v.vence_en,
  now() > v.vence_en                    as vencido,
  p.responsable_usuario_id,
  p.responsable_solicitante_id,
  p.autorizado_por,
  p.solicitud_id,
  p.conflicto,
  p.grupo,
  p.nota,
  coalesce(x.n, 0)::integer             as extensiones
from public.movimiento p
left join lateral (
  select sum(h.cantidad) as cerrado
  from public.movimiento h
  where h.movimiento_origen_id = p.id and h.tipo in ('DEVOLUCION', 'PERDIDA')
) c on true
left join public.solicitud s on s.id = p.solicitud_id
left join lateral (
  select count(*) as n, (array_agg(e.fecha_nueva order by e.extendida_en desc))[1] as ultima
  from public.prestamo_extension e
  where e.prestamo_id = p.id
) x on true
cross join lateral (
  select coalesce(x.ultima, p.fecha_compromiso, s.fecha_devolucion_comprometida,
                  p.fecha + make_interval(days => app.config_int('dias_vencimiento'))) as vence_en
) v
where p.tipo = 'PRESTAMO' and p.cantidad - coalesce(c.cerrado, 0) > 0;

-- El catálogo público muestra si una baja sigue en trámite.
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
    as baja_en_tramite
from public.articulo a
join public.v_existencias e on e.articulo_id = a.id
left join public.contenedor c on c.id = a.contenedor_id
left join public.foto f on f.articulo_id = a.id and f.es_principal;

-- ---------------------------------------------------------------------
-- Almacén privado (daños y pérdidas; en la 3b, entregas e identificaciones)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('privado', 'privado', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create function app.puede_subir_privado(p_ruta text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return split_part(p_ruta, '/', 1) = 'incidencias';
exception when others then
  return false;
end $$;

-- Responsable y sub administración (con contraseña) ven todo lo privado.
-- Quien reportó ve las fotos de su propio reporte.
create function app.puede_ver_privado(p_ruta text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  u public.usuario;
begin
  begin
    u := app.exigir('SESION');
  exception when others then
    return false;
  end;
  if u.rol in ('RESPONSABLE', 'SUBADMIN') and app.nivel_sesion() = 'CONTRASENA' then
    return true;
  end if;
  if split_part(p_ruta, '/', 1) = 'incidencias' then
    return exists (select 1 from public.foto f join public.incidencia i on i.id = f.incidencia_id
                   where f.url = p_ruta and i.reportada_por = u.id);
  end if;
  return false;
end $$;

create policy privado_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'privado' and app.puede_subir_privado(name));
create policy privado_ver on storage.objects for select to authenticated
  using (bucket_id = 'privado' and app.puede_ver_privado(name));

-- ---------------------------------------------------------------------
-- Utilidades internas
-- ---------------------------------------------------------------------
create function app.comando_previo(p_comando uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select c.resultado from public.comando_aplicado c where c.id = p_comando
$$;

create function app.registrar_comando(p_comando uuid, p_usuario uuid, p_tipo text, p_resultado jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if p_comando is not null then
    insert into public.comando_aplicado (id, usuario_id, tipo, resultado) values (p_comando, p_usuario, p_tipo, p_resultado);
  end if;
  return p_resultado;
end $$;

create function app.nombre_usuario(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select nombre from public.usuario where id = p_id
$$;

create function app.nombre_solicitante(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select s.nombre_completo || ' (' || initcap(lower(s.tipo::text)) || coalesce(', ' || s.grupo_area, '') || ')'
  from public.solicitante s where s.id = p_id
$$;

-- Registra una incidencia (pérdida, daño o consumo por autorizar) con sus fotos privadas.
-- La usan el reporte directo, la devolución con daño o faltantes y el consumo de un docente.
create function app.crear_incidencia(
  p_yo uuid, p_id uuid, p_articulo uuid, p_tipo public.tipo_incidencia, p_cantidad integer,
  p_prestamo uuid, p_nota text, p_fotos jsonb, p_sin_foto text,
  p_resp_usuario uuid, p_resp_solicitante uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  a          public.articulo;
  nueva      uuid := coalesce(p_id, gen_random_uuid());
  v_exist    integer;
  v_prest    integer;
  v_fuera    integer;
  v_retenido integer;
  v_apartado integer;
  v_pend     integer;
  f          jsonb;
  ruta       text;
begin
  select * into a from public.articulo where id = p_articulo for update;
  if not found or not a.activo then
    raise exception 'El artículo no existe o está dado de baja.';
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a cero.';
  end if;
  if p_tipo in ('PERDIDA', 'DANO') then
    if length(btrim(coalesce(p_nota, ''))) < 15 then
      raise exception 'Describe qué pasó (al menos 15 letras).';
    end if;
    if coalesce(jsonb_array_length(p_fotos), 0) = 0 and length(btrim(coalesce(p_sin_foto, ''))) < 15 then
      raise exception 'Agrega una foto, o explica por qué no se puede tomar (al menos 15 letras).';
    end if;
  end if;

  -- Las cifras salen de la misma vista que usa todo el sistema (sección 1 de docs/flujos.md).
  select coalesce(max(m.existencia), 0), coalesce(max(m.prestado), 0), coalesce(max(m.fuera_servicio), 0)
    into v_exist, v_prest, v_fuera
    from app.v_mov_totales m where m.articulo_id = p_articulo;
  select coalesce(sum(i.cantidad), 0) into v_retenido
    from public.incidencia i where i.articulo_id = p_articulo and i.estado = 'PENDIENTE' and i.en_taller;

  if p_prestamo is null then
    if p_tipo = 'CONSUMO' then
      select coalesce(sum(coalesce(l.cantidad_aprobada, l.cantidad)), 0) into v_apartado
        from public.solicitud_linea l join public.solicitud s on s.id = l.solicitud_id
        where s.estado = 'APROBADA' and l.articulo_id = p_articulo;
    else
      v_apartado := 0;
    end if;
    if p_cantidad > v_exist - v_prest - v_fuera - v_retenido - v_apartado then
      raise exception 'Solo hay % en el taller sin otros reportes pendientes.', greatest(v_exist - v_prest - v_fuera - v_retenido - v_apartado, 0);
    end if;
  else
    if p_tipo <> 'PERDIDA' then
      raise exception 'Un daño de algo prestado se registra al recibir la devolución.';
    end if;
    select pa.pendiente - coalesce((select sum(i.cantidad) from public.incidencia i
                                     where i.prestamo_id = p_prestamo and i.estado = 'PENDIENTE'), 0)
      into v_pend
      from app.v_prestamos_abiertos pa where pa.prestamo_id = p_prestamo and pa.articulo_id = p_articulo;
    if v_pend is null then
      raise exception 'Ese préstamo ya está cerrado.';
    end if;
    if p_cantidad > v_pend then
      raise exception 'De ese préstamo solo quedan % sin reportar.', greatest(v_pend, 0);
    end if;
  end if;

  insert into public.incidencia (id, articulo_id, tipo, cantidad, nota, sin_foto_justificacion, en_taller, prestamo_id,
                                 responsable_usuario_id, responsable_solicitante_id, reportada_por)
  values (nueva, p_articulo, p_tipo, p_cantidad, coalesce(nullif(btrim(p_nota), ''), 'Consumo'),
          nullif(btrim(p_sin_foto), ''), p_prestamo is null, p_prestamo, p_resp_usuario, p_resp_solicitante, p_yo);

  for f in select * from jsonb_array_elements(coalesce(p_fotos, '[]'::jsonb)) loop
    ruta := f ->> 'ruta';
    if ruta is null or ruta not like 'incidencias/' || nueva::text || '/%' then
      raise exception 'Ruta de foto inválida: %', ruta;
    end if;
    if not app.archivo_existe('privado', ruta) then
      raise exception 'Una de las fotos no terminó de subirse. Intenta de nuevo.';
    end if;
    insert into public.foto (articulo_id, incidencia_id, url, tipo, tomada_por)
    values (p_articulo, nueva, ruta, 'DANO', p_yo);
  end loop;
  return nueva;
end $$;

-- Estado después de un conteo confirmado (decisión de la Fase 3).
create function app.estado_tras_conteo(p_articulo uuid) returns public.estado_inventario
language sql stable security definer set search_path = '' as $$
  select case
    when a.estado_inventario not in ('POR_CONTAR', 'POR_VERIFICAR') then a.estado_inventario
    when exists (select 1 from public.foto f where f.articulo_id = a.id and f.es_principal)
         and (a.contenedor_id is not null or btrim(coalesce(a.ubicacion, '')) <> '') then 'VERIFICADO'
    else 'POR_VERIFICAR'
  end::public.estado_inventario
  from public.articulo a where a.id = p_articulo
$$;

-- ---------------------------------------------------------------------
-- Solicitantes (fichas rápidas; la solicitud pública llega en la 3b)
-- ---------------------------------------------------------------------
-- Solo por matrícula exacta: nadie puede recorrer la lista de alumnos.
create function public.solicitante_buscar(p_matricula text)
returns table (id uuid, nombre_completo text, tipo public.tipo_solicitante, grupo_area text,
               bloqueado boolean, verificada boolean, vencidos integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select s.id, s.nombre_completo, s.tipo, s.grupo_area, s.bloqueado, s.verificada_en is not null,
           (select count(*) from app.v_prestamos_abiertos pa
             where pa.responsable_solicitante_id = s.id and pa.vencido)::integer
    from public.solicitante s
    where lower(btrim(s.matricula_o_clave)) = lower(btrim(p_matricula)) and not s.posible_duplicado
    order by s.tipo;
end $$;

create function public.solicitante_crear_rapido(p_nombre text, p_tipo public.tipo_solicitante, p_matricula text,
                                                p_grupo text, p_correo text, p_telefono text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo      public.usuario := app.exigir('SESION');
  dominio text := app.config_texto('dominio_correo_alumnos');
  correo  text := lower(btrim(coalesce(p_correo, '')));
  nueva   uuid;
begin
  if length(btrim(coalesce(p_nombre, ''))) < 5 then
    raise exception 'Escribe el nombre completo.';
  end if;
  if btrim(coalesce(p_matricula, '')) = '' then
    raise exception 'Escribe la matrícula o clave.';
  end if;
  if p_tipo = 'ALUMNO' and correo !~ ('^[^@\s]+@' || replace(dominio, '.', '\.') || '$') then
    raise exception 'El correo del alumno debe ser institucional (@%).', dominio;
  end if;
  if correo <> '' and correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo no parece válido.';
  end if;
  begin
    insert into public.solicitante (nombre_completo, tipo, matricula_o_clave, grupo_area, correo, telefono,
                                    verificada_por, verificada_en)
    values (btrim(p_nombre), p_tipo, btrim(p_matricula), nullif(btrim(p_grupo), ''), nullif(correo, ''),
            nullif(btrim(p_telefono), ''), yo.id, now())
    returning id into nueva;
  exception when unique_violation then
    raise exception 'Ya existe una ficha con esa matrícula. Búscala en lugar de crear otra.';
  end;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id) values (yo.id, 'SOLICITANTE_CREADO', 'solicitante', nueva::text);
  return nueva;
end $$;

-- ---------------------------------------------------------------------
-- F-07 Préstamo directo
-- ---------------------------------------------------------------------
create function public.prestamo_registrar(
  p_lineas jsonb, p_responsable_usuario uuid default null, p_responsable_solicitante uuid default null,
  p_fecha_compromiso timestamptz default null, p_nota text default null, p_comando uuid default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('SESION');
  previo    jsonb := app.comando_previo(p_comando);
  grupo     uuid := coalesce(p_comando, gen_random_uuid());
  vence     timestamptz := coalesce(p_fecha_compromiso, app.fin_jornada());
  s         public.solicitante;
  l         jsonb;
  articulo  uuid;
  cantidad  integer;
  vistos    uuid[] := '{}';
  ids       uuid[] := '{}';
  nuevo     uuid;
begin
  if previo is not null then
    return previo;
  end if;
  if num_nonnulls(p_responsable_usuario, p_responsable_solicitante) <> 1 then
    raise exception 'Indica para quién es el préstamo.';
  end if;
  if p_responsable_usuario is not null and not exists (select 1 from public.usuario u where u.id = p_responsable_usuario and u.activo) then
    raise exception 'Esa cuenta no está activa.';
  end if;
  if p_responsable_solicitante is not null then
    select * into s from public.solicitante where id = p_responsable_solicitante;
    if not found then
      raise exception 'Esa persona no está registrada.';
    end if;
    if s.bloqueado then
      raise exception '% tiene material pendiente de devolver y no puede llevarse más.', s.nombre_completo;
    end if;
  end if;
  if vence <= now() then
    raise exception 'La fecha de devolución ya pasó.';
  end if;
  if vence > now() + make_interval(days => app.config_int('prestamo_directo_max_dias')) then
    raise exception 'La fecha de devolución puede ser a lo más en % días.', app.config_int('prestamo_directo_max_dias');
  end if;
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array' or jsonb_array_length(p_lineas) = 0 then
    raise exception 'Agrega al menos un artículo.';
  end if;

  for l in select * from jsonb_array_elements(p_lineas) loop
    articulo := (l ->> 'articulo_id')::uuid;
    cantidad := (l ->> 'cantidad')::integer;
    if articulo = any (vistos) then
      raise exception 'Un artículo aparece dos veces en el préstamo.';
    end if;
    vistos := vistos || articulo;
    if cantidad is null or cantidad <= 0 then
      raise exception 'La cantidad debe ser mayor a cero.';
    end if;
    insert into public.movimiento (articulo_id, tipo, cantidad, fecha_compromiso, nota, autorizado_por, registrado_por,
                                   responsable_usuario_id, responsable_solicitante_id, grupo, comando_id, origen)
    values (articulo, 'PRESTAMO', cantidad, vence, nullif(btrim(p_nota), ''), yo.id, yo.id,
            p_responsable_usuario, p_responsable_solicitante, grupo,
            case when p_comando is null then null else md5(p_comando::text || articulo::text)::uuid end, 'APP')
    returning id into nuevo;
    ids := ids || nuevo;
  end loop;

  return app.registrar_comando(p_comando, yo.id, 'PRESTAMO',
    jsonb_build_object('grupo', grupo, 'movimientos', to_jsonb(ids), 'vence_en', vence));
end $$;

-- Deshacer justo después (la app ofrece 10 segundos). No borra: devuelve todo lo prestado.
create function public.prestamo_deshacer(p_grupo uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('SESION');
  p   record;
  n   integer := 0;
begin
  for p in
    select m.id, m.articulo_id, m.registrado_por, m.fecha, m.cantidad, pa.pendiente
    from public.movimiento m
    left join app.v_prestamos_abiertos pa on pa.prestamo_id = m.id
    where m.grupo = p_grupo and m.tipo = 'PRESTAMO'
  loop
    if p.registrado_por <> yo.id then
      raise exception 'Solo quien registró el préstamo puede deshacerlo.' using errcode = 'PT403', detail = 'ROL';
    end if;
    if p.fecha < now() - make_interval(secs => app.config_int('ventana_deshacer_segundos')) then
      raise exception 'Ya pasó el tiempo para deshacer. Registra una devolución.';
    end if;
    if p.pendiente is distinct from p.cantidad then
      raise exception 'Ese préstamo ya tiene devoluciones: no se puede deshacer.';
    end if;
    insert into public.movimiento (articulo_id, tipo, cantidad, movimiento_origen_id, nota, autorizado_por, registrado_por, origen)
    values (p.articulo_id, 'DEVOLUCION', p.cantidad, p.id, 'Deshecho por quien lo registró', yo.id, yo.id, 'APP');
    n := n + 1;
  end loop;
  if n = 0 then
    raise exception 'No encontré ese préstamo.';
  end if;
  return n;
end $$;

create function public.prestamo_extender(p_prestamo uuid, p_fecha timestamptz, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
  pa record;
begin
  select * into pa from app.v_prestamos_abiertos where prestamo_id = p_prestamo;
  if not found then
    raise exception 'Ese préstamo ya se cerró.';
  end if;
  if yo.rol = 'DOCENTE' and pa.autorizado_por <> yo.id and pa.responsable_usuario_id is distinct from yo.id then
    raise exception 'Solo quien prestó o el responsable del laboratorio pueden extender este préstamo.'
      using errcode = 'PT403', detail = 'ROL';
  end if;
  if p_fecha <= now() or p_fecha <= pa.vence_en then
    raise exception 'La nueva fecha debe ser después de la actual (%).', app.hora_local(pa.vence_en);
  end if;
  if p_fecha > now() + make_interval(days => app.config_int('prestamo_directo_max_dias')) then
    raise exception 'Se puede extender a lo más % días desde hoy.', app.config_int('prestamo_directo_max_dias');
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué se extiende.';
  end if;
  insert into public.prestamo_extension (prestamo_id, fecha_anterior, fecha_nueva, motivo, extendida_por)
  values (p_prestamo, pa.vence_en, p_fecha, btrim(p_motivo), yo.id);
end $$;

-- ---------------------------------------------------------------------
-- F-08 Devolución (total, parcial, con daño, con faltantes perdidos)
-- ---------------------------------------------------------------------
-- Cada línea: {prestamo_id, regresan, danadas, nota_dano, fotos_dano, incidencia_dano_id,
--              faltante: "DESPUES" | "PERDIDO", nota_perdida, fotos_perdida, sin_foto_perdida, incidencia_perdida_id}
create function public.devolucion_registrar(p_lineas jsonb, p_comando uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo       public.usuario := app.exigir('SESION');
  previo   jsonb := app.comando_previo(p_comando);
  l        jsonb;
  pa       record;
  regresan integer;
  danadas  integer;
  faltan   integer;
  devueltas integer := 0;
  reportes  integer := 0;
begin
  if previo is not null then
    return previo;
  end if;
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array' or jsonb_array_length(p_lineas) = 0 then
    raise exception 'Indica qué se devuelve.';
  end if;

  for l in select * from jsonb_array_elements(p_lineas) loop
    select * into pa from app.v_prestamos_abiertos where prestamo_id = (l ->> 'prestamo_id')::uuid;
    if not found then
      raise exception 'Ese préstamo ya estaba cerrado.';
    end if;
    regresan := coalesce((l ->> 'regresan')::integer, 0);
    danadas := coalesce((l ->> 'danadas')::integer, 0);
    if regresan < 0 or regresan > pa.pendiente then
      raise exception 'De ese préstamo pueden regresar de 0 a %.', pa.pendiente;
    end if;
    if danadas < 0 or danadas > regresan then
      raise exception 'Las piezas dañadas no pueden ser más de las que regresan.';
    end if;

    if regresan > 0 then
      insert into public.movimiento (articulo_id, tipo, cantidad, movimiento_origen_id, autorizado_por, registrado_por, origen, nota)
      values (pa.articulo_id, 'DEVOLUCION', regresan, pa.prestamo_id, yo.id, yo.id, 'APP',
              case when danadas > 0 then format('Regresan %s, %s con daño', regresan, danadas) end);
      devueltas := devueltas + regresan;
    end if;

    if danadas > 0 then
      perform app.crear_incidencia(yo.id, (l ->> 'incidencia_dano_id')::uuid, pa.articulo_id, 'DANO', danadas, null,
                                   l ->> 'nota_dano', l -> 'fotos_dano', null,
                                   pa.responsable_usuario_id, pa.responsable_solicitante_id);
      reportes := reportes + 1;
    end if;

    faltan := pa.pendiente - regresan;
    if faltan > 0 and l ->> 'faltante' = 'PERDIDO' then
      perform app.crear_incidencia(yo.id, (l ->> 'incidencia_perdida_id')::uuid, pa.articulo_id, 'PERDIDA', faltan, pa.prestamo_id,
                                   l ->> 'nota_perdida', l -> 'fotos_perdida', l ->> 'sin_foto_perdida',
                                   pa.responsable_usuario_id, pa.responsable_solicitante_id);
      reportes := reportes + 1;
    end if;
  end loop;

  return app.registrar_comando(p_comando, yo.id, 'DEVOLUCION',
    jsonb_build_object('devueltas', devueltas, 'reportes', reportes));
end $$;

-- ---------------------------------------------------------------------
-- F-09 Reporte de pérdida o daño, F-10 consumo
-- ---------------------------------------------------------------------
create function public.incidencia_reportar(
  p_id uuid, p_articulo uuid, p_tipo public.tipo_incidencia, p_cantidad integer, p_prestamo uuid,
  p_nota text, p_fotos jsonb, p_sin_foto text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo              public.usuario := app.exigir('SESION');
  resp_usuario    uuid;
  resp_solicitante uuid;
begin
  if p_tipo = 'CONSUMO' then
    raise exception 'El consumo se registra con "Registrar uso".';
  end if;
  if exists (select 1 from public.incidencia i where i.id = p_id) then
    return p_id;   -- reintento del mismo reporte
  end if;
  -- Si viene de un préstamo, queda a cargo de quien lo tiene.
  select pa.responsable_usuario_id, pa.responsable_solicitante_id into resp_usuario, resp_solicitante
    from app.v_prestamos_abiertos pa where pa.prestamo_id = p_prestamo;
  return app.crear_incidencia(yo.id, p_id, p_articulo, p_tipo, p_cantidad, p_prestamo, p_nota, p_fotos, p_sin_foto,
                              resp_usuario, resp_solicitante);
end $$;

-- Responsable o sub administración con contraseña: se aplica. Cualquier otro caso: queda por autorizar.
create function public.consumo_registrar(p_articulo uuid, p_cantidad integer, p_nota text, p_comando uuid default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('SESION');
  previo jsonb := app.comando_previo(p_comando);
  a      public.articulo;
  nueva  uuid;
begin
  if previo is not null then
    return previo;
  end if;
  select * into a from public.articulo where id = p_articulo;
  if not found or not a.es_consumible then
    raise exception 'Solo los consumibles se registran como uso.';
  end if;
  if yo.rol in ('RESPONSABLE', 'SUBADMIN') and app.nivel_sesion() = 'CONTRASENA' then
    insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen, comando_id)
    values (p_articulo, 'CONSUMO', p_cantidad, nullif(btrim(p_nota), ''), yo.id, yo.id, 'APP', p_comando)
    returning id into nueva;
    return app.registrar_comando(p_comando, yo.id, 'CONSUMO', jsonb_build_object('aplicado', true, 'id', nueva));
  end if;
  nueva := app.crear_incidencia(yo.id, null, p_articulo, 'CONSUMO', p_cantidad, null, p_nota, null, null, yo.id, null);
  return app.registrar_comando(p_comando, yo.id, 'CONSUMO', jsonb_build_object('aplicado', false, 'id', nueva));
end $$;

-- Confirmar o descartar uno o varios reportes con una sola reconfirmación de contraseña.
create function public.incidencia_resolver(p_ids uuid[], p_decision text, p_motivo text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  i   public.incidencia;
  mov uuid;
  n   integer := 0;
begin
  if p_decision not in ('CONFIRMAR', 'DESCARTAR') then
    raise exception 'Decisión desconocida: %', p_decision;
  end if;
  if p_decision = 'DESCARTAR' and btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué se descarta.';
  end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 then
    raise exception 'No hay reportes seleccionados.';
  end if;
  perform app.exigir_confirmacion();

  for i in select * from public.incidencia where id = any (p_ids) order by reportada_en for update loop
    if i.estado <> 'PENDIENTE' then
      raise exception 'Uno de los reportes ya fue resuelto por alguien más.';
    end if;
    mov := null;
    if p_decision = 'CONFIRMAR' then
      insert into public.movimiento (articulo_id, tipo, cantidad, movimiento_origen_id, nota, incidencia_id,
                                     autorizado_por, registrado_por, responsable_usuario_id, responsable_solicitante_id, origen)
      values (i.articulo_id, i.tipo::text::public.tipo_movimiento, i.cantidad, i.prestamo_id, i.nota, i.id,
              yo.id, i.reportada_por,
              case when i.tipo = 'CONSUMO' then null else i.responsable_usuario_id end,
              case when i.tipo = 'CONSUMO' then null else i.responsable_solicitante_id end, 'APP')
      returning id into mov;
    end if;
    update public.incidencia
       set estado = case when p_decision = 'CONFIRMAR' then 'CONFIRMADA' else 'DESCARTADA' end::public.estado_incidencia,
           resuelta_por = yo.id, resuelta_en = now(), motivo_resolucion = nullif(btrim(p_motivo), ''), movimiento_id = mov
     where id = i.id;
    n := n + 1;
  end loop;
  if n <> array_length(p_ids, 1) then
    raise exception 'Alguno de los reportes no existe.';
  end if;
  return n;
end $$;

create function public.incidencia_comentar(p_incidencia uuid, p_texto text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
  i  public.incidencia;
begin
  select * into i from public.incidencia where id = p_incidencia;
  if not found then
    raise exception 'El reporte no existe.';
  end if;
  if yo.rol = 'DOCENTE' and i.reportada_por <> yo.id then
    raise exception 'Solo puedes comentar tus propios reportes.' using errcode = 'PT403', detail = 'ROL';
  end if;
  insert into public.incidencia_comentario (incidencia_id, autor_id, texto) values (p_incidencia, yo.id, btrim(p_texto));
end $$;

-- ---------------------------------------------------------------------
-- Reparación, F-13 ajuste de conteo, F-14 baja y reactivación
-- ---------------------------------------------------------------------
create function public.reparacion_registrar(p_articulo uuid, p_cantidad integer, p_nota text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
  values (p_articulo, 'REPARACION', p_cantidad, nullif(btrim(p_nota), ''), yo.id, yo.id, 'APP');
end $$;

-- Se captura cuántos hay EN EL TALLER (lo prestado no se cuenta). Idempotente por naturaleza:
-- repetir el mismo conteo da diferencia cero.
create function public.ajuste_conteo(p_articulo uuid, p_en_taller integer, p_motivo text, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo         public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  a          public.articulo;
  e          record;
  diferencia integer;
  etiqueta   text;
  estado     public.estado_inventario;
begin
  select * into a from public.articulo where id = p_articulo for update;
  if not found or not a.activo then
    raise exception 'El artículo no existe o está dado de baja.';
  end if;
  if p_en_taller is null or p_en_taller < 0 then
    raise exception 'Escribe cuántos hay en el taller.';
  end if;
  etiqueta := case p_motivo
    when 'CONTEO_FISICO' then 'Conteo físico'
    when 'ERROR_CAPTURA' then 'Error de captura inicial'
    when 'APARECIO' then 'Apareció'
    when 'NO_SE_ENCONTRO' then 'No se encontró'
  end;
  if etiqueta is null then
    raise exception 'Elige el motivo del ajuste.';
  end if;
  perform app.exigir_confirmacion();

  select * into e from public.v_existencias where articulo_id = p_articulo;
  diferencia := p_en_taller - e.en_taller;
  if diferencia <> 0 then
    if btrim(coalesce(p_nota, '')) = '' then
      raise exception 'Explica la diferencia de % piezas.', diferencia;
    end if;
    insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
    values (p_articulo, 'AJUSTE_CONTEO', diferencia, etiqueta || ': ' || btrim(p_nota), yo.id, yo.id, 'APP');
  end if;

  estado := app.estado_tras_conteo(p_articulo);
  update public.articulo
     set cantidad_estimada = false, conteo_desconocido = false, estado_inventario = estado
   where id = p_articulo;
  update public.tarea_pendiente
     set resuelta = true, resuelta_por = yo.id, resuelta_en = now(),
         nota_resolucion = format('Conteo físico: %s en el taller (%s)', p_en_taller, lower(etiqueta))
   where articulo_id = p_articulo and tipo = 'CONTAR' and not resuelta;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'CONTEO', 'articulo', p_articulo::text,
          jsonb_build_object('en_sistema', e.en_taller, 'contados', p_en_taller, 'diferencia', diferencia, 'motivo', p_motivo));
  return jsonb_build_object('diferencia', diferencia, 'estado', estado);
end $$;

-- p_cantidad null = baja total del artículo.
create function public.baja_registrar(p_articulo uuid, p_cantidad integer, p_de_fuera_de_servicio boolean,
                                      p_motivo text, p_justificacion text, p_oficio text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo       public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  a        public.articulo;
  e        record;
  etiqueta text;
  nota     text;
  total    boolean := p_cantidad is null;
begin
  select * into a from public.articulo where id = p_articulo for update;
  if not found or not a.activo then
    raise exception 'El artículo no existe o ya está dado de baja.';
  end if;
  etiqueta := case p_motivo
    when 'IRREPARABLE' then 'Irreparable' when 'OBSOLETO' then 'Obsoleto'
    when 'PERDIDA_CONFIRMADA' then 'Pérdida confirmada' when 'DONACION' then 'Donación o transferencia'
    when 'OTRO' then 'Otro' end;
  if etiqueta is null then
    raise exception 'Elige el motivo de la baja.';
  end if;
  if length(btrim(coalesce(p_justificacion, ''))) < 15 then
    raise exception 'Explica la baja (al menos 15 letras).';
  end if;
  if exists (select 1 from public.incidencia i where i.articulo_id = p_articulo and i.estado = 'PENDIENTE') then
    raise exception 'Primero resuelve los reportes pendientes de este artículo.';
  end if;
  perform app.exigir_confirmacion();

  select * into e from public.v_existencias where articulo_id = p_articulo;
  nota := etiqueta || ': ' || btrim(p_justificacion) || coalesce(' (oficio ' || nullif(btrim(p_oficio), '') || ')', '');

  if total then
    if e.prestado > 0 then
      raise exception 'Hay % prestados: primero deben regresar o confirmarse como perdidos.', e.prestado;
    end if;
    if e.apartado > 0 then
      raise exception 'Hay % apartados para una solicitud aprobada.', e.apartado;
    end if;
    if e.fuera_servicio > 0 then
      insert into public.movimiento (articulo_id, tipo, cantidad, de_fuera_de_servicio, nota, autorizado_por, registrado_por, origen)
      values (p_articulo, 'BAJA', e.fuera_servicio, true, nota, yo.id, yo.id, 'APP');
    end if;
    if e.en_taller > 0 then
      insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
      values (p_articulo, 'BAJA', e.en_taller, nota, yo.id, yo.id, 'APP');
    end if;
    update public.articulo set activo = false, estado_inventario = 'DADO_DE_BAJA', baja_oficio = nullif(btrim(p_oficio), '')
     where id = p_articulo;
  else
    if p_cantidad <= 0 then
      raise exception 'La cantidad debe ser mayor a cero.';
    end if;
    insert into public.movimiento (articulo_id, tipo, cantidad, de_fuera_de_servicio, nota, autorizado_por, registrado_por, origen)
    values (p_articulo, 'BAJA', p_cantidad, coalesce(p_de_fuera_de_servicio, false), nota, yo.id, yo.id, 'APP');
  end if;

  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, case when total then 'BAJA_TOTAL' else 'BAJA_PARCIAL' end, 'articulo', p_articulo::text,
          jsonb_build_object('motivo', p_motivo, 'oficio', nullif(btrim(p_oficio), ''), 'cantidad', p_cantidad));
  return jsonb_build_object('total', total,
    'en_tramite', total and a.num_resguardo is not null and btrim(coalesce(p_oficio, '')) = '');
end $$;

create function public.baja_registrar_oficio(p_articulo uuid, p_oficio text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  if btrim(coalesce(p_oficio, '')) = '' then
    raise exception 'Escribe el número de oficio.';
  end if;
  update public.articulo set baja_oficio = btrim(p_oficio) where id = p_articulo and not activo;
  if not found then
    raise exception 'Solo se registra oficio en un artículo dado de baja.';
  end if;
end $$;

create function public.articulo_reactivar(p_articulo uuid, p_cantidad integer, p_justificacion text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  a  public.articulo;
begin
  select * into a from public.articulo where id = p_articulo for update;
  if not found or a.estado_inventario <> 'DADO_DE_BAJA' then
    raise exception 'Solo se reactiva un artículo dado de baja.';
  end if;
  if length(btrim(coalesce(p_justificacion, ''))) < 15 then
    raise exception 'Explica por qué se reactiva (al menos 15 letras).';
  end if;
  if p_cantidad is null or p_cantidad < 0 then
    raise exception 'Escribe cuántos hay.';
  end if;
  perform app.exigir_confirmacion();

  update public.articulo
     set activo = true, baja_oficio = null,
         estado_inventario = case when categoria = 'SIN_CLASIFICAR' then 'SIN_CLASIFICAR' else 'POR_VERIFICAR' end::public.estado_inventario
   where id = p_articulo;
  update public.articulo set estado_inventario = app.estado_tras_conteo(p_articulo) where id = p_articulo;
  if p_cantidad > 0 then
    insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
    values (p_articulo, 'ALTA', p_cantidad, 'Reactivación: ' || btrim(p_justificacion), yo.id, yo.id, 'APP');
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'REACTIVACION', 'articulo', p_articulo::text, jsonb_build_object('cantidad', p_cantidad));
end $$;

-- ---------------------------------------------------------------------
-- Lecturas
-- ---------------------------------------------------------------------
-- Número público (sin nombres) para la franja del Inicio.
create function public.vencidos_contar() returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from app.v_prestamos_abiertos where vencido
$$;

-- Préstamos abiertos de un artículo, para recibir su devolución. Un docente ve aquí el nombre
-- del préstamo que está recibiendo (P-13), pero no la lista general.
create function public.prestamos_de_articulo(p_articulo uuid)
returns table (prestamo_id uuid, cantidad_prestada integer, pendiente integer, fecha timestamptz, vence_en timestamptz,
               vencido boolean, a_cargo text, autorizo text, grupo uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select pa.prestamo_id, pa.cantidad_prestada, pa.pendiente::integer, pa.fecha, pa.vence_en, pa.vencido,
           coalesce(app.nombre_usuario(pa.responsable_usuario_id), app.nombre_solicitante(pa.responsable_solicitante_id)),
           app.nombre_usuario(pa.autorizado_por), pa.grupo
    from app.v_prestamos_abiertos pa
    where pa.articulo_id = p_articulo
    order by pa.vence_en;
end $$;

-- Lo que está a mi nombre, o lo que yo presté a alumnos y maestros sin cuenta.
create function public.mis_prestamos()
returns table (prestamo_id uuid, articulo_id uuid, codigo text, nombre text, unidad text, pendiente integer,
               vence_en timestamptz, vencido boolean, a_mi_nombre boolean, a_cargo text, grupo uuid)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  return query
    select pa.prestamo_id, a.id, a.codigo, a.nombre, a.unidad, pa.pendiente::integer, pa.vence_en, pa.vencido,
           pa.responsable_usuario_id is not distinct from yo.id,
           coalesce(app.nombre_usuario(pa.responsable_usuario_id), app.nombre_solicitante(pa.responsable_solicitante_id)),
           pa.grupo
    from app.v_prestamos_abiertos pa
    join public.articulo a on a.id = pa.articulo_id
    where pa.responsable_usuario_id = yo.id
       or (pa.autorizado_por = yo.id and pa.responsable_solicitante_id is not null)
    order by pa.vence_en;
end $$;

create function public.prestamos_abiertos_listar()
returns table (prestamo_id uuid, articulo_id uuid, codigo text, nombre text, unidad text, pendiente integer,
               fecha timestamptz, vence_en timestamptz, vencido boolean, a_cargo text, autorizo text, extensiones integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select pa.prestamo_id, a.id, a.codigo, a.nombre, a.unidad, pa.pendiente::integer, pa.fecha, pa.vence_en, pa.vencido,
           coalesce(app.nombre_usuario(pa.responsable_usuario_id), app.nombre_solicitante(pa.responsable_solicitante_id)),
           app.nombre_usuario(pa.autorizado_por), pa.extensiones
    from app.v_prestamos_abiertos pa
    join public.articulo a on a.id = pa.articulo_id
    order by pa.vencido desc, pa.vence_en;
end $$;

-- Historial con nombres (solo responsable y sub administración), con las extensiones intercaladas.
create function public.historial_articulo(p_articulo uuid)
returns table (id uuid, tipo text, cantidad integer, fecha timestamptz, nota text, autorizo text, registro text,
               a_cargo text, origen text, conflicto boolean, prestamo_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select m.id, m.tipo::text, m.cantidad, m.fecha, m.nota, app.nombre_usuario(m.autorizado_por),
           app.nombre_usuario(m.registrado_por),
           coalesce(app.nombre_usuario(m.responsable_usuario_id), app.nombre_solicitante(m.responsable_solicitante_id)),
           m.origen::text, m.conflicto, m.movimiento_origen_id
    from public.movimiento m where m.articulo_id = p_articulo
    union all
    select e.id, 'EXTENSION', null::integer, e.extendida_en,
           format('Nueva fecha: %s. %s', app.hora_local(e.fecha_nueva), e.motivo),
           app.nombre_usuario(e.extendida_por), app.nombre_usuario(e.extendida_por), null, 'APP', false, e.prestamo_id
    from public.prestamo_extension e join public.movimiento p on p.id = e.prestamo_id
    where p.articulo_id = p_articulo
    order by 4 desc;
end $$;

create function public.por_revisar_contar() returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  if yo.rol = 'DOCENTE' then
    return 0;
  end if;
  return (select count(*)::integer from public.incidencia where estado = 'PENDIENTE');
end $$;

create function public.por_revisar()
returns table (id uuid, tipo text, articulo_id uuid, codigo text, nombre text, unidad text, cantidad integer,
               en_taller boolean, nota text, sin_foto_justificacion text, reportada_por text, reportada_en timestamptz,
               a_cargo text, fotos text[], comentarios jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select i.id, i.tipo::text, a.id, a.codigo, a.nombre, a.unidad, i.cantidad, i.en_taller, i.nota, i.sin_foto_justificacion,
           app.nombre_usuario(i.reportada_por), i.reportada_en,
           coalesce(app.nombre_usuario(i.responsable_usuario_id), app.nombre_solicitante(i.responsable_solicitante_id)),
           coalesce((select array_agg(f.url order by f.tomada_en) from public.foto f where f.incidencia_id = i.id), '{}'),
           coalesce((select jsonb_agg(jsonb_build_object('autor', app.nombre_usuario(c.autor_id), 'texto', c.texto, 'en', c.en)
                                      order by c.en)
                     from public.incidencia_comentario c where c.incidencia_id = i.id), '[]'::jsonb)
    from public.incidencia i join public.articulo a on a.id = i.articulo_id
    where i.estado = 'PENDIENTE'
    order by i.tipo = 'CONSUMO', i.reportada_en;
end $$;

create function public.mis_reportes()
returns table (id uuid, tipo text, estado text, articulo_id uuid, codigo text, nombre text, cantidad integer, nota text,
               reportada_en timestamptz, resuelta_por text, motivo_resolucion text, fotos text[], comentarios jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  return query
    select i.id, i.tipo::text, i.estado::text, a.id, a.codigo, a.nombre, i.cantidad, i.nota, i.reportada_en,
           app.nombre_usuario(i.resuelta_por), i.motivo_resolucion,
           coalesce((select array_agg(f.url order by f.tomada_en) from public.foto f where f.incidencia_id = i.id), '{}'),
           coalesce((select jsonb_agg(jsonb_build_object('autor', app.nombre_usuario(c.autor_id), 'texto', c.texto, 'en', c.en)
                                      order by c.en)
                     from public.incidencia_comentario c where c.incidencia_id = i.id), '[]'::jsonb)
    from public.incidencia i join public.articulo a on a.id = i.articulo_id
    where i.reportada_por = yo.id
    order by i.estado <> 'PENDIENTE', i.reportada_en desc
    limit 100;
end $$;

-- Bitácora completa: solo sub administración.
create function public.bitacora_listar(p_antes bigint default null, p_limite integer default 100)
returns table (id bigint, en timestamptz, usuario text, evento text, tabla text, registro_id text, referencia text, datos jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['SUBADMIN']::public.rol_usuario[]);
  return query
    select b.id, b.en, app.nombre_usuario(b.usuario_id), b.evento, b.tabla, b.registro_id,
           case b.tabla
             when 'articulo' then (select a.codigo || ' ' || a.nombre from public.articulo a where a.id::text = b.registro_id)
             when 'usuario' then app.nombre_usuario(nullif(b.registro_id, '')::uuid)
             when 'solicitante' then app.nombre_solicitante(nullif(b.registro_id, '')::uuid)
           end,
           b.datos
    from public.bitacora b
    where p_antes is null or b.id < p_antes
    order by b.id desc
    limit least(greatest(coalesce(p_limite, 100), 1), 500);
end $$;

-- ---------------------------------------------------------------------
-- Permisos de ejecución
-- ---------------------------------------------------------------------
revoke execute on all functions in schema app from public;
grant execute on function app.puede_subir_foto(), app.puede_subir_privado(text), app.puede_ver_privado(text) to authenticated;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma, p.proname
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('vencidos_contar', 'solicitante_buscar', 'solicitante_crear_rapido', 'prestamo_registrar',
                        'prestamo_deshacer', 'prestamo_extender', 'devolucion_registrar', 'incidencia_reportar',
                        'consumo_registrar', 'incidencia_resolver', 'incidencia_comentar', 'reparacion_registrar',
                        'ajuste_conteo', 'baja_registrar', 'baja_registrar_oficio', 'articulo_reactivar',
                        'prestamos_de_articulo', 'mis_prestamos', 'prestamos_abiertos_listar', 'historial_articulo',
                        'por_revisar_contar', 'por_revisar', 'mis_reportes', 'bitacora_listar')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.proname = 'vencidos_contar' then
      execute format('grant execute on function %s to anon, authenticated', f.firma);
    else
      execute format('grant execute on function %s to authenticated', f.firma);
    end if;
  end loop;
end $$;

grant select on public.v_inventario to anon, authenticated;
