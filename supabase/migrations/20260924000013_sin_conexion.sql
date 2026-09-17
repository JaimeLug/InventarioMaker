-- =====================================================================
-- 0013 · Trabajo sin conexión (F-17, Fase 6)
--
-- El celular guarda en una cola lo que se capturó sin señal y lo manda al volver por una sola puerta:
-- public.comando_sin_conexion. Esa puerta marca la transacción como "sin conexión"; entonces:
--   * lo que el material ya hizo en físico (préstamo, consumo) se acepta aunque rompa una regla,
--     con marca de conflicto, un pendiente "Contar físicamente" y aviso al responsable;
--   * lo imposible en físico (devolver algo ya devuelto) se rechaza y el celular lo pone en "Por resolver";
--   * cada comando se aplica una sola vez aunque llegue repetido.
-- Con señal nada cambia: las reglas siguen siendo estrictas.
-- =====================================================================

alter table public.movimiento add column registrado_tarde boolean not null default false;
comment on column public.movimiento.registrado_tarde is 'Capturado sin conexión y recibido más de 72 horas después (F-17).';

alter table public.comando_aplicado
  add column conflicto boolean not null default false,
  add column tarde     boolean not null default false;

create function app.sin_conexion() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(current_setting('app.sin_conexion', true), '') = 'on'
$$;

create function app.fecha_dispositivo() returns timestamptz
language sql stable set search_path = '' as $$
  select nullif(current_setting('app.fecha_dispositivo', true), '')::timestamptz
$$;

-- Corre antes que las demás validaciones (los disparadores "before" van en orden alfabético).
create function app.marcar_sin_conexion() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  a        public.articulo;
  e        public.v_existencias;
  motivos  text[] := '{}';
begin
  if not app.sin_conexion() then
    return new;
  end if;
  if new.origen = 'APP' then
    new.origen := 'SIN_CONEXION';
  end if;
  new.fecha_dispositivo := coalesce(new.fecha_dispositivo, app.fecha_dispositivo());
  new.registrado_tarde := coalesce(new.fecha_dispositivo < now() - interval '72 hours', false);

  if new.tipo in ('PRESTAMO', 'CONSUMO') then
    select * into a from public.articulo where id = new.articulo_id;
    select * into e from public.v_existencias where articulo_id = new.articulo_id;
    if not a.activo then
      motivos := motivos || 'estaba dado de baja o desglosado'::text;
    end if;
    if a.no_se_presta and new.tipo = 'PRESTAMO' then
      motivos := motivos || format('estaba marcado como que no se presta (%s)', a.no_se_presta_motivo);
    end if;
    if a.estado_inventario = 'SIN_CLASIFICAR' then
      motivos := motivos || 'estaba sin clasificar'::text;
    end if;
    if a.conteo_desconocido then
      motivos := motivos || 'no se había contado'::text;
    end if;
    if new.cantidad > coalesce(e.disponible, 0) then
      motivos := motivos || format('solo había %s disponibles', greatest(coalesce(e.disponible, 0), 0));
    end if;
    if new.responsable_solicitante_id is not null
       and app.impedimento_solicitante(new.responsable_solicitante_id) is not null then
      motivos := motivos || ('la persona no podía llevarse más material: ' || app.impedimento_solicitante(new.responsable_solicitante_id));
    end if;
    if cardinality(motivos) > 0 then
      new.conflicto := true;
      new.conflicto_motivo := 'Sin conexión: ' || array_to_string(motivos, '; ');
      perform set_config('app.conflictos',
        concat_ws(' | ', nullif(current_setting('app.conflictos', true), ''), format('%s: %s', a.nombre, array_to_string(motivos, '; '))), true);
    end if;
  end if;
  return new;
end $$;
create trigger a_sin_conexion before insert on public.movimiento for each row execute function app.marcar_sin_conexion();

-- Un conflicto aceptado deja un pendiente de conteo y avisa al responsable.
create function app.tras_conflicto() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  a public.articulo;
begin
  select * into a from public.articulo where id = new.articulo_id;
  if not exists (select 1 from public.tarea_pendiente t where t.articulo_id = new.articulo_id and t.tipo = 'CONTAR' and not t.resuelta) then
    insert into public.tarea_pendiente (articulo_id, tipo, descripcion, origen, prioridad, creada_por)
    values (new.articulo_id, 'CONTAR', 'Conflicto al sincronizar lo capturado sin conexión: ' || new.conflicto_motivo, 'SISTEMA', 1, new.registrado_por);
  end if;
  perform app.avisar_responsables('Conflicto sin conexión: ' || a.nombre, new.conflicto_motivo || '. Hay que contarlo.', '/conflictos');
  return null;
