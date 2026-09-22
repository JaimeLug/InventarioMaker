-- Fase 10: devolver sin señal un préstamo que también se hizo sin señal.
--
-- Un préstamo hecho sin señal todavía no existe en el servidor cuando se devuelve, así que el
-- celular no tiene su identificador. Sí tiene el del comando, y el servidor guardó ese mismo
-- valor en movimiento.comando_id al aplicar el préstamo. Aquí se acepta cualquiera de los dos.
-- Lo demás es igual que antes (migración 0006).

create or replace function public.devolucion_registrar(p_lineas jsonb, p_comando uuid default null) returns jsonb
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
      -- Préstamo hecho sin señal: el celular no conoce su identificador, manda el del comando
      -- (el mismo que quedó en movimiento.comando_id al aplicarlo).
      select p.* into pa
        from app.v_prestamos_abiertos p
        join public.movimiento m on m.id = p.prestamo_id
       where m.comando_id = (l ->> 'prestamo_id')::uuid;
    end if;
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

do $$
begin
  revoke all on function public.devolucion_registrar(jsonb, uuid) from public;
  grant execute on function public.devolucion_registrar(jsonb, uuid) to authenticated, service_role;
end $$;
