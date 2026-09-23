-- Fase 11, ajuste: la selección de robótica también ve sus fotos esperando visto bueno.
--
-- Una foto no es una "propuesta" con su tarjeta, así que quien la subió no la veía en ningún lado
-- y parecía que se había perdido. Ahora: el responsable ve todas las pendientes; quien las subió,
-- solo las suyas.

create or replace function public.fotos_por_verificar() returns table (
  id uuid, articulo_id uuid, codigo text, nombre text, url text, tipo public.tipo_foto,
  tomada_por text, tomada_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo   public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  solo boolean := yo.rol::text = 'SELECCION';   -- la selección solo ve lo suyo
begin
  return query
    select f.id, f.articulo_id, a.codigo, a.nombre, f.url, f.tipo, u.nombre, f.tomada_en
      from public.foto f
      join public.articulo a on a.id = f.articulo_id
      left join public.usuario u on u.id = f.tomada_por
     where f.verificada_en is null and f.borrada_en is null
       and (select x.rol::text from public.usuario x where x.id = f.tomada_por) = 'SELECCION'
       and (not solo or f.tomada_por = yo.id)
     order by f.tomada_en;
end $$;
