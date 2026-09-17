-- =====================================================================
-- 0009 · Contenedores, acomodo y etiquetas (Fase 4a)
--
-- Flujos: F-12 alta de contenedores, F-03 escaneo (contenido de un contenedor, prestar y devolver
-- varios), y el acomodo de artículos. La regla "VEX y FTC no se mezclan" ya la hacen cumplir los
-- disparadores de 0001; aquí se decide quién mueve qué y se deja registro.
--
-- Decisiones de la Fase 4 (aprobadas el 2026-09-16):
--   * Los QR llevan la dirección de la app web: <url_app>/q/C-0012. Por eso la dirección debe estar
--     publicada antes de imprimir.
--   * Responsable y sub administración mueven directo; un docente propone y ellos aceptan o rechazan.
--   * Un contenedor no se borra: se desactiva, y solo si está vacío.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Propuestas de ubicación (un docente encontró algo fuera de su lugar)
-- ---------------------------------------------------------------------
create table public.propuesta_ubicacion (
  id             uuid primary key default gen_random_uuid(),
  articulo_id    uuid not null references public.articulo (id),
  contenedor_id  uuid not null references public.contenedor (id),
  nota           text,
  propuesta_por  uuid not null references public.usuario (id),
  propuesta_en   timestamptz not null default now(),
  estado         text not null default 'PENDIENTE' check (estado in ('PENDIENTE', 'ACEPTADA', 'RECHAZADA')),
  resuelta_por   uuid references public.usuario (id),
  resuelta_en    timestamptz,
  motivo         text,
  check ((estado = 'PENDIENTE') = (resuelta_en is null))
);
create index propuesta_ubicacion_pendiente_idx on public.propuesta_ubicacion (propuesta_en) where estado = 'PENDIENTE';
alter table public.propuesta_ubicacion enable row level security;
revoke all on public.propuesta_ubicacion from anon, authenticated;
create trigger sin_borrado before delete on public.propuesta_ubicacion for each row execute function app.prohibir_borrado();


-- ---------------------------------------------------------------------
-- Vista pública de contenedores (sin nombres de personas)
-- ---------------------------------------------------------------------
create view public.v_contenedores as
select
  c.id, c.codigo, c.nombre, c.tipo, c.padre_id, p.codigo as padre_codigo, c.categoria_exclusiva, c.foto_url, c.nota, c.activo,
  app.ruta_contenedor(c.id) as ruta,
  (select count(*) from public.articulo a where a.contenedor_id = c.id and a.activo)::integer as articulos,
  (select count(*) from public.contenedor h where h.padre_id = c.id and h.activo)::integer as subcontenedores,
  c.version, c.actualizado_en
from public.contenedor c
left join public.contenedor p on p.id = c.padre_id;
comment on view public.v_contenedores is
  'Catálogo público de contenedores con su ruta. Corre con permisos del dueño a propósito, como v_inventario.';
grant select on public.v_contenedores to anon, authenticated;

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create function app.tipo_contenedor_valido(p text) returns boolean
language sql immutable set search_path = '' as $$
  select p in ('GABINETE', 'CAJON', 'CANASTA', 'GAVETA', 'BOLSA', 'REPISA', 'CAJA', 'OTRO')
$$;

