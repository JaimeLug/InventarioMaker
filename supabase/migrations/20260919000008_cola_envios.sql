-- =====================================================================
-- 0008 · Ajustes a la cola de envíos (Fase 3b)
--
--   1. Un correo que no salió en 2 días ya no se manda: si el servicio de correo se configura
--      tarde, no deben llegar confirmaciones de solicitudes que ya se cancelaron solas.
--   2. La tarea de cada 5 minutos solo despierta a la función "avisos" si hay algo que hacer.
-- =====================================================================

insert into public.configuracion (clave, valor, descripcion) values
  ('envio_caduca_horas', '48', 'Horas tras las cuales un correo o aviso que no salió ya no se manda')
on conflict (clave) do nothing;

create function app.caducar_envios() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  update public.envio
     set estado = 'FALLIDO', error = coalesce(error || ' · ', '') || 'Caducó sin enviarse'
   where estado = 'PENDIENTE' and creado_en < now() - make_interval(hours => app.config_int('envio_caduca_horas'));
  get diagnostics n = row_count;
  return n;
end $$;

create function app.hay_trabajo_para_avisos() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.envio where estado = 'PENDIENTE')
      or exists (select 1 from public.identificaciones_por_borrar(1))
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Mismo nombre: reemplaza la tarea creada en 0007.
    execute $cron$select cron.schedule('inventario-tareas', '*/5 * * * *',
      'select app.tareas_periodicas(); select app.caducar_envios(); select app.despertar_envios() where app.hay_trabajo_para_avisos();')$cron$;
  end if;
end $$;

revoke execute on all functions in schema app from public;
grant execute on function app.puede_subir_foto(), app.puede_subir_privado(text), app.puede_ver_privado(text) to authenticated;
