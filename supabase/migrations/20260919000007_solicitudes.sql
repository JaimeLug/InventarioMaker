-- =====================================================================
-- 0007 · Solicitudes sin cuenta, entrega con código, avisos y adeudos (Fase 3b)
--
-- Flujos: F-04 alumno sin cuenta, F-04b verificación de identidad, F-05 maestro sin cuenta,
-- F-06 aprobar, rechazar y entregar, F-18 adeudos y expediente.
--
-- Decisiones de la Fase 3b (aprobadas el 2026-09-16):
--   * La solicitud se confirma con un enlace que llega al correo de la ficha. Hasta entonces
--     no aparece en la bandeja. El responsable también puede confirmarla en persona.
--   * Los correos y avisos al celular salen de una cola (tabla envio) que vacía la función
--     del servidor "avisos". Así un correo que falla se reintenta y nada se pierde.
--   * Freno: una solicitud en curso por persona; 5 por hora por dispositivo y 30 por hora por red
--     (en la escuela todos los celulares salen a internet por la misma red).
--   * Las fotos de identificación se borran al terminar el ciclo escolar si la persona ya no debe
--     nada. Es la única excepción a "nada se borra": el registro de la foto se queda y el borrado
--     se anota en la bitácora.
--
-- Nadie sin sesión toca las tablas: la solicitud se crea por la función "solicitud-publica"
-- (que conoce la red de quien pide) y el estado se consulta con el enlace secreto.
-- =====================================================================

-- Solo se usa dentro de funciones plpgsql: un valor nuevo de un tipo no se puede usar en la
-- misma transacción que lo crea.
alter type public.tipo_foto add value if not exists 'IDENTIFICACION';

insert into public.configuracion (clave, valor, descripcion) values
  ('plazo_default_dias',              '7',                        'Días de préstamo que se proponen en una solicitud'),
  ('solicitud_confirmar_horas',       '24',                       'Horas para confirmar la solicitud desde el correo antes de cancelarla'),
  ('solicitudes_por_hora_dispositivo','5',                        'Solicitudes nuevas por hora desde un mismo dispositivo'),
  ('solicitudes_por_hora_red',        '30',                       'Solicitudes nuevas por hora desde una misma red'),
  ('fin_ciclo_escolar',               '"2027-07-10"',             'Fin del ciclo escolar: después se borran las fotos de identificación de quien ya no debe nada'),
  ('url_app',                         '"http://localhost:8123"',  'Dirección de la app web, para los enlaces de los correos'),
  ('url_funciones',                   'null',                     'Dirección de las funciones del servidor (la llena scripts/desplegar.py)'),
  ('identificacion_ver_minutos',      '5',                        'Minutos para ver una foto de identificación después de pedirla (queda en la bitácora)')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------
alter table public.solicitante
  add column correo_confirmado_en       timestamptz,
  add column bloqueo_motivo             text,
  add column permitir_con_adeudo_hasta  timestamptz;
comment on column public.solicitante.bloqueado is
  'Copia para listados: la actualiza la tarea periódica. Las decisiones usan app.impedimento_solicitante().';
comment on column public.solicitante.permitir_con_adeudo_hasta is
  'Desbloqueo del responsable (N3): puede pedir aunque tenga algo vencido, hasta esta hora.';

alter table public.solicitud
  add column confirmada_en        timestamptz,
  add column confirmada_como      text check (confirmada_como in ('CORREO', 'EN_PERSONA')),
  add column confirmada_por       uuid references public.usuario (id),
  add column nota_aprobacion      text,
  add column rechazada_por        uuid references public.usuario (id),
  add column rechazada_en         timestamptz,
  add column cancelada_por        uuid references public.usuario (id),
  add column cancelada_en         timestamptz,
  add column entregada_por        uuid references public.usuario (id),
  add column tipo_identificacion  text check (tipo_identificacion in ('TRANSPORTE', 'DOCUMENTO_ESCOLAR', 'INE', 'OTRA')),
  add column no_fui_yo_en         timestamptz,
  add column otro_correo          boolean not null default false,
  add column ip_hash              text,
  add column dispositivo          text,
  add constraint solicitud_confirmada check ((confirmada_en is null) = (confirmada_como is null));
comment on column public.solicitud.token_hash is 'Sin uso: los enlaces secretos están en solicitud_enlace (puede haber varios).';
comment on column public.solicitud.firma_url is 'Sin uso: no hay firma; la evidencia es la foto de identificación (F-04b).';
comment on column public.solicitud.otro_correo is 'Quien pidió dijo que el correo registrado con esa matrícula no es suyo: revisar la ficha.';

alter table public.codigo_entrega
  alter column codigo_hash drop not null,
  add column codigo                  text,
  add column entrega_anulada_en      timestamptz,
  add column entrega_anulada_motivo  text;
comment on column public.codigo_entrega.codigo is
  'Legible a propósito: quien entrega debe poder volver a mostrarlo mientras está vigente. Solo lo leen responsable y sub administración.';

-- Enlaces secretos a una solicitud. Se guarda solo su huella: el enlace no se puede reconstruir.
-- "confirma" = llegó por correo: sirve para confirmar y para decir "no fui yo".
create table public.solicitud_enlace (
  token_hash    text primary key,
  solicitud_id  uuid not null references public.solicitud (id),
  confirma      boolean not null,
  creado_en     timestamptz not null default now()
);
create index solicitud_enlace_solicitud_idx on public.solicitud_enlace (solicitud_id);

alter table public.foto
  add column borrada_en      timestamptz,
  add column borrada_motivo  text;
comment on column public.foto.borrada_en is 'Solo fotos de identificación: el archivo se borró por la regla de conservación (P-14).';

-- Freno contra abusos en lo público.
create table public.limite_evento (
  id     bigint generated always as identity primary key,
  tipo   text not null,
  clave  text not null,
  en     timestamptz not null default now()
);
create index limite_evento_idx on public.limite_evento (tipo, clave, en);

-- Avisos dentro de la app (campana) para quien tiene cuenta.
create table public.aviso (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.usuario (id),
  titulo      text not null,
  cuerpo      text,
  ruta        text,
  creado_en   timestamptz not null default now(),
  leido_en    timestamptz
);
create index aviso_usuario_idx on public.aviso (usuario_id, creado_en desc);

-- Celulares Android que reciben avisos.
create table public.dispositivo (
  token          text primary key,
  usuario_id     uuid not null references public.usuario (id),
  plataforma     text not null default 'android',
  registrado_en  timestamptz not null default now(),
  visto_en       timestamptz not null default now(),
  activo         boolean not null default true
);
create index dispositivo_usuario_idx on public.dispositivo (usuario_id) where activo;

-- Cola de correos y avisos al celular.
create table public.envio (
  id          bigint generated always as identity primary key,
  canal       text not null check (canal in ('CORREO', 'PUSH')),
  destino     text not null,
  asunto      text not null,
  cuerpo      text not null,
  datos       jsonb not null default '{}',
  clave       text unique,
  estado      text not null default 'PENDIENTE' check (estado in ('PENDIENTE', 'ENVIANDO', 'ENVIADO', 'FALLIDO')),
  intentos    integer not null default 0,
  creado_en   timestamptz not null default now(),
  tomado_en   timestamptz,
  enviado_en  timestamptz,
  error       text
);
create index envio_pendiente_idx on public.envio (canal, id) where estado in ('PENDIENTE', 'ENVIANDO');
comment on column public.envio.clave is 'Evita mandar dos veces el mismo recordatorio.';

do $$
declare
  t text;
begin
  foreach t in array array['solicitud_enlace', 'limite_evento', 'aviso', 'dispositivo', 'envio'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('create trigger sin_borrado before delete on public.%I for each row execute function app.prohibir_borrado()', t);
  end loop;
end $$;
create trigger solo_agregar before update or delete on public.solicitud_enlace for each row execute function app.prohibir_edicion();
create trigger solo_agregar before update or delete on public.limite_evento    for each row execute function app.prohibir_edicion();

create index solicitud_confirmada_idx on public.solicitud (estado, confirmada_en);
create index codigo_entrega_solicitud_idx on public.codigo_entrega (solicitud_id, generado_en desc);
create index foto_solicitud_idx on public.foto (solicitud_id) where solicitud_id is not null;

-- Todos los préstamos (abiertos y cerrados), para historial, retrasos y expediente.
create view app.v_prestamos as
select
  p.id                                  as prestamo_id,
  p.articulo_id,
  p.cantidad,
  p.fecha,
  p.cantidad - coalesce(c.cerrado, 0)   as pendiente,
  c.ultimo                              as cerrado_en,
  v.vence_en,
  p.responsable_usuario_id,
  p.responsable_solicitante_id,
  p.autorizado_por,
  p.registrado_por,
  p.solicitud_id,
  coalesce(p.grupo, p.id)               as grupo,
  p.nota
from public.movimiento p
left join lateral (
  select sum(h.cantidad) as cerrado, max(h.fecha) as ultimo
  from public.movimiento h
  where h.movimiento_origen_id = p.id and h.tipo in ('DEVOLUCION', 'PERDIDA')
) c on true
left join public.solicitud s on s.id = p.solicitud_id
left join lateral (
  select (array_agg(e.fecha_nueva order by e.extendida_en desc))[1] as ultima
  from public.prestamo_extension e where e.prestamo_id = p.id
) x on true
cross join lateral (
  select coalesce(x.ultima, p.fecha_compromiso, s.fecha_devolucion_comprometida,
                  p.fecha + make_interval(days => app.config_int('dias_vencimiento'))) as vence_en
) v
where p.tipo = 'PRESTAMO';
revoke all on app.v_prestamos from anon, authenticated;

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create function app.huella(p text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(p, 'UTF8'), 'sha256'), 'hex')
$$;

create function app.token_nuevo() returns text
language sql volatile set search_path = '' as $$
  select encode(extensions.gen_random_bytes(24), 'hex')
$$;

create function app.codigo_seis() returns text
language sql volatile set search_path = '' as $$
  select lpad(((get_byte(b, 0)::bigint * 16777216 + get_byte(b, 1) * 65536 + get_byte(b, 2) * 256 + get_byte(b, 3))
               % 1000000)::text, 6, '0')
  from (select extensions.gen_random_bytes(4) as b) x
$$;

create function app.fecha_local(p timestamptz) returns text
language sql stable set search_path = '' as $$
  select to_char(p at time zone app.zona_horaria(), 'DD/MM/YYYY')
$$;

-- Una fecha a la hora de fin de jornada, en Mérida.
create function app.al_fin_de_jornada(p_dia date) returns timestamptz
language sql stable set search_path = '' as $$
  select ((p_dia + app.config_texto('hora_fin_jornada')::time)::timestamp at time zone app.zona_horaria())
$$;

-- Lunes a viernes. Los días festivos no se descuentan.
create function app.dias_habiles_despues(p_desde timestamptz, p_dias integer) returns date
language plpgsql stable set search_path = '' as $$
declare
  d date := (p_desde at time zone app.zona_horaria())::date;
  n integer := 0;
begin
  while n < p_dias loop
    d := d + 1;
    if extract(isodow from d) < 6 then
      n := n + 1;
    end if;
  end loop;
  return d;
end $$;

