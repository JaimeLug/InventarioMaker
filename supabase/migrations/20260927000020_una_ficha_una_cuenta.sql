-- Fase 11, cierre: una ficha de alumno no puede quedar compartida por dos cuentas.
--
-- Si por un error de dedo se crean dos cuentas de selección con la misma matrícula, las dos
-- quedarían pegadas a la misma ficha: compartirían solicitudes, préstamos y adeudos. Aquí se
-- impide, con un aviso claro al crear y con un candado en la base por si acaso.

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

    -- Una ficha de alumno, una sola cuenta: si no, dos personas compartirían historial y adeudos.
    if v_solicitante_id is not null
       and exists (select 1 from public.usuario u where u.solicitante_id = v_solicitante_id and u.id <> p_id) then
      raise exception 'Ya hay una cuenta con la matrícula %. Revisa si es la misma persona.', v_mat
        using errcode = 'PT400', detail = 'MATRICULA_REPETIDA';
    end if;

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

create unique index if not exists usuario_solicitante_unico
  on public.usuario (solicitante_id) where solicitante_id is not null;

revoke all on function public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid, text, text, text)
  to service_role;
