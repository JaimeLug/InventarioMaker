-- Fase 10: buscar por nombre a quien ya pasó por el taller.
--
-- La regla no cambia para los demás: a un alumno nuevo solo se le encuentra escribiendo su
-- matrícula exacta. Esta búsqueda solo alcanza a quienes ya pidieron o ya recibieron material,
-- que son a los que se les vuelve a prestar y de los que no siempre se recuerda la matrícula.
-- Cada búsqueda queda anotada en la bitácora, con el texto buscado y cuántos salieron.

create function app.sin_acentos(t text) returns text
language sql immutable set search_path = '' as $$
  select lower(translate(coalesce(t, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'))
$$;

create function public.solicitante_buscar_conocido(p_texto text)
returns table (id uuid, nombre_completo text, tipo public.tipo_solicitante, grupo_area text,
               matricula_o_clave text, bloqueado boolean, verificada boolean, vencidos integer)
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('SESION');
  texto text := btrim(coalesce(p_texto, ''));
  n     integer := 0;
begin
  if length(texto) < 3 then
    raise exception 'Escribe al menos 3 letras del nombre.';
  end if;

  select count(*) into n
    from public.solicitante s
   where not s.posible_duplicado
     and app.sin_acentos(s.nombre_completo) like '%' || app.sin_acentos(texto) || '%'
     and (exists (select 1 from public.solicitud q where q.solicitante_id = s.id)
       or exists (select 1 from public.movimiento m where m.responsable_solicitante_id = s.id));

  insert into public.bitacora (usuario_id, evento, tabla, datos)
  values (yo.id, 'BUSQUEDA_POR_NOMBRE', 'solicitante', jsonb_build_object('texto', texto, 'encontrados', n));

  return query
    select s.id, s.nombre_completo, s.tipo, s.grupo_area, s.matricula_o_clave, s.bloqueado,
           s.verificada_en is not null,
           (select count(*) from app.v_prestamos_abiertos pa
             where pa.responsable_solicitante_id = s.id and pa.vencido)::integer
      from public.solicitante s
     where not s.posible_duplicado
       and app.sin_acentos(s.nombre_completo) like '%' || app.sin_acentos(texto) || '%'
       -- solo quienes ya pasaron por el taller: pidieron o se les prestó
       and (exists (select 1 from public.solicitud q where q.solicitante_id = s.id)
         or exists (select 1 from public.movimiento m where m.responsable_solicitante_id = s.id))
     order by s.nombre_completo
     limit 15;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.sin_acentos(text)', 'public.solicitante_buscar_conocido(text)'] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