create function app.enmascarar_correo(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null or position('@' in p) < 2 then null
              else left(p, 1) || '***' || substr(p, position('@' in p)) end
$$;

create function app.iniciales(p text) returns text
language sql immutable set search_path = '' as $$
  select string_agg(upper(left(w, 1)) || '.', ' ')
  from regexp_split_to_table(btrim(coalesce(p, '')), '\s+') w
  where w <> ''
$$;

-- Qué impide que una persona pida o se lleve material. null = nada.
create function app.impedimento_solicitante(p_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  s public.solicitante;
  v record;
begin
  select * into s from public.solicitante where id = p_id;
  if not found then
    return 'No está registrada.';
  end if;
  if s.bloqueo_manual then
    return 'Tiene un bloqueo: ' || coalesce(nullif(btrim(s.bloqueo_motivo), ''), 'habla con el responsable del laboratorio') || '.';
  end if;
  if coalesce(s.permitir_con_adeudo_hasta > now(), false) then
    return null;
  end if;
  select coalesce(sol.folio, 'préstamo directo') as folio, pa.vence_en into v
    from app.v_prestamos_abiertos pa
    left join public.solicitud sol on sol.id = pa.solicitud_id
    where pa.responsable_solicitante_id = p_id and pa.vencido
    order by pa.vence_en limit 1;
  if found then
    return format('Tiene material pendiente de devolver (%s, desde el %s).', v.folio, app.fecha_local(v.vence_en));
  end if;
  return null;
end $$;

create function app.lista_articulos(p_solicitud uuid, p_aprobadas boolean default false) returns text
language sql stable security definer set search_path = '' as $$
  select string_agg(format('  • %s × %s (%s)', case when p_aprobadas then coalesce(l.cantidad_aprobada, l.cantidad) else l.cantidad end,
                           a.nombre, a.codigo), E'\n' order by a.nombre)
  from public.solicitud_linea l join public.articulo a on a.id = l.articulo_id
  where l.solicitud_id = p_solicitud and (not p_aprobadas or coalesce(l.cantidad_aprobada, l.cantidad) > 0)
$$;

-- ---------------------------------------------------------------------
-- Correos y avisos (cola)
-- ---------------------------------------------------------------------
create function app.encolar_correo(p_destino text, p_asunto text, p_cuerpo text, p_clave text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if btrim(coalesce(p_destino, '')) = '' then
    return;
  end if;
  insert into public.envio (canal, destino, asunto, cuerpo, clave)
  values ('CORREO', lower(btrim(p_destino)), p_asunto, p_cuerpo, p_clave)
  on conflict (clave) do nothing;
end $$;

-- Nuevo enlace secreto (de correo) para una solicitud: la dirección completa, lista para el correo.
create function app.enlace_correo(p_solicitud uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  t text := app.token_nuevo();
begin
  insert into public.solicitud_enlace (token_hash, solicitud_id, confirma) values (app.huella(t), p_solicitud, true);
  return rtrim(coalesce(app.config_texto('url_app'), ''), '/') || '/s/' || t;
end $$;

-- Correo al solicitante de una solicitud. Los avisos al celular nunca llevan nombres de alumnos.
create function app.correo_solicitante(p_solicitud uuid, p_asunto text, p_texto text, p_con_enlace boolean default true,
                                       p_clave text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  s   public.solicitud;
  per public.solicitante;
begin
  select * into s from public.solicitud where id = p_solicitud;
  select * into per from public.solicitante where id = s.solicitante_id;
  if per.correo is null then
    return;
  end if;
  perform app.encolar_correo(per.correo, p_asunto || ' (' || s.folio || ')',
    format(E'Hola, %s:\n\n%s%s\n\nLaboratorio Maker',
           split_part(per.nombre_completo, ' ', 1), p_texto,
           case when p_con_enlace then E'\n\nConsulta tu solicitud aquí:\n' || app.enlace_correo(p_solicitud) else '' end),
    p_clave);
end $$;

create function app.avisar_responsables(p_titulo text, p_cuerpo text, p_ruta text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.aviso (usuario_id, titulo, cuerpo, ruta)
  select u.id, p_titulo, p_cuerpo, p_ruta from public.usuario u where u.activo and u.rol = 'RESPONSABLE';
  if not found then
    insert into public.aviso (usuario_id, titulo, cuerpo, ruta)
    select u.id, p_titulo, p_cuerpo, p_ruta from public.usuario u where u.activo and u.rol = 'SUBADMIN';
  end if;
end $$;

create function app.aviso_a_celular() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.envio (canal, destino, asunto, cuerpo, datos)
  select 'PUSH', d.token, new.titulo, coalesce(new.cuerpo, ''), jsonb_build_object('ruta', new.ruta)
  from public.dispositivo d where d.usuario_id = new.usuario_id and d.activo;
  return new;
end $$;
create trigger al_celular after insert on public.aviso for each row execute function app.aviso_a_celular();

-- Despierta a la función "avisos" para que mande lo que haya en la cola. En Supabase usa pg_net
-- (la petición sale al confirmar la transacción); en la base local no hace nada.
create function app.despertar_envios() returns void
language plpgsql security definer set search_path = '' as $$
declare
  url text := app.config_texto('url_funciones');
begin
  if url is null or not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := ''{}''::jsonb)' using rtrim(url, '/') || '/avisos';
exception when others then
  raise warning 'No se pudo despertar la cola de envíos: %', sqlerrm;
end $$;

create function app.tras_encolar() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app.despertar_envios();
  return null;
end $$;
create trigger despertar after insert on public.envio for each statement execute function app.tras_encolar();

-- Los reportes de pérdida y daño también avisan (decisión de la Fase 3: avisos dentro de la app).
create function app.aviso_incidencia() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo <> 'CONSUMO' then
    perform app.avisar_responsables(
      case new.tipo when 'PERDIDA' then 'Reporte de pérdida' else 'Reporte de daño' end,
      (select format('%s de %s', new.cantidad, a.nombre) from public.articulo a where a.id = new.articulo_id),
      '/por-revisar');
  end if;
  return new;
end $$;
create trigger avisar after insert on public.incidencia for each row execute function app.aviso_incidencia();

-- ---------------------------------------------------------------------
-- Estados de una solicitud
-- ---------------------------------------------------------------------
create function app.cancelar_solicitud(p_id uuid, p_motivo text, p_por uuid, p_correo text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  s public.solicitud;
begin
  select * into s from public.solicitud where id = p_id for update;
  if s.estado not in ('PENDIENTE', 'APROBADA') then
    raise exception 'Esta solicitud ya no se puede cancelar (está %).', lower(s.estado::text);
  end if;
  update public.solicitud
     set estado = 'CANCELADA', motivo_cancelacion = p_motivo, cancelada_por = p_por, cancelada_en = now()
   where id = p_id;
  update public.codigo_entrega
     set estado = case when expira_en <= now() then 'EXPIRADO' else 'ANULADO' end::public.estado_codigo
   where solicitud_id = p_id and estado = 'VIGENTE';
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (p_por, 'SOLICITUD_CANCELADA', 'solicitud', p_id::text, jsonb_build_object('folio', s.folio, 'motivo', p_motivo));
  if p_correo is not null and s.confirmada_en is not null then
    perform app.correo_solicitante(p_id, 'Solicitud cancelada', p_correo, false);
  end if;
end $$;

-- ENTREGADO, VENCIDA o DEVUELTA según sus préstamos.
create function app.actualizar_estado_solicitud(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  actual public.estado_solicitud;
  abiertos integer;
  vencido boolean;
  nuevo public.estado_solicitud;
begin
  select estado into actual from public.solicitud where id = p_id for update;
  if actual not in ('ENTREGADO', 'VENCIDA') then
    return;
  end if;
  select count(*), coalesce(bool_or(pa.vencido), false) into abiertos, vencido
    from app.v_prestamos_abiertos pa where pa.solicitud_id = p_id;
  nuevo := case when abiertos = 0 then 'DEVUELTA' when vencido then 'VENCIDA' else 'ENTREGADO' end;
  if nuevo <> actual then
    update public.solicitud set estado = nuevo where id = p_id;
    if nuevo = 'DEVUELTA' then
      perform app.correo_solicitante(p_id, 'Devolución completa',
        'Registramos la devolución de todo el material de esta solicitud. ¡Gracias!', false);
    end if;
  end if;
end $$;

create function app.tras_cierre_prestamo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  sol uuid;
begin
  if tg_table_name = 'movimiento' then
    if new.tipo not in ('DEVOLUCION', 'PERDIDA') or new.movimiento_origen_id is null then
      return new;
    end if;
    select m.solicitud_id into sol from public.movimiento m where m.id = new.movimiento_origen_id;
  else
    select m.solicitud_id into sol from public.movimiento m where m.id = new.prestamo_id;
  end if;
  if sol is not null then
    perform app.actualizar_estado_solicitud(sol);
  end if;
  return new;
end $$;
create trigger estado_solicitud after insert on public.movimiento         for each row execute function app.tras_cierre_prestamo();
create trigger estado_solicitud after insert on public.prestamo_extension for each row execute function app.tras_cierre_prestamo();

-- ---------------------------------------------------------------------
-- Código de entrega
-- ---------------------------------------------------------------------
create function app.codigo_generar(p_solicitud uuid, p_yo uuid, p_vigencia text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  expira timestamptz;
  nuevo  text := app.codigo_seis();
begin
  expira := case coalesce(p_vigencia, 'RATO')
    when 'RATO'   then now() + make_interval(mins => app.config_int('codigo_vigencia_minutos'))
    when 'HOY'    then app.fin_jornada()
    when 'MANANA' then now() + make_interval(hours => app.config_int('codigo_vigencia_max_horas'))
  end;
  if expira is null then
    raise exception 'Elige cuándo pasa a recoger.';
  end if;
  expira := least(greatest(expira, now() + make_interval(mins => app.config_int('codigo_vigencia_minutos'))),
                  now() + make_interval(hours => app.config_int('codigo_vigencia_max_horas')));

  update public.codigo_entrega
     set estado = case when expira_en <= now() then 'EXPIRADO' else 'ANULADO' end::public.estado_codigo
   where solicitud_id = p_solicitud and estado = 'VIGENTE';
  insert into public.codigo_entrega (solicitud_id, codigo, generado_por, expira_en)
  values (p_solicitud, nuevo, p_yo, expira);
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (p_yo, 'CODIGO_GENERADO', 'solicitud', p_solicitud::text, jsonb_build_object('expira_en', expira));
  return jsonb_build_object('codigo', nuevo, 'expira_en', expira);
end $$;

-- No lanza error al fallar: así los intentos fallidos se cuentan.
create function app.canjear_codigo(p_solicitud uuid, p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s      public.solicitud;
  c      public.codigo_entrega;
  maximo integer := app.config_int('codigo_intentos_max');
begin
  select * into s from public.solicitud where id = p_solicitud for update;
  if not found or s.estado <> 'APROBADA' then
    return jsonb_build_object('ok', false, 'motivo', 'ESTADO', 'mensaje', 'Esta solicitud no está lista para entregarse.');
  end if;
  select * into c from public.codigo_entrega where solicitud_id = p_solicitud order by generado_en desc limit 1 for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'SIN_CODIGO', 'mensaje', 'Pide al responsable que genere el código.');
  end if;
  if c.estado = 'USADO' and c.entrega_anulada_en is null then
    return jsonb_build_object('ok', true, 'mensaje', 'Código aceptado. Espera a que el responsable termine la entrega.');
  end if;
  if c.estado = 'VIGENTE' and c.expira_en <= now() then
    update public.codigo_entrega set estado = 'EXPIRADO' where id = c.id;
    return jsonb_build_object('ok', false, 'motivo', 'EXPIRADO', 'mensaje', 'El código venció. Pide al responsable uno nuevo.');
  end if;
  if c.estado <> 'VIGENTE' then
    return jsonb_build_object('ok', false, 'motivo', c.estado, 'mensaje', 'Ese código ya no sirve. Pide al responsable uno nuevo.');
  end if;

  if btrim(coalesce(p_codigo, '')) <> c.codigo then
    update public.codigo_entrega
       set intentos_fallidos = intentos_fallidos + 1,
           estado = case when intentos_fallidos + 1 >= maximo then 'BLOQUEADO' else 'VIGENTE' end::public.estado_codigo
     where id = c.id;
    if c.intentos_fallidos + 1 >= maximo then
      insert into public.bitacora (evento, tabla, registro_id) values ('CODIGO_BLOQUEADO', 'solicitud', p_solicitud::text);
      return jsonb_build_object('ok', false, 'motivo', 'BLOQUEADO',
                                'mensaje', 'Demasiados intentos. Pide al responsable un código nuevo.');
    end if;
    return jsonb_build_object('ok', false, 'motivo', 'INCORRECTO', 'restantes', maximo - c.intentos_fallidos - 1,
                              'mensaje', format('Código incorrecto. Te quedan %s intentos.', maximo - c.intentos_fallidos - 1));
  end if;

  update public.codigo_entrega set estado = 'USADO', usado_en = now() where id = c.id;
  insert into public.bitacora (evento, tabla, registro_id) values ('CODIGO_USADO', 'solicitud', p_solicitud::text);
  return jsonb_build_object('ok', true, 'mensaje', 'Código aceptado. Espera a que el responsable termine la entrega.');
end $$;

-- ---------------------------------------------------------------------
-- F-04 / F-05 Lado público (sin cuenta)
-- ---------------------------------------------------------------------
-- Solo la llama la función del servidor "solicitud-publica" (llave secreta), que agrega la red.
-- p_datos: {tipo, matricula, nombre, grupo, correo, telefono, quien (solo OTRO), motivo, detalle, fecha (AAAA-MM-DD),
--           lineas: [{articulo_id, cantidad}], otro_correo}
create function public.solicitud_publica_enviar(p_datos jsonb, p_ip text, p_dispositivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tipo        public.tipo_solicitante;
  v_matricula   text := btrim(coalesce(p_datos ->> 'matricula', ''));
  v_nombre      text := regexp_replace(btrim(coalesce(p_datos ->> 'nombre', '')), '\s+', ' ', 'g');
  v_correo      text := lower(btrim(coalesce(p_datos ->> 'correo', '')));
  v_dominio     text := app.config_texto('dominio_correo_alumnos');
  v_motivo      text := btrim(coalesce(p_datos ->> 'motivo', ''));
  v_detalle     text := nullif(btrim(coalesce(p_datos ->> 'detalle', '')), '');
  v_quien       text := nullif(btrim(coalesce(p_datos ->> 'quien', '')), '');
  v_otro_correo boolean := coalesce((p_datos ->> 'otro_correo')::boolean, false);
  v_ip_hash     text := app.huella('red:' || coalesce(p_ip, ''));
  v_disp        text := left(coalesce(nullif(btrim(p_dispositivo), ''), 'sin-dispositivo'), 64);
  v_plazo_max   integer;
  v_vence       timestamptz;
  v_existente   public.solicitante;
  v_ficha       uuid;
  v_reconocido  boolean := false;
  v_impedimento text;
  v_en_curso    text;
  l             jsonb;
  a             record;
  v_vistos      uuid[] := '{}';
  v_nueva       uuid;
  v_folio       text;
  v_token       text := app.token_nuevo();
  v_per         public.solicitante;
begin
  begin
    v_tipo := (p_datos ->> 'tipo')::public.tipo_solicitante;
  exception when others then
    raise exception 'Elige si eres alumno, maestro u otro.';
  end;
  if v_tipo is null then
    raise exception 'Elige si eres alumno, maestro u otro.';
  end if;
  if v_matricula = '' then
    raise exception '%', case when v_tipo = 'ALUMNO' then 'Escribe tu matrícula.' else 'Escribe tu clave de empleado o un dato que te identifique.' end;
  end if;
  if length(v_nombre) < 5 or position(' ' in v_nombre) = 0 then
    raise exception 'Escribe tu nombre completo.';
  end if;
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Escribe un correo válido: ahí te llega el enlace para confirmar.';
  end if;
  if v_tipo = 'ALUMNO' and v_correo !~ ('@' || replace(v_dominio, '.', '\.') || '$') then
    raise exception 'Usa tu correo institucional (@%).', v_dominio;
  end if;
  if v_tipo = 'OTRO' and v_quien is null then
    raise exception 'Escribe quién eres (por ejemplo: personal de intendencia, visitante de otra escuela).';
  end if;
  if v_motivo = '' then
    raise exception 'Elige para qué lo necesitas.';
  end if;
  if v_motivo = 'Otro' and v_detalle is null then
    raise exception 'Cuéntanos para qué lo necesitas.';
  end if;

  -- Freno contra abusos (solo cuentan las solicitudes que sí se crearon).
  if (select count(*) from public.limite_evento e
       where e.tipo = 'SOLICITUD' and e.clave = 'd:' || v_disp and e.en > now() - interval '1 hour')
     >= app.config_int('solicitudes_por_hora_dispositivo')
     or (select count(*) from public.limite_evento e
          where e.tipo = 'SOLICITUD' and e.clave = 'r:' || v_ip_hash and e.en > now() - interval '1 hour')
     >= app.config_int('solicitudes_por_hora_red') then
    raise exception 'Se enviaron demasiadas solicitudes desde aquí. Intenta más tarde o acude al laboratorio.';
  end if;

  -- Fecha de devolución (a la hora de fin de jornada).
  v_plazo_max := app.config_int(case when v_tipo = 'MAESTRO' then 'plazo_max_maestro_dias' else 'plazo_max_alumno_dias' end);
  if nullif(p_datos ->> 'fecha', '') is null then
    v_vence := app.al_fin_de_jornada(app.hoy() + app.config_int('plazo_default_dias'));
  else
    begin
      v_vence := app.al_fin_de_jornada((p_datos ->> 'fecha')::date);
    exception when others then
      raise exception 'La fecha de devolución no es válida.';
    end;
  end if;
  if v_vence <= now() then
    raise exception 'La fecha de devolución ya pasó.';
  end if;
  if (v_vence at time zone app.zona_horaria())::date > app.hoy() + v_plazo_max then
    raise exception 'La fecha de devolución puede ser a lo más en % días.', v_plazo_max;
  end if;

  -- Artículos.
  if jsonb_typeof(p_datos -> 'lineas') <> 'array' or jsonb_array_length(p_datos -> 'lineas') = 0 then
    raise exception 'Tu solicitud no tiene artículos.';
  end if;
  if jsonb_array_length(p_datos -> 'lineas') > 20 then
    raise exception 'Una solicitud puede tener hasta 20 artículos.';
  end if;
  for l in select * from jsonb_array_elements(p_datos -> 'lineas') loop
    select ar.id, ar.nombre, ar.activo, ar.es_consumible, e.prestable, e.disponible into a
      from public.articulo ar join public.v_existencias e on e.articulo_id = ar.id
      where ar.id = (l ->> 'articulo_id')::uuid;
    if not found or not a.activo then
      raise exception 'Uno de los artículos ya no está en el inventario.';
    end if;
    if a.id = any (v_vistos) then
      raise exception '"%" aparece dos veces.', a.nombre;
    end if;
    v_vistos := v_vistos || a.id;
    if a.es_consumible then
      raise exception '"%" es consumible: se pide en persona en el laboratorio.', a.nombre;
    end if;
    if not a.prestable then
      raise exception '"%" todavía no se puede prestar.', a.nombre;
    end if;
    if coalesce((l ->> 'cantidad')::integer, 0) <= 0 then
      raise exception 'La cantidad de "%" debe ser mayor a cero.', a.nombre;
    end if;
    if (l ->> 'cantidad')::integer > a.disponible then
      raise exception 'Mientras llenabas la solicitud cambió lo disponible: de "%" quedan %. Ajusta la cantidad.',
        a.nombre, greatest(a.disponible, 0);
    end if;
  end loop;

  -- Ficha. Si la matrícula ya existe y ya se comprobó (en persona o por correo), no se cambia desde aquí.
  select * into v_existente from public.solicitante s
   where s.tipo = v_tipo and lower(btrim(s.matricula_o_clave)) = lower(v_matricula) and not s.posible_duplicado
   for update;
  if found and (v_existente.verificada_en is not null or v_existente.correo_confirmado_en is not null) then
    v_reconocido := true;
    v_impedimento := app.impedimento_solicitante(v_existente.id);
    if v_impedimento is not null then
      raise exception 'No puedes pedir material. % Acude al laboratorio.', v_impedimento;
    end if;
    if v_otro_correo then
      insert into public.solicitante (nombre_completo, tipo, matricula_o_clave, grupo_area, correo, telefono, posible_duplicado, nota)
      values (v_nombre, v_tipo, v_matricula, nullif(btrim(p_datos ->> 'grupo'), ''), v_correo, nullif(btrim(p_datos ->> 'telefono'), ''),
              true, format('Dice que el correo registrado con la matrícula %s no es suyo. Ficha original: %s', v_matricula, v_existente.id))
      returning id into v_ficha;
    else
      v_ficha := v_existente.id;
    end if;
  elsif found then
    -- Nadie la ha comprobado: se toman los datos nuevos.
    update public.solicitante
       set nombre_completo = v_nombre, grupo_area = nullif(btrim(p_datos ->> 'grupo'), ''), correo = v_correo,
           telefono = nullif(btrim(p_datos ->> 'telefono'), ''), nota = v_quien
     where id = v_existente.id;
    v_ficha := v_existente.id;
  else
    insert into public.solicitante (nombre_completo, tipo, matricula_o_clave, grupo_area, correo, telefono, nota)
    values (v_nombre, v_tipo, v_matricula, nullif(btrim(p_datos ->> 'grupo'), ''), v_correo, nullif(btrim(p_datos ->> 'telefono'), ''), v_quien)
    returning id into v_ficha;
  end if;

  v_impedimento := app.impedimento_solicitante(v_ficha);
  if v_impedimento is not null then
    raise exception 'No puedes pedir material. % Acude al laboratorio.', v_impedimento;
  end if;

  -- Una solicitud en curso por persona. Las que nunca se confirmaron se reemplazan.
  select string_agg(s.folio, ', ') into v_en_curso from public.solicitud s
   where s.solicitante_id = v_ficha and s.estado in ('PENDIENTE', 'APROBADA') and s.confirmada_en is not null;
  if v_en_curso is not null then
    raise exception 'Ya tienes la solicitud % en curso. Espera a que se resuelva o cancélala desde su enlace.', v_en_curso;
  end if;
  perform app.cancelar_solicitud(s.id, 'Reemplazada por una solicitud nueva', null)
     from public.solicitud s
    where s.solicitante_id = v_ficha and s.estado = 'PENDIENTE' and s.confirmada_en is null;

  insert into public.solicitud (solicitante_id, motivo, fecha_devolucion_comprometida, otro_correo, ip_hash, dispositivo)
  values (v_ficha, v_motivo || coalesce(': ' || v_detalle, ''), v_vence, v_otro_correo, v_ip_hash, v_disp)
  returning solicitud.id, solicitud.folio into v_nueva, v_folio;
  insert into public.solicitud_linea (solicitud_id, articulo_id, cantidad)
  select v_nueva, (x ->> 'articulo_id')::uuid, (x ->> 'cantidad')::integer from jsonb_array_elements(p_datos -> 'lineas') x;
  insert into public.solicitud_enlace (token_hash, solicitud_id, confirma) values (app.huella(v_token), v_nueva, false);
  insert into public.limite_evento (tipo, clave) values ('SOLICITUD', 'd:' || v_disp), ('SOLICITUD', 'r:' || v_ip_hash);
  insert into public.bitacora (evento, tabla, registro_id, datos)
  values ('SOLICITUD_CREADA', 'solicitud', v_nueva::text, jsonb_build_object('folio', v_folio, 'reconocido', v_reconocido, 'otro_correo', v_otro_correo));

  select * into v_per from public.solicitante where id = v_ficha;
  perform app.correo_solicitante(v_nueva, 'Confirma tu solicitud',
    format(E'Se pidió este material del Laboratorio Maker a tu nombre:\n\n%s\n\nDevolución: %s.\n\n'
           'Abre el enlace y toca "Sí, yo lo pedí" para que llegue al responsable. '
           'Si no fuiste tú, abre el enlace y toca "No fui yo". Sin confirmar, la solicitud se cancela en %s horas.',
           app.lista_articulos(v_nueva), app.hora_local(v_vence), app.config_int('solicitud_confirmar_horas')));

  return jsonb_build_object('folio', v_folio, 'token', v_token, 'reconocido', v_reconocido,
                            'iniciales', app.iniciales(v_per.nombre_completo),
                            'correo', app.enmascarar_correo(v_per.correo), 'sin_correo', v_per.correo is null);
end $$;

create function app.solicitud_por_token(p_token text) returns public.solicitud_enlace
language sql stable security definer set search_path = '' as $$
  select * from public.solicitud_enlace where token_hash = app.huella(coalesce(p_token, ''))
$$;

-- Lo que ve quien tiene el enlace. Antes de confirmar, sin nombre completo.
create function app.solicitud_publica_json(p_id uuid, p_de_correo boolean) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  s   public.solicitud;
  per public.solicitante;
  c   public.codigo_entrega;
begin
  select * into s from public.solicitud where id = p_id;
  select * into per from public.solicitante where id = s.solicitante_id;
  select * into c from public.codigo_entrega where solicitud_id = p_id order by generado_en desc limit 1;
  return jsonb_build_object(
    'folio', s.folio,
    'estado', s.estado,
    'confirmada', s.confirmada_en is not null,
    'enlace_de_correo', p_de_correo,
    'creada_en', s.creada_en,
    'motivo', s.motivo,
    'fecha_devolucion', s.fecha_devolucion_comprometida,
    'recoger_hasta', s.recoger_hasta,
    'motivo_rechazo', s.motivo_rechazo,
    'motivo_cancelacion', s.motivo_cancelacion,
    'nota_aprobacion', s.nota_aprobacion,
    'entregada_en', s.entregada_en,
    'codigo_aceptado', c.estado = 'USADO' and c.entrega_anulada_en is null,
    'solicitante', case when s.confirmada_en is not null
                        then jsonb_build_object('nombre', per.nombre_completo, 'matricula', per.matricula_o_clave,
                                                'grupo', per.grupo_area, 'tipo', per.tipo)
                        else jsonb_build_object('nombre', app.iniciales(per.nombre_completo), 'tipo', per.tipo) end,
    'correo', app.enmascarar_correo(per.correo),
    'autorizo', app.nombre_usuario(s.autorizada_por),
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'articulo_id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'unidad', a.unidad,
                  'cantidad', l.cantidad, 'aprobada', l.cantidad_aprobada,
                  'pendiente', (select coalesce(sum(pa.pendiente), 0)::integer from app.v_prestamos_abiertos pa
                                 where pa.solicitud_id = s.id and pa.articulo_id = a.id)) order by a.nombre), '[]'::jsonb)
               from public.solicitud_linea l join public.articulo a on a.id = l.articulo_id where l.solicitud_id = s.id));
end $$;

create function public.solicitud_publica_estado(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  e public.solicitud_enlace := app.solicitud_por_token(p_token);
begin
  if e.solicitud_id is null then
    return null;
  end if;
  return app.solicitud_publica_json(e.solicitud_id, e.confirma);
end $$;

create function public.solicitud_publica_confirmar(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e public.solicitud_enlace := app.solicitud_por_token(p_token);
  s public.solicitud;
begin
  if e.solicitud_id is null or not e.confirma then
    raise exception 'Este enlace no sirve para confirmar. Usa el que llegó a tu correo.';
  end if;
  select * into s from public.solicitud where id = e.solicitud_id for update;
  if s.confirmada_en is null then
    if s.estado <> 'PENDIENTE' then
      raise exception 'Esta solicitud ya no está activa (%).', lower(s.estado::text);
    end if;
    update public.solicitud set confirmada_en = now(), confirmada_como = 'CORREO' where id = s.id;
    update public.solicitante set correo_confirmado_en = now() where id = s.solicitante_id and correo_confirmado_en is null;
    insert into public.bitacora (evento, tabla, registro_id, datos)
    values ('SOLICITUD_CONFIRMADA', 'solicitud', s.id::text, jsonb_build_object('folio', s.folio, 'como', 'CORREO'));
    perform app.avisar_responsables('Nueva solicitud ' || s.folio,
      (select format('%s artículo(s), %s pieza(s)', count(*), sum(l.cantidad)) from public.solicitud_linea l where l.solicitud_id = s.id),
      '/solicitudes/' || s.id);
  end if;
  return app.solicitud_publica_json(s.id, true);
end $$;

create function public.solicitud_publica_cancelar(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e public.solicitud_enlace := app.solicitud_por_token(p_token);
  s public.solicitud;
begin
  if e.solicitud_id is null then
    raise exception 'El enlace no es válido.';
  end if;
  select * into s from public.solicitud where id = e.solicitud_id;
  if s.estado in ('ENTREGADO', 'VENCIDA') then
    raise exception 'El material ya está a tu nombre: no se cancela, se devuelve en el laboratorio.';
  end if;
  perform app.cancelar_solicitud(s.id, 'Cancelada por el solicitante', null);
  if s.confirmada_en is not null then
    perform app.avisar_responsables('Solicitud ' || s.folio || ' cancelada', 'La canceló quien la pidió.', '/solicitudes/' || s.id);
  end if;
  return app.solicitud_publica_json(s.id, e.confirma);
end $$;

-- Solo desde el correo: el dueño del correo dice que no pidió (o no recibió) el material.
create function public.solicitud_publica_no_fui_yo(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e public.solicitud_enlace := app.solicitud_por_token(p_token);
  s public.solicitud;
begin
  if e.solicitud_id is null or not e.confirma then
    raise exception 'Usa el enlace que llegó a tu correo.';
  end if;
  select * into s from public.solicitud where id = e.solicitud_id for update;
  update public.solicitud set no_fui_yo_en = coalesce(no_fui_yo_en, now()) where id = s.id;
  insert into public.bitacora (evento, tabla, registro_id, datos)
  values ('NO_FUI_YO', 'solicitud', s.id::text, jsonb_build_object('folio', s.folio, 'estado', s.estado));
  if s.estado in ('PENDIENTE', 'APROBADA') then
    perform app.cancelar_solicitud(s.id, 'El dueño del correo dijo que no la pidió', null);
  end if;
  perform app.avisar_responsables('Alerta en ' || s.folio,
    case when s.estado in ('PENDIENTE', 'APROBADA') then 'El dueño del correo dijo que no pidió este material. Se canceló.'
         else 'El dueño del correo dijo que no recibió este material. Revisa la entrega.' end,
    '/solicitudes/' || s.id);
  return app.solicitud_publica_json(s.id, true);
end $$;

create function public.solicitud_publica_canjear(p_token text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e public.solicitud_enlace := app.solicitud_por_token(p_token);
begin
  if e.solicitud_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'ENLACE', 'mensaje', 'El enlace no es válido.');
  end if;
  return app.canjear_codigo(e.solicitud_id, p_codigo);
end $$;

-- Perdí el enlace: se manda uno nuevo al correo de la ficha. Siempre responde lo mismo,
-- para no revelar si el folio y la matrícula existen. Solo la función del servidor.
create function public.solicitud_publica_recuperar(p_folio text, p_matricula text, p_ip text, p_dispositivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  s    public.solicitud;
  disp text := left(coalesce(nullif(btrim(p_dispositivo), ''), 'sin-dispositivo'), 64);
begin
  if (select count(*) from public.limite_evento e
       where e.tipo = 'RECUPERAR' and e.clave in ('d:' || disp, 'r:' || app.huella('red:' || coalesce(p_ip, '')))
         and e.en > now() - interval '1 hour') >= 10 then
    return;
  end if;
  insert into public.limite_evento (tipo, clave)
  values ('RECUPERAR', 'd:' || disp), ('RECUPERAR', 'r:' || app.huella('red:' || coalesce(p_ip, '')));

  select sol.* into s from public.solicitud sol join public.solicitante per on per.id = sol.solicitante_id
   where upper(btrim(sol.folio)) = upper(btrim(coalesce(p_folio, '')))
     and lower(btrim(per.matricula_o_clave)) = lower(btrim(coalesce(p_matricula, '')));
  if found then
    perform app.correo_solicitante(s.id, 'Enlace a tu solicitud', 'Pediste de nuevo el enlace a tu solicitud.');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- F-06 Bandeja, aprobación, rechazo y entrega (responsable y sub administración)
-- ---------------------------------------------------------------------
create function public.solicitudes_contar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  if yo.rol = 'DOCENTE' then
    return jsonb_build_object('por_revisar', 0, 'por_entregar', 0, 'sin_confirmar', 0);
  end if;
  return (select jsonb_build_object(
            'por_revisar',   count(*) filter (where estado = 'PENDIENTE' and confirmada_en is not null),
            'por_entregar',  count(*) filter (where estado = 'APROBADA'),
            'sin_confirmar', count(*) filter (where estado = 'PENDIENTE' and confirmada_en is null))
          from public.solicitud where estado in ('PENDIENTE', 'APROBADA'));
end $$;

-- p_grupo: POR_REVISAR | SIN_CONFIRMAR | POR_ENTREGAR | EN_PRESTAMO | CERRADAS
create function public.solicitudes_listar(p_grupo text)
returns table (id uuid, folio text, estado text, creada_en timestamptz, confirmada_en timestamptz, solicitante text,
               verificada boolean, posible_duplicado boolean, articulos integer, piezas integer,
               fecha_devolucion timestamptz, recoger_hasta timestamptz, vencida boolean, alerta text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  if p_grupo not in ('POR_REVISAR', 'SIN_CONFIRMAR', 'POR_ENTREGAR', 'EN_PRESTAMO', 'CERRADAS') then
    raise exception 'Grupo desconocido: %', p_grupo;
  end if;
  return query
    select s.id, s.folio, s.estado::text, s.creada_en, s.confirmada_en, app.nombre_solicitante(s.solicitante_id),
           per.verificada_en is not null, per.posible_duplicado or s.otro_correo,
           (select count(*)::integer from public.solicitud_linea l where l.solicitud_id = s.id),
           (select coalesce(sum(coalesce(l.cantidad_aprobada, l.cantidad)), 0)::integer from public.solicitud_linea l where l.solicitud_id = s.id),
           s.fecha_devolucion_comprometida, s.recoger_hasta, s.estado = 'VENCIDA',
           case when s.no_fui_yo_en is not null then 'El dueño del correo dijo "no fui yo"'
                when per.posible_duplicado or s.otro_correo then 'Posible duplicado: revisa la identificación'
                when s.estado = 'PENDIENTE' then app.impedimento_solicitante(per.id) end
    from public.solicitud s join public.solicitante per on per.id = s.solicitante_id
    where case p_grupo
            when 'POR_REVISAR'   then s.estado = 'PENDIENTE' and s.confirmada_en is not null
            when 'SIN_CONFIRMAR' then s.estado = 'PENDIENTE' and s.confirmada_en is null
            when 'POR_ENTREGAR'  then s.estado = 'APROBADA'
            when 'EN_PRESTAMO'   then s.estado in ('ENTREGADO', 'VENCIDA')
            else s.estado in ('RECHAZADA', 'CANCELADA', 'DEVUELTA') end
    order by case when p_grupo = 'CERRADAS' then null else s.estado = 'VENCIDA' end desc nulls last,
             case when p_grupo = 'CERRADAS' then s.actualizado_en end desc nulls last,
             coalesce(s.confirmada_en, s.creada_en)
    limit 200;
end $$;

create function public.solicitud_detalle(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  s    public.solicitud;
  per  public.solicitante;
  hist record;
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  select * into s from public.solicitud where id = p_id;
  if not found then
    raise exception 'La solicitud no existe.';
  end if;
  select * into per from public.solicitante where id = s.solicitante_id;
  select count(distinct p.grupo)::integer as prestamos,
         count(distinct p.grupo) filter (where (case when p.pendiente > 0 then now() else p.cerrado_en end) > p.vence_en)::integer as con_retraso
    into hist
    from app.v_prestamos p where p.responsable_solicitante_id = per.id and p.solicitud_id is distinct from s.id;

  return jsonb_build_object(
    'id', s.id, 'folio', s.folio, 'estado', s.estado, 'motivo', s.motivo, 'creada_en', s.creada_en,
    'confirmada_en', s.confirmada_en, 'confirmada_como', s.confirmada_como, 'confirmada_por', app.nombre_usuario(s.confirmada_por),
    'fecha_devolucion', s.fecha_devolucion_comprometida, 'recoger_hasta', s.recoger_hasta,
    'autorizo', app.nombre_usuario(s.autorizada_por), 'autorizada_en', s.autorizada_en, 'nota_aprobacion', s.nota_aprobacion,
    'motivo_rechazo', s.motivo_rechazo, 'rechazo', app.nombre_usuario(s.rechazada_por),
    'motivo_cancelacion', s.motivo_cancelacion, 'cancelo', app.nombre_usuario(s.cancelada_por), 'cancelada_en', s.cancelada_en,
    'entregada_en', s.entregada_en, 'entrego', app.nombre_usuario(s.entregada_por), 'tipo_identificacion', s.tipo_identificacion,
    'no_fui_yo_en', s.no_fui_yo_en, 'otro_correo', s.otro_correo,
    'solicitante', jsonb_build_object(
      'id', per.id, 'nombre', per.nombre_completo, 'tipo', per.tipo, 'matricula', per.matricula_o_clave, 'grupo', per.grupo_area,
      'telefono', per.telefono, 'correo', per.correo, 'nota', per.nota,
      'verificada_por', app.nombre_usuario(per.verificada_por), 'verificada_en', per.verificada_en,
      'correo_confirmado', per.correo_confirmado_en is not null, 'posible_duplicado', per.posible_duplicado,
      'impedimento', app.impedimento_solicitante(per.id),
      'prestamos_anteriores', hist.prestamos, 'con_retraso', hist.con_retraso),
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'articulo_id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'unidad', a.unidad,
                  'foto', (select f.url from public.foto f where f.articulo_id = a.id and f.es_principal),
                  'cantidad', l.cantidad, 'aprobada', l.cantidad_aprobada, 'disponible', e.disponible, 'prestable', e.prestable,
                  'pendiente', (select coalesce(sum(pa.pendiente), 0)::integer from app.v_prestamos_abiertos pa
                                 where pa.solicitud_id = s.id and pa.articulo_id = a.id)) order by a.nombre), '[]'::jsonb)
               from public.solicitud_linea l join public.articulo a on a.id = l.articulo_id
               join public.v_existencias e on e.articulo_id = a.id where l.solicitud_id = s.id),
    'codigo', (select jsonb_build_object('estado', c.estado, 'expira_en', c.expira_en, 'usado_en', c.usado_en,
                                         'intentos_fallidos', c.intentos_fallidos, 'entrega_anulada_en', c.entrega_anulada_en,
                                         'codigo', case when c.estado = 'VIGENTE' and c.expira_en > now() then c.codigo end)
               from public.codigo_entrega c where c.solicitud_id = s.id order by c.generado_en desc limit 1),
    'codigos', (select coalesce(jsonb_agg(jsonb_build_object('estado', c.estado, 'generado_en', c.generado_en, 'expira_en', c.expira_en,
                                                             'usado_en', c.usado_en, 'genero', app.nombre_usuario(c.generado_por))
                                          order by c.generado_en), '[]'::jsonb)
                from public.codigo_entrega c where c.solicitud_id = s.id),
    'fotos_entrega', (select coalesce(jsonb_agg(f.url order by f.tomada_en), '[]'::jsonb) from public.foto f
                      where f.solicitud_id = s.id and f.url like 'entregas/%'),
    'hay_identificacion', exists (select 1 from public.foto f where f.solicitud_id = s.id and f.url like 'identificaciones/%'),
    'identificacion_borrada', exists (select 1 from public.foto f where f.solicitud_id = s.id and f.url like 'identificaciones/%'
                                      and f.borrada_en is not null),
    'prestamos', (select coalesce(jsonb_agg(jsonb_build_object('prestamo_id', p.prestamo_id, 'articulo', a.nombre,
                                                               'cantidad', p.cantidad, 'pendiente', p.pendiente, 'vence_en', p.vence_en)
                                            order by a.nombre), '[]'::jsonb)
                  from app.v_prestamos p join public.articulo a on a.id = p.articulo_id where p.solicitud_id = s.id));
end $$;

-- p_lineas: [{articulo_id, cantidad}] con la cantidad aprobada de cada línea (0 o ausente = se quita).
-- p_vigencia del código: RATO (1 h 30 min) | HOY (fin de la jornada) | MANANA (24 h)
create function public.solicitud_aprobar(p_id uuid, p_lineas jsonb, p_fecha timestamptz default null,
                                         p_nota text default null, p_vigencia text default 'RATO')
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  s         public.solicitud;
  per       public.solicitante;
  l         record;
  pedida    integer;
  aprobada  integer;
  total     integer := 0;
  cambios   boolean := false;
  vence     timestamptz;
  plazo_max integer;
  impedimento text;
  codigo    jsonb;
begin
  select * into s from public.solicitud where id = p_id for update;
  if not found then
    raise exception 'La solicitud no existe.';
  end if;
  if s.estado <> 'PENDIENTE' then
    raise exception 'Esta solicitud ya fue % (por %).', lower(s.estado::text),
      coalesce(app.nombre_usuario(coalesce(s.autorizada_por, s.rechazada_por, s.cancelada_por)), 'el sistema');
  end if;
  if s.confirmada_en is null then
    raise exception 'La solicitud no está confirmada. Confírmala en persona si el solicitante está presente.';
  end if;
  select * into per from public.solicitante where id = s.solicitante_id;
  impedimento := app.impedimento_solicitante(per.id);
  if impedimento is not null then
    raise exception '% %', per.nombre_completo, lower(left(impedimento, 1)) || substr(impedimento, 2);
  end if;

  vence := coalesce(p_fecha, s.fecha_devolucion_comprometida);
  plazo_max := app.config_int(case when per.tipo = 'MAESTRO' then 'plazo_max_maestro_dias' else 'plazo_max_alumno_dias' end);
  if vence <= now() then
    raise exception 'La fecha de devolución ya pasó: elige otra.';
  end if;
  if (vence at time zone app.zona_horaria())::date > app.hoy() + plazo_max then
    raise exception 'La fecha de devolución puede ser a lo más en % días.', plazo_max;
  end if;
  cambios := vence is distinct from s.fecha_devolucion_comprometida;

  -- Se bloquean los artículos en orden para revisar existencias sin choques.
  perform 1 from public.articulo a
   where a.id in (select sl.articulo_id from public.solicitud_linea sl where sl.solicitud_id = p_id)
   order by a.id for update;

  for l in select sl.id, sl.articulo_id, sl.cantidad, a.nombre, e.disponible, e.prestable, a.activo
             from public.solicitud_linea sl
             join public.articulo a on a.id = sl.articulo_id
             join public.v_existencias e on e.articulo_id = sl.articulo_id
            where sl.solicitud_id = p_id loop
    pedida := l.cantidad;
    aprobada := coalesce((select (x ->> 'cantidad')::integer from jsonb_array_elements(coalesce(p_lineas, '[]'::jsonb)) x
                          where (x ->> 'articulo_id')::uuid = l.articulo_id), 0);
    if aprobada < 0 or aprobada > pedida then
      raise exception 'De "%" se pueden aprobar de 0 a %.', l.nombre, pedida;
    end if;
    if aprobada > 0 and (not l.activo or not l.prestable) then
      raise exception '"%" ya no se puede prestar.', l.nombre;
    end if;
    if aprobada > l.disponible then
      raise exception 'Solo hay % disponibles de "%".', greatest(l.disponible, 0), l.nombre;
    end if;
    cambios := cambios or aprobada <> pedida;
    total := total + aprobada;
    update public.solicitud_linea set cantidad_aprobada = aprobada where id = l.id;
  end loop;

  if total = 0 then
    raise exception 'No aprobaste ningún artículo. Si no hay material, rechaza la solicitud.';
  end if;
  if cambios and btrim(coalesce(p_nota, '')) = '' then
    raise exception 'Cambiaste cantidades o la fecha: escribe una nota para el solicitante.';
  end if;

  update public.solicitud
     set estado = 'APROBADA', autorizada_por = yo.id, autorizada_en = now(), nota_aprobacion = nullif(btrim(p_nota), ''),
         fecha_devolucion_comprometida = vence,
         recoger_hasta = app.al_fin_de_jornada(app.dias_habiles_despues(now(), app.config_int('aprobada_sin_recoger_dias_habiles')))
   where id = p_id
   returning * into s;
  codigo := app.codigo_generar(p_id, yo.id, p_vigencia);
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITUD_APROBADA', 'solicitud', p_id::text, jsonb_build_object('folio', s.folio, 'cambios', cambios));

  perform app.correo_solicitante(p_id, 'Solicitud aprobada',
    format(E'Tu solicitud fue aprobada. Pasa al laboratorio por tu material antes del %s:\n\n%s\n\nDevolución: %s.%s\n\n'
           'Lleva una identificación con foto (credencial de transporte, documento escolar con foto u otra). '
           'En el laboratorio te darán un código para escribirlo en esta página.',
           app.hora_local(s.recoger_hasta), app.lista_articulos(p_id, true), app.hora_local(vence),
           coalesce(E'\n\nNota: ' || s.nota_aprobacion, '')));
  return jsonb_build_object('folio', s.folio, 'recoger_hasta', s.recoger_hasta) || codigo;
end $$;

create function public.solicitud_rechazar(p_id uuid, p_motivo text, p_detalle text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  s  public.solicitud;
  texto text := btrim(coalesce(p_motivo, '')) || coalesce(': ' || nullif(btrim(p_detalle), ''), '');
begin
  select * into s from public.solicitud where id = p_id for update;
  if not found then
    raise exception 'La solicitud no existe.';
  end if;
  if s.estado <> 'PENDIENTE' then
    raise exception 'Esta solicitud ya fue % (por %).', lower(s.estado::text),
      coalesce(app.nombre_usuario(coalesce(s.autorizada_por, s.rechazada_por, s.cancelada_por)), 'el sistema');
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Elige el motivo del rechazo.';
  end if;
  if p_motivo = 'Otro' and btrim(coalesce(p_detalle, '')) = '' then
    raise exception 'Explica el motivo del rechazo.';
  end if;
  update public.solicitud set estado = 'RECHAZADA', motivo_rechazo = texto, rechazada_por = yo.id, rechazada_en = now() where id = p_id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITUD_RECHAZADA', 'solicitud', p_id::text, jsonb_build_object('folio', s.folio, 'motivo', texto));
  if s.confirmada_en is not null then
    perform app.correo_solicitante(p_id, 'Solicitud rechazada', 'Tu solicitud no fue aprobada. Motivo: ' || texto, false);
  end if;
end $$;

create function public.solicitud_cancelar(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué se cancela.';
  end if;
  perform app.cancelar_solicitud(p_id, 'Cancelada por el laboratorio: ' || btrim(p_motivo), yo.id,
                                 'El laboratorio canceló tu solicitud. Motivo: ' || btrim(p_motivo));
end $$;

-- Sin correo (o con el correo equivocado): el responsable la confirma con la persona enfrente.
create function public.solicitud_confirmar_en_persona(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  s  public.solicitud;
begin
  select * into s from public.solicitud where id = p_id for update;
  if not found or s.estado <> 'PENDIENTE' then
    raise exception 'Solo se confirma una solicitud pendiente.';
  end if;
  if s.confirmada_en is null then
    update public.solicitud set confirmada_en = now(), confirmada_como = 'EN_PERSONA', confirmada_por = yo.id where id = p_id;
    insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
    values (yo.id, 'SOLICITUD_CONFIRMADA', 'solicitud', p_id::text, jsonb_build_object('folio', s.folio, 'como', 'EN_PERSONA'));
  end if;
end $$;

create function public.solicitud_codigo_nuevo(p_id uuid, p_vigencia text default 'RATO') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  s  public.solicitud;
begin
  select * into s from public.solicitud where id = p_id for update;
  if not found or s.estado <> 'APROBADA' then
    raise exception 'Solo se genera código para una solicitud aprobada.';
  end if;
  return app.codigo_generar(p_id, yo.id, p_vigencia);
end $$;

-- El alumno sin celular teclea el código en el dispositivo del laboratorio, con su matrícula.
create function public.solicitud_canjear_en_laboratorio(p_id uuid, p_matricula text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  if not exists (select 1 from public.solicitud s join public.solicitante per on per.id = s.solicitante_id
                 where s.id = p_id and lower(btrim(per.matricula_o_clave)) = lower(btrim(coalesce(p_matricula, '')))) then
    return jsonb_build_object('ok', false, 'motivo', 'MATRICULA', 'mensaje', 'La matrícula no corresponde a esta solicitud.');
  end if;
  return app.canjear_codigo(p_id, p_codigo);
end $$;

-- Cierra la entrega: aquí, y solo aquí, se crean los préstamos (F-06 paso 6).
-- Fotos ya subidas al almacén privado: identificaciones/<solicitud>/… y entregas/<solicitud>/…
create function public.solicitud_entregar(p_id uuid, p_tipo_identificacion text, p_foto_identificacion text,
                                          p_fotos_material jsonb, p_fecha_devolucion timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  s         public.solicitud;
  per       public.solicitante;
  c         public.codigo_entrega;
  vence     timestamptz;
  plazo_max integer;
  impedimento text;
  f         jsonb;
  ruta      text;
  l         record;
  n         integer := 0;
begin
  select * into s from public.solicitud where id = p_id for update;
  if not found then
    raise exception 'La solicitud no existe.';
  end if;
  if s.estado <> 'APROBADA' then
    raise exception 'Esta solicitud no está por entregar (está %).', lower(s.estado::text);
  end if;
  select * into c from public.codigo_entrega where solicitud_id = p_id order by generado_en desc limit 1;
  if c.estado is distinct from 'USADO' or c.entrega_anulada_en is not null then
    raise exception 'Falta que el solicitante escriba el código de entrega.';
  end if;
  if p_tipo_identificacion is null or p_tipo_identificacion not in ('TRANSPORTE', 'DOCUMENTO_ESCOLAR', 'INE', 'OTRA') then
    raise exception 'Elige qué identificación mostró.';
  end if;
  if p_foto_identificacion is null or p_foto_identificacion not like 'identificaciones/' || p_id::text || '/%'
     or not app.archivo_existe('privado', p_foto_identificacion) then
    raise exception 'Falta la foto de la identificación.';
  end if;
  if jsonb_typeof(p_fotos_material) <> 'array' or jsonb_array_length(p_fotos_material) = 0 then
    raise exception 'Falta la foto del material que se entrega.';
  end if;

  select * into per from public.solicitante where id = s.solicitante_id;
  impedimento := app.impedimento_solicitante(per.id);
  if impedimento is not null then
    raise exception '% %', per.nombre_completo, lower(left(impedimento, 1)) || substr(impedimento, 2);
  end if;
  vence := coalesce(p_fecha_devolucion, s.fecha_devolucion_comprometida);
  if vence <= now() then
    raise exception 'La fecha de devolución ya pasó: elige una nueva.';
  end if;
  plazo_max := app.config_int(case when per.tipo = 'MAESTRO' then 'plazo_max_maestro_dias' else 'plazo_max_alumno_dias' end);
  if (vence at time zone app.zona_horaria())::date > app.hoy() + plazo_max then
    raise exception 'La fecha de devolución puede ser a lo más en % días.', plazo_max;
  end if;

  for l in select sl.articulo_id, coalesce(sl.cantidad_aprobada, sl.cantidad) as cantidad
             from public.solicitud_linea sl where sl.solicitud_id = p_id and coalesce(sl.cantidad_aprobada, sl.cantidad) > 0
            order by sl.articulo_id loop
    insert into public.movimiento (articulo_id, tipo, cantidad, fecha_compromiso, nota, autorizado_por, registrado_por,
                                   responsable_solicitante_id, solicitud_id, grupo, origen)
    values (l.articulo_id, 'PRESTAMO', l.cantidad, vence, 'Folio ' || s.folio, s.autorizada_por, yo.id,
            per.id, s.id, s.id, 'SOLICITUD');
    n := n + 1;
  end loop;

  insert into public.foto (solicitud_id, url, tipo, tomada_por) values (p_id, p_foto_identificacion, 'IDENTIFICACION', yo.id);
  for f in select * from jsonb_array_elements(p_fotos_material) loop
    ruta := coalesce(f ->> 'ruta', f #>> '{}');
    if ruta is null or ruta not like 'entregas/' || p_id::text || '/%' or not app.archivo_existe('privado', ruta) then
      raise exception 'Una de las fotos del material no terminó de subirse. Intenta de nuevo.';
    end if;
    insert into public.foto (solicitud_id, url, tipo, tomada_por) values (p_id, ruta, 'ENTREGA', yo.id);
  end loop;

  update public.solicitud
     set estado = 'ENTREGADO', entregada_en = now(), entregada_por = yo.id, tipo_identificacion = p_tipo_identificacion,
         fecha_devolucion_comprometida = vence,
         foto_entrega_url = (select coalesce(x ->> 'ruta', x #>> '{}') from jsonb_array_elements(p_fotos_material) x limit 1)
   where id = p_id;
  if per.verificada_en is null then
    update public.solicitante set verificada_por = yo.id, verificada_en = now() where id = per.id;
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'ENTREGA', 'solicitud', p_id::text,
          jsonb_build_object('folio', s.folio, 'prestamos', n, 'identificacion', p_tipo_identificacion, 'ficha_verificada', per.verificada_en is null));

  perform app.correo_solicitante(p_id, 'Material entregado',
    format(E'Se entregó este material a tu nombre:\n\n%s\n\nDevuélvelo a más tardar el %s. Si se pierde o se daña, queda registrado a tu nombre.\n\n'
           'Si no fuiste tú quien lo recibió, abre el enlace y toca "No fui yo".',
           app.lista_articulos(p_id, true), app.hora_local(vence)));
  return jsonb_build_object('folio', s.folio, 'prestamos', n, 'vence_en', vence, 'a_cargo', per.nombre_completo);
end $$;

-- No trajo identificación: la entrega no se cierra y el material sigue apartado. Se necesitará un código nuevo.
create function public.solicitud_entrega_anular(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  c  public.codigo_entrega;
begin
  select * into c from public.codigo_entrega where solicitud_id = p_id order by generado_en desc limit 1 for update;
  if c.estado is distinct from 'USADO' or c.entrega_anulada_en is not null
     or not exists (select 1 from public.solicitud s where s.id = p_id and s.estado = 'APROBADA') then
    raise exception 'No hay una entrega en curso que anular.';
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué no se entregó.';
  end if;
  update public.codigo_entrega set entrega_anulada_en = now(), entrega_anulada_motivo = btrim(p_motivo) where id = c.id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'ENTREGA_ANULADA', 'solicitud', p_id::text, jsonb_build_object('motivo', btrim(p_motivo)));
end $$;

-- Ver la identificación deja registro con nombre y hora; el almacén solo la muestra después de esto.
create function public.identificacion_ver(p_solicitud uuid) returns text[]
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  rutas text[];
begin
  select array_agg(f.url order by f.tomada_en) into rutas
    from public.foto f where f.solicitud_id = p_solicitud and f.url like 'identificaciones/%' and f.borrada_en is null;
  if rutas is null then
    return '{}';
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id) values (yo.id, 'IDENTIFICACION_VISTA', 'solicitud', p_solicitud::text);
  return rutas;
end $$;

-- ---------------------------------------------------------------------
-- Fichas: bloqueo, desbloqueo y corrección de datos
-- ---------------------------------------------------------------------
create function public.solicitante_bloquear(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Explica el bloqueo (al menos 10 letras).';
  end if;
  perform app.exigir_confirmacion();
  update public.solicitante set bloqueo_manual = true, bloqueo_motivo = btrim(p_motivo), bloqueado = true, permitir_con_adeudo_hasta = null
   where id = p_id;
  if not found then
    raise exception 'La ficha no existe.';
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITANTE_BLOQUEADO', 'solicitante', p_id::text, jsonb_build_object('motivo', btrim(p_motivo)));
end $$;

-- Quita el bloqueo manual y, si tiene algo vencido, le permite pedir hasta el fin de la jornada.
create function public.solicitante_desbloquear(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Explica por qué se desbloquea (al menos 10 letras).';
  end if;
  perform app.exigir_confirmacion();
  update public.solicitante set bloqueo_manual = false, bloqueo_motivo = null, permitir_con_adeudo_hasta = app.fin_jornada()
   where id = p_id;
  if not found then
    raise exception 'La ficha no existe.';
  end if;
  update public.solicitante set bloqueado = app.impedimento_solicitante(p_id) is not null where id = p_id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITANTE_DESBLOQUEADO', 'solicitante', p_id::text, jsonb_build_object('motivo', btrim(p_motivo)));
end $$;

-- F-04b medida 3: los datos de contacto solo los cambia el responsable o sub administración, en persona.
create function public.solicitante_editar(p_id uuid, p_nombre text, p_grupo text, p_correo text, p_telefono text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo      public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  s       public.solicitante;
  v_correo text := lower(btrim(coalesce(p_correo, '')));
  dominio text := app.config_texto('dominio_correo_alumnos');
begin
  select * into s from public.solicitante where id = p_id for update;
  if not found then
    raise exception 'La ficha no existe.';
  end if;
  if length(btrim(coalesce(p_nombre, ''))) < 5 then
    raise exception 'Escribe el nombre completo.';
  end if;
  if s.tipo = 'ALUMNO' and v_correo !~ ('^[^@\s]+@' || replace(dominio, '.', '\.') || '$') then
    raise exception 'El correo del alumno debe ser institucional (@%).', dominio;
  end if;
  if v_correo <> '' and v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo no parece válido.';
  end if;
  update public.solicitante
     set nombre_completo = btrim(p_nombre), grupo_area = nullif(btrim(p_grupo), ''), telefono = nullif(btrim(p_telefono), ''),
         correo = nullif(v_correo, ''),
         correo_confirmado_en = case when nullif(v_correo, '') is distinct from s.correo then null else correo_confirmado_en end
   where id = p_id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITANTE_EDITADO', 'solicitante', p_id::text, jsonb_build_object(
    'antes', jsonb_build_object('nombre', s.nombre_completo, 'grupo', s.grupo_area, 'correo', s.correo, 'telefono', s.telefono)));
end $$;

-- ---------------------------------------------------------------------
-- F-18 Adeudos y expediente
-- ---------------------------------------------------------------------
create function public.adeudos_listar()
returns table (persona_tipo text, persona_id uuid, nombre text, detalle text, piezas integer, prestamos integer,
               desde timestamptz, vencidos integer, bloqueado boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select x.persona_tipo, x.persona_id, x.nombre, x.detalle, x.piezas, x.prestamos, x.desde, x.vencidos, x.bloqueado
    from (
      select 'SOLICITANTE' as persona_tipo, per.id as persona_id, per.nombre_completo as nombre,
             initcap(lower(per.tipo::text)) || coalesce(' · ' || per.grupo_area, '') || ' · ' || per.matricula_o_clave as detalle,
             sum(pa.pendiente)::integer as piezas, count(distinct coalesce(pa.grupo, pa.prestamo_id))::integer as prestamos,
             min(pa.fecha) as desde, count(*) filter (where pa.vencido)::integer as vencidos,
             app.impedimento_solicitante(per.id) is not null as bloqueado
      from app.v_prestamos_abiertos pa join public.solicitante per on per.id = pa.responsable_solicitante_id
      group by per.id
      union all
      select 'USUARIO', u.id, u.nombre, initcap(lower(u.rol::text)),
             sum(pa.pendiente)::integer, count(distinct coalesce(pa.grupo, pa.prestamo_id))::integer,
             min(pa.fecha), count(*) filter (where pa.vencido)::integer, false
      from app.v_prestamos_abiertos pa join public.usuario u on u.id = pa.responsable_usuario_id
      group by u.id
    ) x
    order by x.vencidos > 0 desc, x.desde;
end $$;

create function public.persona_expediente(p_tipo text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  per public.solicitante;
  u   public.usuario;
  es_solicitante boolean := p_tipo = 'SOLICITANTE';
  datos jsonb;
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  if es_solicitante then
    select * into per from public.solicitante where id = p_id;
    if not found then
      raise exception 'La ficha no existe.';
    end if;
    datos := jsonb_build_object('tipo', per.tipo, 'nombre', per.nombre_completo, 'matricula', per.matricula_o_clave,
      'grupo', per.grupo_area, 'telefono', per.telefono, 'correo', per.correo, 'nota', per.nota,
      'verificada_por', app.nombre_usuario(per.verificada_por), 'verificada_en', per.verificada_en,
      'correo_confirmado', per.correo_confirmado_en is not null, 'posible_duplicado', per.posible_duplicado,
      'bloqueo_manual', per.bloqueo_manual, 'bloqueo_motivo', per.bloqueo_motivo,
      'impedimento', app.impedimento_solicitante(per.id), 'permitir_con_adeudo_hasta', per.permitir_con_adeudo_hasta);
  elsif p_tipo = 'USUARIO' then
    select * into u from public.usuario where id = p_id;
    if not found then
      raise exception 'La cuenta no existe.';
    end if;
    datos := jsonb_build_object('tipo', u.rol, 'nombre', u.nombre, 'correo', u.correo);
  else
    raise exception 'Tipo de persona desconocido.';
  end if;

  return datos || jsonb_build_object(
    'persona_tipo', p_tipo, 'persona_id', p_id,
    'prestamos', (select coalesce(jsonb_agg(jsonb_build_object(
                    'prestamo_id', p.prestamo_id, 'articulo_id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'unidad', a.unidad,
                    'cantidad', p.cantidad, 'pendiente', p.pendiente, 'fecha', p.fecha, 'vence_en', p.vence_en,
                    'cerrado_en', p.cerrado_en, 'vencido', p.pendiente > 0 and p.vence_en < now(),
                    'con_retraso', (case when p.pendiente > 0 then now() else p.cerrado_en end) > p.vence_en,
                    'folio', (select s.folio from public.solicitud s where s.id = p.solicitud_id))
                    order by p.pendiente > 0 desc, p.fecha desc), '[]'::jsonb)
                  from app.v_prestamos p join public.articulo a on a.id = p.articulo_id
                  where (es_solicitante and p.responsable_solicitante_id = p_id) or (not es_solicitante and p.responsable_usuario_id = p_id)),
    'incidencias', (select coalesce(jsonb_agg(jsonb_build_object(
                      'tipo', i.tipo, 'estado', i.estado, 'cantidad', i.cantidad, 'articulo', a.nombre, 'reportada_en', i.reportada_en,
                      'nota', i.nota) order by i.reportada_en desc), '[]'::jsonb)
                    from public.incidencia i join public.articulo a on a.id = i.articulo_id
                    where i.tipo <> 'CONSUMO' and ((es_solicitante and i.responsable_solicitante_id = p_id)
                                                   or (not es_solicitante and i.responsable_usuario_id = p_id))),
    'solicitudes', case when es_solicitante then
                     (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'folio', s.folio, 'estado', s.estado,
                                                                   'creada_en', s.creada_en, 'entregada_en', s.entregada_en)
                                                order by s.creada_en desc), '[]'::jsonb)
                      from public.solicitud s where s.solicitante_id = p_id)
                   else '[]'::jsonb end);
end $$;

-- Todo lo de un préstamo en una sola pantalla: "¿a nombre de quién estaba?"
create function public.expediente_prestamo(p_prestamo uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  p   record;
  s   public.solicitud;
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  select * into p from app.v_prestamos where prestamo_id = p_prestamo;
  if not found then
    raise exception 'El préstamo no existe.';
  end if;
  select * into s from public.solicitud where id = p.solicitud_id;

  return jsonb_build_object(
    'prestamo_id', p.prestamo_id, 'cantidad', p.cantidad, 'pendiente', p.pendiente, 'fecha', p.fecha, 'vence_en', p.vence_en,
    'vencido', p.pendiente > 0 and p.vence_en < now(), 'nota', p.nota,
    'articulo', (select jsonb_build_object('id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'unidad', a.unidad)
                 from public.articulo a where a.id = p.articulo_id),
    'a_cargo', coalesce(app.nombre_usuario(p.responsable_usuario_id), app.nombre_solicitante(p.responsable_solicitante_id)),
    'a_cargo_matricula', (select per.matricula_o_clave from public.solicitante per where per.id = p.responsable_solicitante_id),
    'persona_tipo', case when p.responsable_usuario_id is not null then 'USUARIO' else 'SOLICITANTE' end,
    'persona_id', coalesce(p.responsable_usuario_id, p.responsable_solicitante_id),
    'autorizo', app.nombre_usuario(p.autorizado_por), 'registro', app.nombre_usuario(p.registrado_por),
    'extensiones', (select coalesce(jsonb_agg(jsonb_build_object('fecha_nueva', e.fecha_nueva, 'motivo', e.motivo,
                                                                 'por', app.nombre_usuario(e.extendida_por), 'en', e.extendida_en)
                                              order by e.extendida_en), '[]'::jsonb)
                    from public.prestamo_extension e where e.prestamo_id = p.prestamo_id),
    'cierres', (select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'cantidad', m.cantidad, 'fecha', m.fecha, 'nota', m.nota,
                                                             'recibio', app.nombre_usuario(m.registrado_por))
                                          order by m.fecha), '[]'::jsonb)
                from public.movimiento m where m.movimiento_origen_id = p.prestamo_id and m.tipo in ('DEVOLUCION', 'PERDIDA')),
    'incidencias', (select coalesce(jsonb_agg(jsonb_build_object('tipo', i.tipo, 'estado', i.estado, 'cantidad', i.cantidad,
                                                                 'nota', i.nota, 'reportada_en', i.reportada_en,
                                                                 'reporto', app.nombre_usuario(i.reportada_por))
                                              order by i.reportada_en), '[]'::jsonb)
                    from public.incidencia i
                    -- Los daños se reportan al recibir la devolución, en la misma operación.
                    where i.prestamo_id = p.prestamo_id
                       or (i.tipo = 'DANO' and i.articulo_id = p.articulo_id
                           and exists (select 1 from public.movimiento d where d.movimiento_origen_id = p.prestamo_id
                                       and d.tipo = 'DEVOLUCION' and abs(extract(epoch from d.fecha - i.reportada_en)) < 5))),
    'solicitud', case when s.id is null then null else jsonb_build_object(
      'id', s.id, 'folio', s.folio, 'creada_en', s.creada_en, 'motivo', s.motivo,
      'confirmada_en', s.confirmada_en, 'confirmada_como', s.confirmada_como,
      'autorizo', app.nombre_usuario(s.autorizada_por), 'autorizada_en', s.autorizada_en,
      'entregada_en', s.entregada_en, 'entrego', app.nombre_usuario(s.entregada_por), 'tipo_identificacion', s.tipo_identificacion,
      'no_fui_yo_en', s.no_fui_yo_en,
      'codigos', (select coalesce(jsonb_agg(jsonb_build_object('estado', c.estado, 'generado_en', c.generado_en,
                                                               'expira_en', c.expira_en, 'usado_en', c.usado_en)
                                            order by c.generado_en), '[]'::jsonb)
                  from public.codigo_entrega c where c.solicitud_id = s.id),
      'fotos_entrega', (select coalesce(jsonb_agg(f.url order by f.tomada_en), '[]'::jsonb) from public.foto f
                        where f.solicitud_id = s.id and f.url like 'entregas/%'),
      'hay_identificacion', exists (select 1 from public.foto f where f.solicitud_id = s.id and f.url like 'identificaciones/%'
                                    and f.borrada_en is null),
      'identificacion_borrada', exists (select 1 from public.foto f where f.solicitud_id = s.id and f.url like 'identificaciones/%'
                                        and f.borrada_en is not null)) end);
end $$;

-- ---------------------------------------------------------------------
-- Avisos en la app y celulares
-- ---------------------------------------------------------------------
create function public.avisos_listar() returns table (id uuid, titulo text, cuerpo text, ruta text, creado_en timestamptz, leido boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  return query
    select a.id, a.titulo, a.cuerpo, a.ruta, a.creado_en, a.leido_en is not null
    from public.aviso a where a.usuario_id = yo.id
    order by a.creado_en desc limit 50;
end $$;

create function public.avisos_sin_leer() returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  return (select count(*)::integer from public.aviso a where a.usuario_id = yo.id and a.leido_en is null);
end $$;

create function public.avisos_marcar_leidos() returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  update public.aviso set leido_en = now() where usuario_id = yo.id and leido_en is null;
end $$;

create function public.dispositivo_registrar(p_token text, p_plataforma text default 'android') returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  if length(btrim(coalesce(p_token, ''))) < 20 then
    raise exception 'Identificador de dispositivo inválido.';
  end if;
  insert into public.dispositivo (token, usuario_id, plataforma)
  values (btrim(p_token), yo.id, coalesce(p_plataforma, 'android'))
  on conflict (token) do update set usuario_id = excluded.usuario_id, visto_en = now(), activo = true;
end $$;

-- ---------------------------------------------------------------------
-- Para la función del servidor "avisos" (llave secreta)
-- ---------------------------------------------------------------------
create function public.envios_tomar(p_canales text[], p_limite integer default 20)
returns table (id bigint, canal text, destino text, asunto text, cuerpo text, datos jsonb)
language plpgsql security definer set search_path = '' as $$
begin
  return query
    update public.envio e set estado = 'ENVIANDO', tomado_en = now(), intentos = e.intentos + 1
     where e.id in (select x.id from public.envio x
                     where x.estado = 'PENDIENTE' and x.canal = any (p_canales)
                       -- reintentos cada vez más espaciados
                       and (x.tomado_en is null or x.tomado_en < now() - make_interval(mins => 5 * x.intentos * x.intentos))
                     order by x.id limit least(greatest(coalesce(p_limite, 20), 1), 100)
                     for update skip locked)
    returning e.id, e.canal, e.destino, e.asunto, e.cuerpo, e.datos;
end $$;

create function public.envio_resultado(p_id bigint, p_ok boolean, p_error text default null, p_token_invalido boolean default false)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  e public.envio;
begin
  update public.envio
     set estado = case when p_ok then 'ENVIADO' when intentos >= 5 or p_token_invalido then 'FALLIDO' else 'PENDIENTE' end,
         enviado_en = case when p_ok then now() end, error = left(p_error, 1000)
   where id = p_id
   returning * into e;
  if p_token_invalido and e.canal = 'PUSH' then
    update public.dispositivo set activo = false where token = e.destino;
  end if;
end $$;

-- Fotos de identificación que ya se deben borrar (P-14), y archivos subidos a una entrega que nunca se cerró.
create function public.identificaciones_por_borrar(p_limite integer default 50) returns table (ruta text)
language plpgsql stable security definer set search_path = '' as $$
declare
  fin timestamptz := app.al_fin_de_jornada(app.config_texto('fin_ciclo_escolar')::date);
begin
  return query
    select f.url from public.foto f join public.solicitud s on s.id = f.solicitud_id
     where f.url like 'identificaciones/%' and f.borrada_en is null
       and now() >= fin and f.tomada_en < fin
       and not exists (select 1 from app.v_prestamos_abiertos pa where pa.responsable_solicitante_id = s.solicitante_id)
    union all
    select o.name from storage.objects o
     where o.bucket_id = 'privado' and o.name like 'identificaciones/%' and o.created_at < now() - interval '1 day'
       and not exists (select 1 from public.foto f where f.url = o.name)
    limit least(greatest(coalesce(p_limite, 50), 1), 500);
end $$;

create function public.identificaciones_borradas(p_rutas text[]) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r text;
begin
  foreach r in array coalesce(p_rutas, '{}') loop
    update public.foto set borrada_en = now(), borrada_motivo = 'Fin del ciclo escolar sin adeudos'
     where url = r and borrada_en is null;
    insert into public.bitacora (evento, tabla, registro_id, datos)
    values ('IDENTIFICACION_BORRADA', 'solicitud', split_part(r, '/', 2),
            jsonb_build_object('con_registro', found));
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Tareas periódicas (cada 5 minutos en Supabase con pg_cron)
-- ---------------------------------------------------------------------
create function app.tareas_periodicas() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r        record;
  n_codigos integer;
  n_sin_confirmar integer := 0;
  n_sin_respuesta integer := 0;
  n_sin_recoger integer := 0;
  n_recordatorios integer := 0;
begin
  update public.codigo_entrega set estado = 'EXPIRADO' where estado = 'VIGENTE' and expira_en <= now();
  get diagnostics n_codigos = row_count;

  for r in select s.id from public.solicitud s
            where s.estado = 'PENDIENTE' and s.confirmada_en is null
              and s.creada_en < now() - make_interval(hours => app.config_int('solicitud_confirmar_horas')) loop
    perform app.cancelar_solicitud(r.id, 'No se confirmó desde el correo', null);
    n_sin_confirmar := n_sin_confirmar + 1;
  end loop;

  for r in select s.id from public.solicitud s
            where s.estado = 'PENDIENTE' and s.confirmada_en is not null
              and app.al_fin_de_jornada(app.dias_habiles_despues(s.confirmada_en,
                    app.config_int('solicitud_sin_respuesta_dias_habiles'))) < now() loop
    perform app.cancelar_solicitud(r.id, 'Sin respuesta del laboratorio', null,
      'Tu solicitud se canceló porque el laboratorio no la revisó a tiempo. Puedes volver a pedir.');
    n_sin_respuesta := n_sin_respuesta + 1;
  end loop;

  for r in select s.id from public.solicitud s where s.estado = 'APROBADA' and s.recoger_hasta < now() loop
    perform app.cancelar_solicitud(r.id, 'No se recogió', null,
      'Tu solicitud se canceló porque no pasaste a recoger el material a tiempo. No cuenta como adeudo: puedes volver a pedir.');
    n_sin_recoger := n_sin_recoger + 1;
  end loop;

  for r in select s.id from public.solicitud s where s.estado in ('ENTREGADO', 'VENCIDA') loop
    perform app.actualizar_estado_solicitud(r.id);
  end loop;

  update public.solicitante per set bloqueado = x.bloqueado
    from (select s.id, app.impedimento_solicitante(s.id) is not null as bloqueado from public.solicitante s) x
   where x.id = per.id and per.bloqueado is distinct from x.bloqueado;

  -- Recordatorios: un día antes y el día del vencimiento, uno por persona y día.
  for r in select pa.responsable_solicitante_id as per, (pa.vence_en at time zone app.zona_horaria())::date as dia,
                  string_agg(format('  • %s × %s', pa.pendiente, a.nombre), E'\n' order by a.nombre) as lista
             from app.v_prestamos_abiertos pa join public.articulo a on a.id = pa.articulo_id
            where pa.responsable_solicitante_id is not null and not pa.vencido
              and (pa.vence_en at time zone app.zona_horaria())::date in (app.hoy(), app.hoy() + 1)
            group by 1, 2 loop
    insert into public.envio (canal, destino, asunto, cuerpo, clave)
    select 'CORREO', per.correo,
           case when r.dia = app.hoy() then 'Hoy vence tu préstamo' else 'Mañana vence tu préstamo' end,
           format(E'Hola, %s:\n\nRecuerda devolver al Laboratorio Maker a más tardar el %s:\n\n%s\n\nLaboratorio Maker',
                  split_part(per.nombre_completo, ' ', 1), app.hora_local(app.al_fin_de_jornada(r.dia)), r.lista),
           format('recordatorio:%s:%s:%s', per.id, r.dia, case when r.dia = app.hoy() then 'hoy' else 'manana' end)
      from public.solicitante per where per.id = r.per and per.correo is not null
    on conflict (clave) do nothing;
    if found then
      n_recordatorios := n_recordatorios + 1;
    end if;
  end loop;

  update public.envio set estado = 'PENDIENTE' where estado = 'ENVIANDO' and tomado_en < now() - interval '10 minutes';

  return jsonb_build_object('codigos_expirados', n_codigos, 'sin_confirmar', n_sin_confirmar, 'sin_respuesta', n_sin_respuesta,
                            'sin_recoger', n_sin_recoger, 'recordatorios', n_recordatorios);
end $$;

-- ---------------------------------------------------------------------
-- Configuración que cambia sub administración
-- ---------------------------------------------------------------------
create function public.configuracion_cambiar(p_clave text, p_valor jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA', array['SUBADMIN']::public.rol_usuario[]);
  antes  jsonb;
  numero integer;
begin
  if p_clave not in ('fin_ciclo_escolar', 'hora_fin_jornada', 'plazo_default_dias', 'plazo_max_alumno_dias',
                     'plazo_max_maestro_dias', 'url_app') then
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
  end if;
  perform app.exigir_confirmacion();
  select valor into antes from public.configuracion where clave = p_clave;
  update public.configuracion set valor = p_valor where clave = p_clave;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'CONFIGURACION', 'configuracion', p_clave, jsonb_build_object('antes', antes, 'despues', p_valor));
end $$;

-- ---------------------------------------------------------------------
-- Reemplazos de la Fase 3: el bloqueo se revisa en vivo, no con la copia guardada
-- ---------------------------------------------------------------------
create or replace function public.solicitante_buscar(p_matricula text)
returns table (id uuid, nombre_completo text, tipo public.tipo_solicitante, grupo_area text,
               bloqueado boolean, verificada boolean, vencidos integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select s.id, s.nombre_completo, s.tipo, s.grupo_area, app.impedimento_solicitante(s.id) is not null, s.verificada_en is not null,
           (select count(*) from app.v_prestamos_abiertos pa
             where pa.responsable_solicitante_id = s.id and pa.vencido)::integer
    from public.solicitante s
    where lower(btrim(s.matricula_o_clave)) = lower(btrim(p_matricula)) and not s.posible_duplicado
    order by s.tipo;
end $$;

create or replace function public.prestamo_registrar(
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
  impedimento text;
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
    impedimento := app.impedimento_solicitante(s.id);
    if impedimento is not null then
      raise exception '% no puede llevarse más material. %', s.nombre_completo, impedimento;
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

-- El historial de la ficha: el préstamo que vino de una solicitud muestra su folio.
-- (Sin cambios de columnas; la nota del movimiento ya dice "Folio LM-…".)

-- ---------------------------------------------------------------------
-- Almacén privado: entregas e identificaciones
-- ---------------------------------------------------------------------
create or replace function app.puede_subir_privado(p_ruta text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  u public.usuario;
begin
  u := app.exigir('SESION');
  if split_part(p_ruta, '/', 1) = 'incidencias' then
    return true;
  end if;
  if split_part(p_ruta, '/', 1) in ('entregas', 'identificaciones') then
    return u.rol in ('RESPONSABLE', 'SUBADMIN') and app.nivel_sesion() = 'CONTRASENA';
  end if;
  return false;
exception when others then
  return false;
end $$;

-- Las identificaciones: solo responsable y sub administración con contraseña, y solo después de
-- pedirlas con identificacion_ver (que deja el registro en la bitácora).
create or replace function app.puede_ver_privado(p_ruta text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  u public.usuario;
begin
  begin
    u := app.exigir('SESION');
  exception when others then
    return false;
  end;
  if split_part(p_ruta, '/', 1) = 'identificaciones' then
    return u.rol in ('RESPONSABLE', 'SUBADMIN') and app.nivel_sesion() = 'CONTRASENA'
       and exists (select 1 from public.bitacora b
                   where b.usuario_id = u.id and b.evento = 'IDENTIFICACION_VISTA'
                     and b.registro_id = split_part(p_ruta, '/', 2)
                     and b.en > now() - make_interval(mins => app.config_int('identificacion_ver_minutos')));
  end if;
  if u.rol in ('RESPONSABLE', 'SUBADMIN') and app.nivel_sesion() = 'CONTRASENA' then
    return true;
  end if;
  if split_part(p_ruta, '/', 1) = 'incidencias' then
    return exists (select 1 from public.foto f join public.incidencia i on i.id = f.incidencia_id
                   where f.url = p_ruta and i.reportada_por = u.id);
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------------
-- Tareas automáticas en Supabase (pg_cron y pg_net). En la base local no existen y se omite.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    execute 'create extension if not exists pg_net with schema extensions';
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron';
    execute $cron$select cron.schedule('inventario-tareas', '*/5 * * * *',
                                       'select app.tareas_periodicas(); select app.despertar_envios();')$cron$;
  end if;
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
      and p.proname in ('solicitud_publica_enviar', 'solicitud_publica_estado', 'solicitud_publica_confirmar',
                        'solicitud_publica_cancelar', 'solicitud_publica_no_fui_yo', 'solicitud_publica_canjear',
                        'solicitud_publica_recuperar', 'solicitudes_contar', 'solicitudes_listar', 'solicitud_detalle',
                        'solicitud_aprobar', 'solicitud_rechazar', 'solicitud_cancelar', 'solicitud_confirmar_en_persona',
                        'solicitud_codigo_nuevo', 'solicitud_canjear_en_laboratorio', 'solicitud_entregar',
                        'solicitud_entrega_anular', 'identificacion_ver', 'solicitante_bloquear', 'solicitante_desbloquear',
                        'solicitante_editar', 'adeudos_listar', 'persona_expediente', 'expediente_prestamo', 'avisos_listar',
                        'avisos_sin_leer', 'avisos_marcar_leidos', 'dispositivo_registrar', 'envios_tomar', 'envio_resultado',
                        'identificaciones_por_borrar', 'identificaciones_borradas', 'configuracion_cambiar',
                        'solicitante_buscar', 'prestamo_registrar')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.proname in ('solicitud_publica_estado', 'solicitud_publica_confirmar', 'solicitud_publica_cancelar',
                     'solicitud_publica_no_fui_yo', 'solicitud_publica_canjear') then
      execute format('grant execute on function %s to anon, authenticated', f.firma);
    elsif f.proname in ('solicitud_publica_enviar', 'solicitud_publica_recuperar', 'envios_tomar', 'envio_resultado',
                        'identificaciones_por_borrar', 'identificaciones_borradas') then
      execute format('grant execute on function %s to service_role', f.firma);
    else
      execute format('grant execute on function %s to authenticated', f.firma);
    end if;
  end loop;
end $$;