-- La foto de un contenedor vive en fotos/contenedores/<id>/…
create function app.validar_foto_contenedor(p_id uuid, p_ruta text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_ruta is null then
    return;
  end if;
  if p_ruta not like 'contenedores/' || p_id::text || '/%' then
    raise exception 'Ruta de foto inválida.';
  end if;
  if not app.archivo_existe('fotos', p_ruta) then
    raise exception 'La foto no terminó de subirse. Intenta de nuevo.';
  end if;
end $$;

-- Mensajes de la base en español para las reglas de VEX y FTC.
create function app.mover_articulo(p_yo uuid, p_articulo uuid, p_contenedor uuid, p_origen text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  a public.articulo;
  c public.contenedor;
begin
  select * into a from public.articulo where id = p_articulo for update;
  if not found then
    raise exception 'El artículo no existe.';
  end if;
  if not a.activo then
    raise exception '"%" está dado de baja: no se acomoda.', a.nombre;
  end if;
  if p_contenedor is not null then
    select * into c from public.contenedor where id = p_contenedor;
    if not found or not c.activo then
      raise exception 'El contenedor no existe o está desactivado.';
    end if;
    if a.categoria in ('VEX', 'FTC') and c.categoria_exclusiva is distinct from a.categoria then
      raise exception '"%" es %: solo puede ir en un contenedor "Solo %". % es %.',
        a.nombre, a.categoria, a.categoria, c.codigo,
        case when c.categoria_exclusiva is null then 'mixto' else 'solo ' || c.categoria_exclusiva end;
    end if;
    if c.categoria_exclusiva is not null and c.categoria_exclusiva <> a.categoria then
      raise exception '% es solo para %; "%" es %.', c.codigo, c.categoria_exclusiva, a.nombre, a.categoria;
    end if;
  end if;
  if a.contenedor_id is not distinct from p_contenedor then
    return false;
  end if;
  update public.articulo set contenedor_id = p_contenedor where id = p_articulo;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (p_yo, 'UBICACION', 'articulo', p_articulo::text,
          jsonb_build_object('de', a.contenedor_id, 'a', p_contenedor, 'origen', p_origen));
  return true;
end $$;

-- ---------------------------------------------------------------------
-- F-12 Contenedores (responsable y sub administración)
-- ---------------------------------------------------------------------
-- El id lo genera la app para subir la foto a contenedores/<id>/ antes de llamar.
create function public.contenedor_crear(p_id uuid, p_nombre text, p_tipo text, p_padre uuid default null,
                                        p_categoria public.categoria_articulo default null, p_foto text default null,
                                        p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  c  public.contenedor;
begin
  if exists (select 1 from public.contenedor where id = p_id) then
    select * into c from public.contenedor where id = p_id;
    return jsonb_build_object('id', c.id, 'codigo', c.codigo);   -- reintento
  end if;
  if length(btrim(coalesce(p_nombre, ''))) < 2 then
    raise exception 'Escribe el nombre del contenedor.';
  end if;
  if not coalesce(app.tipo_contenedor_valido(p_tipo), false) then
    raise exception 'Elige el tipo de contenedor.';
  end if;
  if p_categoria is not null and p_categoria not in ('VEX', 'FTC') then
    raise exception 'Un contenedor puede ser Solo VEX, Solo FTC o mixto.';
  end if;
  if p_padre is not null and not exists (select 1 from public.contenedor where id = p_padre and activo) then
    raise exception 'El contenedor de arriba no existe o está desactivado.';
  end if;
  perform app.validar_foto_contenedor(p_id, p_foto);

  begin
    insert into public.contenedor (id, nombre, tipo, padre_id, categoria_exclusiva, foto_url, nota)
    values (p_id, btrim(p_nombre), p_tipo, p_padre, p_categoria, p_foto, nullif(btrim(p_nota), ''))
    returning * into c;
  exception when raise_exception then
    -- validar_contenedor: el de arriba es exclusivo de otra categoría
    raise exception '%', replace(sqlerrm, 'contenedor padre', 'contenedor de arriba');
  end;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'CONTENEDOR_CREADO', 'contenedor', c.id::text, jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre));
  return jsonb_build_object('id', c.id, 'codigo', c.codigo);
end $$;

create function public.contenedor_editar(p_id uuid, p_nombre text, p_tipo text, p_padre uuid,
                                         p_categoria public.categoria_articulo, p_foto text, p_nota text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  c  public.contenedor;
begin
  select * into c from public.contenedor where id = p_id for update;
  if not found then
    raise exception 'El contenedor no existe.';
  end if;
  if length(btrim(coalesce(p_nombre, ''))) < 2 then
    raise exception 'Escribe el nombre del contenedor.';
  end if;
  if not coalesce(app.tipo_contenedor_valido(p_tipo), false) then
    raise exception 'Elige el tipo de contenedor.';
  end if;
  if p_categoria is not null and p_categoria not in ('VEX', 'FTC') then
    raise exception 'Un contenedor puede ser Solo VEX, Solo FTC o mixto.';
  end if;
  if p_padre is not null and not exists (select 1 from public.contenedor where id = p_padre and activo) then
    raise exception 'El contenedor de arriba no existe o está desactivado.';
  end if;
  if p_foto is distinct from c.foto_url then
    perform app.validar_foto_contenedor(p_id, p_foto);
  end if;
  -- Los mensajes de las reglas (se metería dentro de sí mismo, VEX/FTC) vienen de app.validar_contenedor.
  update public.contenedor
     set nombre = btrim(p_nombre), tipo = p_tipo, padre_id = p_padre, categoria_exclusiva = p_categoria,
         foto_url = p_foto, nota = nullif(btrim(p_nota), '')
   where id = p_id;
end $$;

-- Solo vacío: sin artículos activos ni contenedores activos dentro.
create function public.contenedor_activar(p_id uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  c  public.contenedor;
  n  integer;
begin
  select * into c from public.contenedor where id = p_id for update;
  if not found then
    raise exception 'El contenedor no existe.';
  end if;
  if not p_activo then
    select count(*) into n from public.articulo where contenedor_id = p_id and activo;
    if n > 0 then
      raise exception '% todavía tiene % artículo(s). Muévelos antes de desactivarlo.', c.codigo, n;
    end if;
    if exists (select 1 from public.contenedor where padre_id = p_id and activo) then
      raise exception '% tiene contenedores adentro. Muévelos o desactívalos primero.', c.codigo;
    end if;
  elsif c.padre_id is not null and not exists (select 1 from public.contenedor where id = c.padre_id and activo) then
    raise exception 'El contenedor de arriba está desactivado: reactívalo primero.';
  end if;
  update public.contenedor set activo = p_activo where id = p_id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id)
  values (yo.id, case when p_activo then 'CONTENEDOR_REACTIVADO' else 'CONTENEDOR_DESACTIVADO' end, 'contenedor', p_id::text);
end $$;

-- Acomodo: uno o varios artículos a un contenedor (null = sin ubicación). Devuelve cuántos cambiaron.
create function public.articulos_acomodar(p_articulos uuid[], p_contenedor uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  a  uuid;
  n  integer := 0;
begin
  if coalesce(array_length(p_articulos, 1), 0) = 0 then
    raise exception 'Elige al menos un artículo.';
  end if;
  foreach a in array p_articulos loop
    if app.mover_articulo(yo.id, a, p_contenedor, 'DIRECTO') then
      n := n + 1;
    end if;
  end loop;
  -- Lo que se acomodó ya no está "fuera de su lugar".
  update public.propuesta_ubicacion
     set estado = 'RECHAZADA', resuelta_por = yo.id, resuelta_en = now(), motivo = 'Se acomodó directamente'
   where articulo_id = any (p_articulos) and estado = 'PENDIENTE';
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Propuestas de docentes
-- ---------------------------------------------------------------------
create function public.ubicacion_proponer(p_articulo uuid, p_contenedor uuid, p_nota text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('SESION');
  a     public.articulo;
  c     public.contenedor;
  nueva uuid;
begin
  select * into a from public.articulo where id = p_articulo;
  select * into c from public.contenedor where id = p_contenedor;
  if a.id is null or not a.activo then
    raise exception 'El artículo no existe o está dado de baja.';
  end if;
  if c.id is null or not c.activo then
    raise exception 'El contenedor no existe o está desactivado.';
  end if;
  if a.contenedor_id = p_contenedor then
    raise exception '"%" ya está registrado en %.', a.nombre, c.codigo;
  end if;
  if a.categoria in ('VEX', 'FTC') and c.categoria_exclusiva is distinct from a.categoria then
    raise exception '"%" es % y % no es "Solo %".', a.nombre, a.categoria, c.codigo, a.categoria;
  end if;
  if c.categoria_exclusiva is not null and c.categoria_exclusiva <> a.categoria then
    raise exception '% es solo para %.', c.codigo, c.categoria_exclusiva;
  end if;
  -- Una propuesta abierta por artículo: la nueva reemplaza a la anterior.
  update public.propuesta_ubicacion
     set estado = 'RECHAZADA', resuelta_por = yo.id, resuelta_en = now(), motivo = 'Reemplazada por una propuesta nueva'
   where articulo_id = p_articulo and estado = 'PENDIENTE';
  insert into public.propuesta_ubicacion (articulo_id, contenedor_id, nota, propuesta_por)
  values (p_articulo, p_contenedor, nullif(btrim(p_nota), ''), yo.id)
  returning id into nueva;
  if yo.rol = 'DOCENTE' then
    perform app.avisar_responsables('Propuesta de ubicación', format('%s: está en %s', a.nombre, c.codigo), '/por-revisar');
  end if;
  return nueva;
end $$;

create function public.ubicacion_propuestas()
returns table (id uuid, articulo_id uuid, articulo_codigo text, articulo text, categoria text, actual text,
               contenedor_id uuid, contenedor_codigo text, propuesta text, nota text, propuesta_por text, propuesta_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select p.id, a.id, a.codigo, a.nombre, a.categoria::text, app.ruta_contenedor(a.contenedor_id),
           c.id, c.codigo, app.ruta_contenedor(c.id), p.nota, app.nombre_usuario(p.propuesta_por), p.propuesta_en
    from public.propuesta_ubicacion p
    join public.articulo a on a.id = p.articulo_id
    join public.contenedor c on c.id = p.contenedor_id
    where p.estado = 'PENDIENTE'
    order by p.propuesta_en;
end $$;

create function public.ubicacion_resolver(p_id uuid, p_aceptar boolean, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  p  public.propuesta_ubicacion;
begin
  select * into p from public.propuesta_ubicacion where id = p_id for update;
  if not found or p.estado <> 'PENDIENTE' then
    raise exception 'Esa propuesta ya se resolvió.';
  end if;
  if not p_aceptar and btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué se rechaza.';
  end if;
  if p_aceptar then
    perform app.mover_articulo(yo.id, p.articulo_id, p.contenedor_id, 'PROPUESTA');
  end if;
  update public.propuesta_ubicacion
     set estado = case when p_aceptar then 'ACEPTADA' else 'RECHAZADA' end,
         resuelta_por = yo.id, resuelta_en = now(), motivo = nullif(btrim(p_motivo), '')
   where id = p_id;
end $$;

-- "Por revisar" también cuenta las propuestas de ubicación.
create or replace function public.por_revisar_contar() returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  if yo.rol = 'DOCENTE' then
    return 0;
  end if;
  return (select count(*)::integer from public.incidencia where estado = 'PENDIENTE')
       + (select count(*)::integer from public.propuesta_ubicacion where estado = 'PENDIENTE');
end $$;

-- ---------------------------------------------------------------------
-- F-03 Préstamos abiertos de lo que vive en un contenedor (para "Devolver varios")
-- ---------------------------------------------------------------------
create function public.prestamos_de_contenedor(p_contenedor uuid)
returns table (prestamo_id uuid, articulo_id uuid, codigo text, nombre text, unidad text, pendiente integer,
               vence_en timestamptz, vencido boolean, a_cargo text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select pa.prestamo_id, a.id, a.codigo, a.nombre, a.unidad, pa.pendiente::integer, pa.vence_en, pa.vencido,
           coalesce(app.nombre_usuario(pa.responsable_usuario_id), app.nombre_solicitante(pa.responsable_solicitante_id))
    from app.v_prestamos_abiertos pa
    join public.articulo a on a.id = pa.articulo_id
    where a.contenedor_id = p_contenedor
    order by a.nombre, pa.vence_en;
end $$;

-- ---------------------------------------------------------------------
-- Almacén: fotos de contenedores (público para ver, como las del catálogo)
-- ---------------------------------------------------------------------
create function app.puede_subir_foto_contenedor() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return true;
exception when others then
  return false;
end $$;

create policy fotos_subir_contenedores on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = 'contenedores' and app.puede_subir_foto_contenedor());

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on all functions in schema app from public;
grant execute on function app.puede_subir_foto(), app.puede_subir_foto_contenedor(), app.puede_subir_privado(text),
                          app.puede_ver_privado(text) to authenticated;
grant execute on function app.ruta_contenedor(uuid) to anon, authenticated;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('contenedor_crear', 'contenedor_editar', 'contenedor_activar', 'articulos_acomodar',
                        'ubicacion_proponer', 'ubicacion_propuestas', 'ubicacion_resolver', 'por_revisar_contar',
                        'prestamos_de_contenedor')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to authenticated', f.firma);
  end loop;
end $$;
