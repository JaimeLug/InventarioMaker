-- =====================================================================
-- 0019 · Solicitudes para la selección de robótica desde su cuenta (Fase 11)
--
-- Los alumnos de la selección de robótica pueden pedir material prestado
-- desde su cuenta, vinculada a su ficha de alumno (solicitante) creada al
-- dar de alta la cuenta.
--
-- La solicitud nace confirmada (confirmada_como = 'EN_PERSONA') porque la
-- sesión ya identifica a la persona. Pasa por el mismo proceso de revisión,
-- entrega con código e identificación que cualquier alumno.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Vínculo entre cuenta de usuario y solicitante
-- ---------------------------------------------------------------------
alter table public.usuario
  add column if not exists solicitante_id uuid references public.solicitante(id);

comment on column public.usuario.solicitante_id is
  'Solo para cuentas de rol SELECCION: su ficha de alumno como solicitante.';

-- ---------------------------------------------------------------------
-- 2. Modificar cuenta_registrar para vincular el solicitante al crear la cuenta
-- ---------------------------------------------------------------------
drop function if exists public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid);

create or replace function public.cuenta_registrar(
  p_id uuid,
  p_nombre text,
  p_rol public.rol_usuario,
  p_correo text,
  p_creada_por uuid,
  p_matricula text default null,
  p_nombre_alumno text default null,
  p_grupo text default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_solicitante_id uuid;
  v_mat text;
  v_nom text;
begin
  if p_rol::text = 'SELECCION' then
    v_mat := btrim(coalesce(p_matricula, ''));
    if v_mat = '' then
      raise exception 'La selección de robótica necesita la matrícula del alumno.'
        using errcode = 'PT400', detail = 'MATRICULA_REQUERIDA';
    end if;

    -- Buscar si ya existe el solicitante alumno con esa matrícula
    select id into v_solicitante_id
      from public.solicitante
     where tipo = 'ALUMNO' and lower(btrim(matricula_o_clave)) = lower(v_mat)
     limit 1;

    if v_solicitante_id is null then
      v_nom := btrim(coalesce(p_nombre_alumno, p_nombre));
      insert into public.solicitante (nombre_completo, tipo, matricula_o_clave, grupo_area, correo)
      values (v_nom, 'ALUMNO', v_mat, nullif(btrim(p_grupo), ''), nullif(btrim(p_correo), ''))
      returning id into v_solicitante_id;
    else
      -- Actualizar correo si el solicitante existente no tenía
      update public.solicitante
         set correo = coalesce(correo, nullif(btrim(p_correo), ''))
       where id = v_solicitante_id;
    end if;
  end if;

  insert into public.usuario (id, nombre, correo, rol, solicitante_id)
  values (p_id, btrim(p_nombre), nullif(btrim(p_correo), ''), p_rol, v_solicitante_id);

  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (p_creada_por, 'CUENTA_CREADA', 'usuario', p_id::text,
          jsonb_build_object('nombre', p_nombre, 'rol', p_rol, 'solicitante_id', v_solicitante_id));
end $$;

-- ---------------------------------------------------------------------
-- 3. Consultar ficha del alumno desde la sesión de selección
-- ---------------------------------------------------------------------
create or replace function public.seleccion_mi_ficha()
returns table (
  solicitante_id uuid,
  nombre_completo text,
  matricula text,
  grupo text,
  correo text,
  impedimento text
)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', array['SELECCION']::public.rol_usuario[]);
  s  public.solicitante;
begin
  if yo.solicitante_id is null then
    return;
  end if;
  select * into s from public.solicitante where id = yo.solicitante_id;
  if not found then
    return;
  end if;
  return query
    select s.id, s.nombre_completo, s.matricula_o_clave, s.grupo_area, s.correo,
           app.impedimento_solicitante(s.id);
end $$;

-- ---------------------------------------------------------------------
-- 4. Crear solicitud desde sesión de selección
-- ---------------------------------------------------------------------
create or replace function public.solicitud_crear_sesion(
  p_id uuid,
  p_lineas jsonb,
  p_motivo text,
  p_fecha_devolucion date,
  p_nota text default null
)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo            public.usuario := app.exigir('SESION', array['SELECCION']::public.rol_usuario[]);
  s             public.solicitante;
  v_impedimento text;
  v_en_curso    text;
  v_folio       text;
  v_vence       timestamptz;
  v_plazo_max   integer;
  v_vistos      uuid[] := '{}';
  l             jsonb;
  a             record;
begin
  if yo.solicitante_id is null then
    raise exception 'Tu cuenta no está vinculada a una ficha de alumno. Habla con el responsable del laboratorio.'
      using errcode = 'PT403', detail = 'SIN_FICHA_ALUMNO';
  end if;

  select * into s from public.solicitante where id = yo.solicitante_id for update;
  if not found then
    raise exception 'No se encontró tu ficha de alumno.';
  end if;

  v_impedimento := app.impedimento_solicitante(s.id);
  if v_impedimento is not null then
    raise exception 'No puedes pedir material. % Acude al laboratorio.', v_impedimento;
  end if;

  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Elige para qué necesitas el material.';
  end if;

  -- Freno: una solicitud en curso a la vez
  select string_agg(sol.folio, ', ') into v_en_curso
    from public.solicitud sol
   where sol.solicitante_id = s.id and sol.estado in ('PENDIENTE', 'APROBADA') and sol.confirmada_en is not null;
  if v_en_curso is not null then
    raise exception 'Ya tienes la solicitud % en curso. Espera a que se resuelva o cancélala antes de pedir de nuevo.', v_en_curso;
  end if;

  -- Fecha de vencimiento
  v_plazo_max := app.config_int('plazo_max_alumno_dias');
  if p_fecha_devolucion is null then
    v_vence := app.al_fin_de_jornada(app.hoy() + app.config_int('plazo_default_dias'));
  else
    v_vence := app.al_fin_de_jornada(p_fecha_devolucion);
  end if;
  if v_vence <= now() then
    raise exception 'La fecha de devolución ya pasó.';
  end if;
  if (v_vence at time zone app.zona_horaria())::date > app.hoy() + v_plazo_max then
    raise exception 'La fecha de devolución puede ser a lo más en % días.', v_plazo_max;
  end if;

  -- Validar artículos
  if jsonb_typeof(p_lineas) <> 'array' or jsonb_array_length(p_lineas) = 0 then
    raise exception 'Tu solicitud no tiene artículos.';
  end if;
  if jsonb_array_length(p_lineas) > 20 then
    raise exception 'Una solicitud puede tener hasta 20 artículos.';
  end if;

  for l in select * from jsonb_array_elements(p_lineas) loop
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

  -- Crear la solicitud ya confirmada
  insert into public.solicitud (
    id, solicitante_id, motivo, fecha_devolucion_comprometida,
    confirmada_en, confirmada_como, confirmada_por
  ) values (
    p_id, s.id, btrim(p_motivo) || coalesce(': ' || nullif(btrim(p_nota), ''), ''), v_vence,
    now(), 'EN_PERSONA', yo.id
  )
  returning solicitud.folio into v_folio;

  insert into public.solicitud_linea (solicitud_id, articulo_id, cantidad)
  select p_id, (x ->> 'articulo_id')::uuid, (x ->> 'cantidad')::integer
    from jsonb_array_elements(p_lineas) x;

  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITUD_CREADA', 'solicitud', p_id::text,
          jsonb_build_object('folio', v_folio, 'de_seleccion', true));

  perform app.avisar_responsables(
    'Solicitud de material',
    format('%s (Selección) pidió material (%s)', s.nombre_completo, v_folio),
    '/solicitudes'
  );

  return jsonb_build_object('id', p_id, 'folio', v_folio);
