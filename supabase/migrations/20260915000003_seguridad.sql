-- =====================================================================
-- 0003 · Permisos base (Fase 1)
--
-- Punto de partida seguro: nadie escribe directo en las tablas desde la
-- app. Toda escritura va a pasar por funciones del servidor (Fases 2-3).
-- La lectura pública es solo del catálogo, sin datos de personas.
-- =====================================================================

-- Todas las tablas con RLS y sin permisos para la app ---------------------
do $$
declare
  t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
  for t in select viewname from pg_views where schemaname = 'public' loop
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- Catálogo de lectura abierta ---------------------------------------------
grant select on public.articulo, public.contenedor, public.foto,
                public.tarea_pendiente, public.configuracion
  to anon, authenticated;

create policy lectura_publica on public.articulo        for select to anon, authenticated using (true);
create policy lectura_publica on public.contenedor      for select to anon, authenticated using (true);
create policy lectura_publica on public.foto            for select to anon, authenticated using (true);
create policy lectura_publica on public.tarea_pendiente for select to anon, authenticated using (true);
create policy lectura_publica on public.configuracion   for select to anon, authenticated using (true);

-- Vistas públicas: agregados sin nombres de personas.
grant select on public.v_inventario, public.v_existencias, public.v_historial_publico,
                public.v_resumen_categoria
  to anon, authenticated;

-- Funciones internas: nadie las ejecuta salvo las vistas que las usan.
revoke execute on all functions in schema app from public;
grant usage on schema app to anon, authenticated;
grant execute on function app.ruta_contenedor(uuid) to anon, authenticated;
grant execute on function app.config_int(text) to anon, authenticated;

-- Las secuencias solo las usa el servidor.
revoke all on all sequences in schema app from public;
