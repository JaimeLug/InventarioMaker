-- Aviso claro cuando un conteo se quedó viejo.
--
-- Un conteo guarda cuántos había en el taller al contar y se aplica como diferencia. Si desde
-- entonces salieron piezas (préstamos, bajas, daños), la diferencia ya no cabe y el candado de
-- movimientos respondía «el ajuste dejaría el taller en -5», que no dice qué hacer. Ahora se
-- revisa antes y se pide volver a contar. Lo mismo al cerrar un inventario periódico.

create or replace function app.conteo_sigue_vigente(p_articulo uuid, p_codigo text, p_sistema integer, p_diferencia integer)
returns void
language plpgsql stable set search_path = '' as $$
declare
  v_ahora integer;
begin
  select en_taller into v_ahora from public.v_existencias where articulo_id = p_articulo;
  if coalesce(v_ahora, 0) + p_diferencia < 0 then
    raise exception 'Hubo movimientos de % desde que se contó (al contar había % en el taller y ahora hay %); cuéntalo de nuevo.',
      p_codigo, p_sistema, coalesce(v_ahora, 0);
  end if;
end $$;

create or replace function public.conteos_aplicar(p_ids uuid[], p_notas jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo      public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  c       record;
  v_nota  text;
  mov     uuid;
  ajustes integer := 0;
  n       integer := 0;
begin
  if coalesce(array_length(p_ids, 1), 0) = 0 then
    raise exception 'Elige al menos un conteo.';
  end if;
  -- Las explicaciones se revisan antes de gastar la reconfirmación.
  for c in select cp.*, a.codigo, a.nombre from public.conteo_propuesto cp join public.articulo a on a.id = cp.articulo_id
            where cp.id = any (p_ids) loop
    if c.estado <> 'PENDIENTE' then
      raise exception 'El conteo de % ya fue resuelto por alguien más.', c.codigo;
    end if;
    if c.en_taller <> c.sistema and coalesce(nullif(btrim(p_notas ->> c.id::text), ''), c.nota) is null then
      raise exception 'Falta explicar la diferencia de % (%).', c.codigo, c.en_taller - c.sistema;
    end if;
  end loop;
  perform app.exigir_confirmacion();

  for c in select cp.*, a.codigo from public.conteo_propuesto cp join public.articulo a on a.id = cp.articulo_id
            where cp.id = any (p_ids) order by a.id, cp.contado_en for update of cp loop
    mov := null;
    v_nota := coalesce(nullif(btrim(p_notas ->> c.id::text), ''), c.nota);
    if c.en_taller <> c.sistema then
      perform app.conteo_sigue_vigente(c.articulo_id, c.codigo, c.sistema, c.en_taller - c.sistema);
      begin
        insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
        values (c.articulo_id, 'AJUSTE_CONTEO', c.en_taller - c.sistema,
                format('Conteo físico (%s): %s', app.nombre_usuario(c.contado_por), v_nota), yo.id, c.contado_por, 'APP')
        returning id into mov;
      exception when raise_exception then
        raise exception 'No se pudo aplicar el conteo de %: %', c.codigo, sqlerrm;
      end;
      ajustes := ajustes + 1;
    end if;
    update public.articulo set cantidad_estimada = false, conteo_desconocido = false where id = c.articulo_id;
    update public.tarea_pendiente
       set resuelta = true, resuelta_por = yo.id, resuelta_en = now(),
           nota_resolucion = format('Contados %s en el taller por %s', c.en_taller, app.nombre_usuario(c.contado_por))
     where articulo_id = c.articulo_id and tipo = 'CONTAR' and not resuelta;
    update public.conteo_propuesto set estado = 'APLICADO', resuelto_por = yo.id, resuelto_en = now(), movimiento_id = mov where id = c.id;
    -- Otros conteos pendientes del mismo artículo quedan superados por este.
    update public.conteo_propuesto set estado = 'DESCARTADO', resuelto_por = yo.id, resuelto_en = now(), motivo = 'Se aplicó otro conteo'
     where articulo_id = c.articulo_id and estado = 'PENDIENTE' and id <> c.id and not (id = any (p_ids));
    insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
    values (yo.id, 'CONTEO', 'articulo', c.articulo_id::text,
            jsonb_build_object('en_sistema', c.sistema, 'contados', c.en_taller, 'diferencia', c.en_taller - c.sistema,
                               'contado_por', c.contado_por));
    n := n + 1;
  end loop;
  return jsonb_build_object('aplicados', n, 'ajustes', ajustes);
end $$;

create or replace function public.inventario_cerrar(p_inventario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  i         public.inventario_periodico;
  r         record;
  x         public.inventario_decision;
  mov       uuid;
  contados  integer := 0;
  ajustes   integer := 0;
  reportes  integer := 0;
  sin_contar integer := 0;
  pendientes text;
begin
  select * into i from public.inventario_periodico where id = p_inventario for update;
  if not found or i.estado <> 'ABIERTO' then
    raise exception 'Ese inventario ya está cerrado.';
  end if;
  select string_agg(a.codigo, ', ') into pendientes
    from app.inventario_resumen(p_inventario) s join public.articulo a on a.id = s.articulo_id where s.conflicto;
  if pendientes is not null then
    raise exception 'Hay conteos que no coinciden: %. Mándalos a recontar.', pendientes;
  end if;
  select string_agg(a.codigo, ', ') into pendientes
    from app.inventario_resumen(p_inventario) s join public.articulo a on a.id = s.articulo_id
    left join public.inventario_decision d on d.inventario_id = p_inventario and d.articulo_id = s.articulo_id
    where s.contados > 0 and s.diferencia <> 0 and d.decision is null;
  if pendientes is not null then
    raise exception 'Faltan decisiones en las diferencias de: %.', pendientes;
  end if;
  perform app.exigir_confirmacion();

  for r in select s.*, a.codigo, a.nombre from app.inventario_resumen(p_inventario) s join public.articulo a on a.id = s.articulo_id
            order by s.articulo_id loop
    if r.contados = 0 then
      sin_contar := sin_contar + 1;
      continue;
    end if;
    contados := contados + 1;
    select * into x from public.inventario_decision where inventario_id = p_inventario and articulo_id = r.articulo_id;
    mov := null;
    if r.diferencia <> 0 and x.decision = 'AJUSTE' then
      perform app.conteo_sigue_vigente(r.articulo_id, r.codigo, r.sistema, r.diferencia);
      begin
        insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen, inventario_id)
        values (r.articulo_id, 'AJUSTE_CONTEO', r.diferencia,
                format('Inventario "%s": %s', coalesce(i.nombre, 'periódico'), x.nota), yo.id, yo.id, 'INVENTARIO', p_inventario)
        returning id into mov;
      exception when raise_exception then
        raise exception 'No se pudo ajustar %: %', r.codigo, sqlerrm;
      end;
      update public.inventario_decision set movimiento_id = mov where inventario_id = p_inventario and articulo_id = r.articulo_id;
      ajustes := ajustes + 1;
    elsif x.decision = 'INCIDENCIA' then
      reportes := reportes + 1;
    end if;
    update public.articulo set cantidad_estimada = false, conteo_desconocido = false where id = r.articulo_id;
    update public.tarea_pendiente
       set resuelta = true, resuelta_por = yo.id, resuelta_en = now(),
           nota_resolucion = format('Contado en el inventario "%s": %s', coalesce(i.nombre, 'periódico'), r.fisico)
     where articulo_id = r.articulo_id and tipo = 'CONTAR' and not resuelta;
  end loop;

  update public.inventario_periodico set estado = 'CERRADO', fecha_cierre = now(), cerrado_por = yo.id where id = p_inventario;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'INVENTARIO_CERRADO', 'inventario_periodico', p_inventario::text,
          jsonb_build_object('contados', contados, 'ajustes', ajustes, 'reportes', reportes, 'no_contados', sin_contar,
                             'hallazgos_abiertos', (select count(*) from public.inventario_hallazgo h where h.inventario_id = p_inventario and h.decision is null)));
  return jsonb_build_object('contados', contados, 'ajustes', ajustes, 'reportes', reportes, 'no_contados', sin_contar);
end $$;

revoke execute on function app.conteo_sigue_vigente(uuid, text, integer, integer) from public;