end $$;
create trigger conflicto after insert on public.movimiento for each row when (new.conflicto) execute function app.tras_conflicto();

-- Préstamo directo (versión de la 0007): sin conexión no se rechaza a quien tenía adeudo ni la fecha que ya pasó (el material ya salió).
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
    if impedimento is not null and not app.sin_conexion() then
      raise exception '% no puede llevarse más material. %', s.nombre_completo, impedimento;
    end if;
  end if;
  if vence <= now() and not app.sin_conexion() then
    raise exception 'La fecha de devolución ya pasó.';
  end if;
  if vence > coalesce(app.fecha_dispositivo(), now()) + make_interval(days => app.config_int('prestamo_directo_max_dias')) then
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

-- Un conteo capturado sin conexión se marca "Revisar" si el artículo tuvo movimientos después de contarlo.
create function app.nota_conteo_sin_conexion(p_articulo uuid, p_nota text) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.movimiento m where m.articulo_id = p_articulo and m.fecha > app.fecha_dispositivo())
      then concat_ws(' ', 'Revisar: hubo movimientos después de contarlo sin conexión.', nullif(btrim(p_nota), ''))
    else p_nota end
$$;

-- Sin conexión, el registro del comando guarda también la hora del celular y si hubo conflicto o llegó tarde
-- (comando_aplicado no se edita: todo va al insertarlo).
create or replace function app.registrar_comando(p_comando uuid, p_usuario uuid, p_tipo text, p_resultado jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_conflicto text := nullif(current_setting('app.conflictos', true), '');
  v_fecha     timestamptz := app.fecha_dispositivo();
  v_tarde     boolean := coalesce(v_fecha < now() - interval '72 hours', false);
  r           jsonb := p_resultado;
begin
  if app.sin_conexion() then
    r := coalesce(r, '{}'::jsonb) || jsonb_build_object('conflicto', v_conflicto, 'tarde', v_tarde);
  end if;
  if p_comando is not null then
    insert into public.comando_aplicado (id, usuario_id, tipo, resultado, fecha_dispositivo, conflicto, tarde)
    values (p_comando, p_usuario, p_tipo, r, v_fecha, app.sin_conexion() and v_conflicto is not null, app.sin_conexion() and v_tarde);
  end if;
  return r;
end $$;

-- La puerta única de lo capturado sin conexión.
-- p_tipo: PRESTAMO | DEVOLUCION | CONSUMO | INCIDENCIA | CONTEO | CONTEO_INVENTARIO | APORTE
create function public.comando_sin_conexion(p_id uuid, p_tipo text, p_datos jsonb, p_fecha_dispositivo timestamptz)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('SESION');
  previo    jsonb := app.comando_previo(p_id);
  r         jsonb;
  d         jsonb := coalesce(p_datos, '{}');
begin
  if previo is not null then
    return previo || jsonb_build_object('repetido', true);
  end if;
  if p_id is null or p_fecha_dispositivo is null then
    raise exception 'Al comando le falta su identificador o su hora.';
  end if;
  perform set_config('app.sin_conexion', 'on', true);
  perform set_config('app.fecha_dispositivo', p_fecha_dispositivo::text, true);
  perform set_config('app.conflictos', '', true);

  case p_tipo
    when 'PRESTAMO' then
      r := public.prestamo_registrar(d -> 'lineas', (d ->> 'responsable_usuario')::uuid, (d ->> 'responsable_solicitante')::uuid,
                                     (d ->> 'fecha_compromiso')::timestamptz, d ->> 'nota', p_id);
    when 'DEVOLUCION' then
      r := public.devolucion_registrar(d -> 'lineas', p_id);
    when 'CONSUMO' then
      r := public.consumo_registrar((d ->> 'articulo_id')::uuid, (d ->> 'cantidad')::integer, d ->> 'nota', p_id);
    when 'INCIDENCIA' then
      r := jsonb_build_object('id', public.incidencia_reportar(p_id, (d ->> 'articulo_id')::uuid, (d ->> 'tipo')::public.tipo_incidencia,
                                     (d ->> 'cantidad')::integer, (d ->> 'prestamo_id')::uuid, d ->> 'nota',
                                     coalesce(d -> 'fotos', '[]'::jsonb), d ->> 'sin_foto'));
      r := app.registrar_comando(p_id, yo.id, 'INCIDENCIA', r);
    when 'CONTEO' then
      r := public.conteo_proponer((d ->> 'articulo_id')::uuid, (d ->> 'en_taller')::integer,
                                  app.nota_conteo_sin_conexion((d ->> 'articulo_id')::uuid, d ->> 'nota'));
      r := app.registrar_comando(p_id, yo.id, 'CONTEO', r);
    when 'CONTEO_INVENTARIO' then
      perform public.inventario_contar((d ->> 'inventario_id')::uuid, (d ->> 'articulo_id')::uuid, (d ->> 'cantidad')::integer,
                                       (d ->> 'contenedor_id')::uuid, app.nota_conteo_sin_conexion((d ->> 'articulo_id')::uuid, d ->> 'nota'));
      r := app.registrar_comando(p_id, yo.id, 'CONTEO_INVENTARIO', '{}'::jsonb);
    when 'APORTE' then
      perform public.pendiente_aportar((d ->> 'tarea_id')::uuid, d ->> 'nota', d ->> 'foto');
      r := app.registrar_comando(p_id, yo.id, 'APORTE', '{}'::jsonb);
    else
      raise exception 'La app mandó un tipo de comando que el servidor no conoce: %.', p_tipo;
  end case;

  perform set_config('app.sin_conexion', '', true);
  perform set_config('app.fecha_dispositivo', '', true);
  return r || jsonb_build_object('hora_servidor', now());
end $$;

-- Para avisar si la hora del celular está mal.
create function public.hora_servidor() returns timestamptz
language sql stable set search_path = '' as $$ select now() $$;

-- Lo que el celular guarda para trabajar sin señal ------------------------------------------

-- Préstamos abiertos, para recibir devoluciones sin conexión (lo mismo que ve un docente al recibir una).
create function public.prestamos_para_sin_conexion()
returns table (prestamo_id uuid, articulo_id uuid, cantidad_prestada integer, pendiente integer, fecha timestamptz,
               vence_en timestamptz, vencido boolean, a_cargo text, autorizo text, grupo uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select pa.prestamo_id, pa.articulo_id, pa.cantidad_prestada, pa.pendiente::integer, pa.fecha, pa.vence_en, pa.vencido,
           coalesce(app.nombre_usuario(pa.responsable_usuario_id), app.nombre_solicitante(pa.responsable_solicitante_id)),
           app.nombre_usuario(pa.autorizado_por), pa.grupo
    from app.v_prestamos_abiertos pa
    order by pa.vence_en;
end $$;

-- Alumnos y maestros que ya pidieron algo en el ciclo: solo nombre, matrícula y grupo (nada de contacto
-- ni identificaciones). En el celular se buscan igual que en línea: por matrícula exacta.
create function public.solicitantes_para_sin_conexion()
returns table (id uuid, nombre_completo text, tipo public.tipo_solicitante, matricula text, grupo_area text, bloqueado boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select s.id, s.nombre_completo, s.tipo, s.matricula_o_clave, s.grupo_area, s.bloqueado
    from public.solicitante s
    where not s.posible_duplicado
      and (exists (select 1 from public.movimiento m where m.responsable_solicitante_id = s.id and m.fecha > now() - interval '1 year')
           or exists (select 1 from public.solicitud x where x.solicitante_id = s.id and x.creada_en > now() - interval '1 year'));
end $$;

-- Lo aceptado con conflicto o registrado tarde (responsable y sub administración).
create function public.conflictos_sin_conexion()
returns table (movimiento_id uuid, articulo_id uuid, codigo text, articulo text, tipo text, cantidad integer, unidad text, motivo text,
               conflicto boolean, tarde boolean, capturado_en timestamptz, recibido_en timestamptz, registro text, a_cargo text,
               tarea_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select m.id, a.id, a.codigo, a.nombre, m.tipo::text, m.cantidad, a.unidad, m.conflicto_motivo, m.conflicto, m.registrado_tarde,
           m.fecha_dispositivo, m.fecha, app.nombre_usuario(m.registrado_por),
           coalesce(app.nombre_usuario(m.responsable_usuario_id), app.nombre_solicitante(m.responsable_solicitante_id)),
           (select t.id from public.tarea_pendiente t where t.articulo_id = a.id and t.tipo = 'CONTAR' and not t.resuelta limit 1)
    from public.movimiento m join public.articulo a on a.id = m.articulo_id
    where m.conflicto or m.registrado_tarde
    order by m.fecha desc
    limit 300;
end $$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function app.registrar_comando(uuid, uuid, text, jsonb), app.sin_conexion(), app.fecha_dispositivo(), app.marcar_sin_conexion(), app.tras_conflicto(),
                           app.nota_conteo_sin_conexion(uuid, text) from public;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma, p.proname
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('comando_sin_conexion', 'hora_servidor', 'prestamos_para_sin_conexion', 'solicitantes_para_sin_conexion',
                        'conflictos_sin_conexion', 'prestamo_registrar')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to authenticated', f.firma);
    if f.proname = 'hora_servidor' then
      execute format('grant execute on function %s to anon', f.firma);
    end if;
  end loop;
end $$;