end $$;

-- ---------------------------------------------------------------------
-- 5. Listar mis solicitudes desde sesión de selección
-- ---------------------------------------------------------------------
create or replace function public.mis_solicitudes_sesion(p_estado text default null)
returns table (
  id uuid, folio text, estado text, motivo text,
  creada_en timestamptz, fecha_devolucion_comprometida timestamptz,
  articulos text, cantidad_total bigint, nota_aprobacion text, motivo_rechazo text
)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', array['SELECCION']::public.rol_usuario[]);
begin
  if yo.solicitante_id is null then
    return;
  end if;
  return query
    select s.id, s.folio, s.estado::text, s.motivo, s.creada_en, s.fecha_devolucion_comprometida,
           app.lista_articulos(s.id, s.estado in ('APROBADA', 'ENTREGADO', 'DEVUELTA')),
           coalesce((select sum(l.cantidad) from public.solicitud_linea l where l.solicitud_id = s.id), 0)::bigint,
           s.nota_aprobacion, s.motivo_rechazo
      from public.solicitud s
     where s.solicitante_id = yo.solicitante_id
       and (p_estado is null or s.estado::text = p_estado)
     order by s.creada_en desc;
end $$;

-- ---------------------------------------------------------------------
-- 6. Cancelar solicitud propia desde sesión de selección
-- ---------------------------------------------------------------------
create or replace function public.solicitud_cancelar_sesion(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', array['SELECCION']::public.rol_usuario[]);
  s  public.solicitud;
begin
  select * into s from public.solicitud where id = p_id for update;
  if not found or s.solicitante_id <> yo.solicitante_id then
    raise exception 'Esa solicitud no existe.';
  end if;
  if s.estado <> 'PENDIENTE' then
    raise exception 'Solo se pueden cancelar solicitudes pendientes.';
  end if;
  update public.solicitud
     set estado = 'CANCELADA', cancelada_por = yo.id, cancelada_en = now(),
         motivo_cancelacion = 'Cancelada por el alumno'
   where id = p_id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'SOLICITUD_CANCELADA', 'solicitud', p_id::text,
          jsonb_build_object('motivo', 'Cancelada por el alumno'));
end $$;

-- ---------------------------------------------------------------------
-- 7. Permisos
-- ---------------------------------------------------------------------
revoke all on function public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid, text, text, text)
  to service_role;

do $$
declare f text;
begin
  foreach f in array array[
    'public.seleccion_mi_ficha()',
    'public.solicitud_crear_sesion(uuid, jsonb, text, date, text)',
    'public.mis_solicitudes_sesion(text)',
    'public.solicitud_cancelar_sesion(uuid)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
