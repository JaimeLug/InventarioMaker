-- Fase 11: la selección de robótica propone, el responsable decide.
--
-- Cómo está pensado el permiso: la cuenta de selección se NIEGA por omisión. app.exigir solo la
-- deja pasar donde se la nombra a propósito, así que cualquier función que no se tocó aquí
-- (prestar, devolver, dar de baja, ver alumnos, reportes, cuentas…) le queda cerrada sola.
--
-- Lo que sí puede: ver el catálogo (que ya es público), subir fotos, proponer un artículo nuevo,
-- proponer correcciones, proponer ubicación, contar (suelto y dentro del inventario periódico)
-- y reportar daños o pérdidas. Todo queda como propuesta con su nombre.

-- ---------------------------------------------------------------------
-- Quién puede pasar
-- ---------------------------------------------------------------------
create or replace function app.exigir(p_nivel text default 'SESION', p_roles public.rol_usuario[] default null)
returns public.usuario
language plpgsql stable security definer set search_path = '' as $$
declare
  u      public.usuario;
  expira timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Identifícate para continuar.' using errcode = 'PT401', detail = 'SIN_SESION';
  end if;
  select * into u from public.usuario where id = auth.uid();
  if not found or not u.activo then
    raise exception 'Tu cuenta no está activa. Habla con el responsable del laboratorio.'
      using errcode = 'PT403', detail = 'CUENTA_INACTIVA';
  end if;
  expira := app.sesion_expira_en();
  if expira is null or expira <= now() then
    raise exception 'Tu sesión terminó. Vuelve a identificarte.' using errcode = 'PT401', detail = 'SESION_VENCIDA';
  end if;
  if p_roles is not null and not (u.rol = any (p_roles)) then
    raise exception 'Tu cuenta no puede hacer esto.' using errcode = 'PT403', detail = 'ROL';
  end if;
  -- La selección de robótica solo entra donde se la nombra: lo demás se le niega por omisión.
  if u.rol::text = 'SELECCION' and (p_roles is null or not ('SELECCION' = any (p_roles::text[]))) then
    raise exception 'Tu cuenta no puede hacer esto.' using errcode = 'PT403', detail = 'ROL';
  end if;
  if p_nivel = 'CONTRASENA' and app.nivel_sesion() <> 'CONTRASENA' then
    raise exception 'Esta acción necesita que entres con tu contraseña.'
      using errcode = 'PT403', detail = 'NIVEL_CONTRASENA';
  end if;
  return u;
end $$;

-- Los cuatro roles que trabajan en el taller; se usa donde la selección también entra.
-- En plpgsql a propósito: así el valor nuevo del enum se resuelve al usarse, no al crear la función.
create function app.roles_con_seleccion() returns public.rol_usuario[]
language plpgsql immutable set search_path = '' as $$
begin
  return array['DOCENTE', 'RESPONSABLE', 'SUBADMIN', 'SELECCION']::public.rol_usuario[];
end $$;

-- Subir al almacén de fotos: la selección también.
create or replace function app.puede_subir_foto() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION', app.roles_con_seleccion());
  return true;
exception when others then
  return false;
end $$;

-- Avisar a una persona (ya existía el aviso a los responsables, no a uno en concreto).
create function app.avisar(p_usuario uuid, p_titulo text, p_cuerpo text, p_ruta text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.aviso (usuario_id, titulo, cuerpo, ruta)
  select u.id, p_titulo, p_cuerpo, p_ruta from public.usuario u where u.id = p_usuario and u.activo;
end $$;

-- La lista de "¿Quién eres?" es solo de quien entra con PIN: la selección entra con su correo.
create or replace function public.pin_usuarios() returns table (id uuid, nombre text)
language sql stable security definer set search_path = '' as $$
  select u.id, u.nombre from public.usuario u
  where u.activo and u.pin_hash is not null and u.rol::text <> 'SELECCION'
  order by u.nombre
$$;

-- ---------------------------------------------------------------------
-- Fotos: quedan "sin verificar" hasta que el responsable las acepta
-- ---------------------------------------------------------------------
alter table public.foto add column if not exists verificada_por uuid references public.usuario(id);
alter table public.foto add column if not exists verificada_en timestamptz;

-- Las que ya existen las tomó personal del taller: quedan verificadas.
update public.foto set verificada_en = coalesce(verificada_en, tomada_en) where verificada_en is null;

create or replace function public.foto_agregar(p_articulo uuid, p_ruta text, p_tipo public.tipo_foto default 'GENERAL',
                                               p_principal boolean default false)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo            public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  a             public.articulo;
  hay_principal boolean;
  de_seleccion  boolean := yo.rol::text = 'SELECCION';
  nueva         uuid;
begin
  select * into a from public.articulo where id = p_articulo for update;
  if not found then
    raise exception 'El artículo no existe.';
  end if;
  if not a.activo then
    raise exception 'No se agregan fotos a un artículo dado de baja.';
  end if;
  if p_tipo not in ('GENERAL', 'PLACA_SERIE', 'ETIQUETA_RESGUARDO') then
    raise exception 'Ese tipo de foto se agrega desde un reporte o una entrega.';
  end if;
  if p_ruta is null or p_ruta not like 'articulos/' || p_articulo::text || '/%' then
    raise exception 'Ruta de foto inválida.';
  end if;
  if not app.archivo_existe('fotos', p_ruta) then
    raise exception 'La foto no terminó de subirse. Intenta de nuevo.';
  end if;

  hay_principal := exists (select 1 from public.foto f where f.articulo_id = p_articulo and f.es_principal);
  if p_principal and hay_principal then
    -- Cambiar la foto principal es de responsable o sub administración (matriz de permisos).
    perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
    update public.foto set es_principal = false where articulo_id = p_articulo and es_principal;
  end if;

  insert into public.foto (articulo_id, url, tipo, tomada_por, es_principal, verificada_por, verificada_en)
  values (p_articulo, p_ruta, p_tipo, yo.id, (p_principal or not hay_principal) and not de_seleccion,
          case when de_seleccion then null else yo.id end,
          case when de_seleccion then null else now() end)
  returning id into nueva;

  if de_seleccion then
    perform app.avisar_responsables('Foto por verificar', format('%s subió una foto de %s', yo.nombre, a.nombre), '/por-revisar');
  end if;
  return nueva;
end $$;

-- Las fotos del personal del taller nacen verificadas; las de la selección, no.
create function app.foto_nace_verificada() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.verificada_en is null and new.tomada_por is not null
     and (select u.rol::text from public.usuario u where u.id = new.tomada_por) <> 'SELECCION' then
    new.verificada_por := new.tomada_por;
    new.verificada_en := now();
  end if;
  return new;
end $$;
create trigger nace_verificada before insert on public.foto for each row execute function app.foto_nace_verificada();

-- El responsable acepta la foto (y la puede volver principal) o la descarta.
create function public.foto_verificar(p_foto uuid, p_aceptar boolean, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  f  public.foto;
begin
  select * into f from public.foto where id = p_foto for update;
  if not found or f.borrada_en is not null then
    raise exception 'Esa foto ya no está.';
  end if;
  if p_aceptar then
    update public.foto set verificada_por = yo.id, verificada_en = now() where id = p_foto;
    -- Si el artículo no tenía foto principal, esta lo es.
    if not exists (select 1 from public.foto x where x.articulo_id = f.articulo_id and x.es_principal and x.borrada_en is null) then
      update public.foto set es_principal = true where id = p_foto;
    end if;
  else
    if btrim(coalesce(p_motivo, '')) = '' then
      raise exception 'Escribe por qué se descarta la foto.';
    end if;
    update public.foto set borrada_en = now(), borrada_motivo = btrim(p_motivo), es_principal = false where id = p_foto;
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, case when p_aceptar then 'FOTO_VERIFICADA' else 'FOTO_DESCARTADA' end, 'foto', p_foto::text,
          jsonb_build_object('motivo', p_motivo));
end $$;

create function public.fotos_por_verificar() returns table (
  id uuid, articulo_id uuid, codigo text, nombre text, url text, tipo public.tipo_foto,
  tomada_por text, tomada_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select f.id, f.articulo_id, a.codigo, a.nombre, f.url, f.tipo, u.nombre, f.tomada_en
      from public.foto f
      join public.articulo a on a.id = f.articulo_id
      left join public.usuario u on u.id = f.tomada_por
     where f.verificada_en is null and f.borrada_en is null
       and (select x.rol::text from public.usuario x where x.id = f.tomada_por) = 'SELECCION'
     order by f.tomada_en;
end $$;

-- ---------------------------------------------------------------------
-- Propuestas de alta y de corrección
-- ---------------------------------------------------------------------
create table public.propuesta (
  id            uuid primary key,
  tipo          text not null check (tipo in ('ALTA', 'CORRECCION')),
  articulo_id   uuid references public.articulo(id),          -- solo en CORRECCION; en un ALTA el id de la propuesta será el del artículo
  datos         jsonb not null default '{}'::jsonb,
  cantidad      integer,
  fotos         jsonb not null default '[]'::jsonb,
  nota          text,
  estado        text not null default 'PENDIENTE' check (estado in ('PENDIENTE', 'APROBADA', 'DESCARTADA')),
  creada_por    uuid not null references public.usuario(id),
  creada_en     timestamptz not null default now(),
  resuelta_por  uuid references public.usuario(id),
  resuelta_en   timestamptz,
  motivo        text,
  check (tipo <> 'CORRECCION' or articulo_id is not null)
);
create index propuesta_pendientes_idx on public.propuesta (estado, creada_en);
alter table public.propuesta enable row level security;

-- Artículos parecidos, para no capturar dos veces lo mismo.
create function public.articulos_parecidos(p_texto text)
returns table (id uuid, codigo text, nombre text, marca_modelo text, categoria text, foto text)
language plpgsql stable security definer set search_path = '' as $$
declare
  texto text := app.sin_acentos(btrim(coalesce(p_texto, '')));
begin
  perform app.exigir('SESION', app.roles_con_seleccion());
  if length(texto) < 3 then
    return;
  end if;
  return query
    select a.id, a.codigo, a.nombre, a.marca_modelo, a.categoria::text, v.foto_principal_url
      from public.articulo a
      join public.v_inventario v on v.id = a.id
     where a.activo
       and (app.sin_acentos(a.nombre) like '%' || texto || '%'
         or texto like '%' || app.sin_acentos(a.nombre) || '%'
         or app.sin_acentos(coalesce(a.marca_modelo, '')) like '%' || texto || '%')
     order by length(a.nombre)
     limit 5;
end $$;

-- Proponer: el alta de un artículo nuevo o la corrección de uno que ya existe.
create function public.propuesta_crear(p_id uuid, p_tipo text, p_datos jsonb, p_articulo uuid default null,
                                       p_cantidad integer default null, p_fotos jsonb default '[]'::jsonb,
                                       p_nota text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  a  public.articulo;
begin
  if exists (select 1 from public.propuesta where id = p_id) then
    return p_id;   -- el mismo envío otra vez
  end if;
  if p_tipo not in ('ALTA', 'CORRECCION') then
    raise exception 'Tipo de propuesta desconocido: %', p_tipo;
  end if;
  if jsonb_typeof(p_datos) <> 'object' or p_datos = '{}'::jsonb then
    raise exception 'Escribe qué propones.';
  end if;
  if app.campos_no_editables(p_datos) is not null then
    raise exception 'Estos datos no se capturan aquí: %', app.campos_no_editables(p_datos);
  end if;

  if p_tipo = 'ALTA' then
    if btrim(coalesce(p_datos ->> 'nombre', '')) = '' then
      raise exception 'Escribe el nombre del artículo.';
    end if;
    if jsonb_typeof(p_fotos) <> 'array' or jsonb_array_length(p_fotos) = 0 then
      raise exception 'Agrega al menos una foto del artículo.';
    end if;
  else
    select * into a from public.articulo where id = p_articulo;
    if not found or not a.activo then
      raise exception 'El artículo no existe o está dado de baja.';
    end if;
  end if;

  insert into public.propuesta (id, tipo, articulo_id, datos, cantidad, fotos, nota, creada_por)
  values (p_id, p_tipo, case when p_tipo = 'CORRECCION' then p_articulo end, p_datos, p_cantidad,
          coalesce(p_fotos, '[]'::jsonb), nullif(btrim(p_nota), ''), yo.id);

  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'PROPUESTA_CREADA', 'propuesta', p_id::text, jsonb_build_object('tipo', p_tipo));
  perform app.avisar_responsables(
    case when p_tipo = 'ALTA' then 'Artículo propuesto' else 'Corrección propuesta' end,
    format('%s: %s', yo.nombre, coalesce(p_datos ->> 'nombre', a.nombre, 'sin nombre')), '/por-revisar');
  return p_id;
end $$;

-- La lista: el responsable ve todas; quien propone, solo las suyas.
create function public.propuestas_listar(p_estado text default 'PENDIENTE')
returns table (id uuid, tipo text, articulo_id uuid, codigo text, nombre_actual text, datos jsonb, cantidad integer,
               fotos jsonb, nota text, estado text, creada_por text, creada_en timestamptz, motivo text)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  mias  boolean := yo.rol::text = 'SELECCION';
begin
  return query
    select p.id, p.tipo, p.articulo_id, a.codigo, a.nombre, p.datos, p.cantidad, p.fotos, p.nota, p.estado,
           u.nombre, p.creada_en, p.motivo
      from public.propuesta p
      left join public.articulo a on a.id = p.articulo_id and p.tipo = 'CORRECCION'
      join public.usuario u on u.id = p.creada_por
     where (p_estado is null or p.estado = p_estado)
       and (not mias or p.creada_por = yo.id)
     order by p.creada_en;
end $$;

-- Aprobar: el alta entra al inventario y la corrección se aplica, con nota de quién la propuso.
create function public.propuesta_aprobar(p_id uuid, p_datos jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  p      public.propuesta;
  quien  text;
  datos  jsonb;
  r      jsonb;
begin
  select * into p from public.propuesta where id = p_id for update;
  if not found then
    raise exception 'Esa propuesta ya no está.';
  end if;
  if p.estado <> 'PENDIENTE' then
    raise exception 'Esa propuesta ya se había resuelto.';
  end if;
  select u.nombre into quien from public.usuario u where u.id = p.creada_por;
  datos := coalesce(p_datos, p.datos);

  if p.tipo = 'ALTA' then
    r := public.articulo_crear(p.id, datos, p.cantidad, p.fotos, null);
  else
    perform public.articulo_editar(p.articulo_id, datos, format('Propuesta de %s', quien));
    r := jsonb_build_object('ok', true, 'articulo', p.articulo_id);
  end if;

  update public.propuesta set estado = 'APROBADA', resuelta_por = yo.id, resuelta_en = now() where id = p_id;
  -- Las fotos que venían con la propuesta quedan verificadas: el responsable ya las vio al aprobar.
  update public.foto set verificada_por = yo.id, verificada_en = now()
   where articulo_id = coalesce(p.articulo_id, p.id) and verificada_en is null and borrada_en is null;

  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'PROPUESTA_APROBADA', 'propuesta', p_id::text, jsonb_build_object('de', quien, 'tipo', p.tipo));
  perform app.avisar(p.creada_por, 'Tu propuesta se aceptó', coalesce(datos ->> 'nombre', 'Artículo'), '/mis-propuestas');
  return r;
end $$;

create function public.propuesta_descartar(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  p  public.propuesta;
begin
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué no procede, para que quien la hizo aprenda.';
  end if;
  select * into p from public.propuesta where id = p_id for update;
  if not found or p.estado <> 'PENDIENTE' then
    raise exception 'Esa propuesta ya se había resuelto.';
  end if;
  update public.propuesta
     set estado = 'DESCARTADA', resuelta_por = yo.id, resuelta_en = now(), motivo = btrim(p_motivo)
   where id = p_id;
  -- Las fotos que venían con ella no se quedan sueltas.
  update public.foto set borrada_en = now(), borrada_motivo = btrim(p_motivo), es_principal = false
   where articulo_id = p.id and verificada_en is null and borrada_en is null and p.tipo = 'ALTA';
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'PROPUESTA_DESCARTADA', 'propuesta', p_id::text, jsonb_build_object('motivo', btrim(p_motivo)));
  perform app.avisar(p.creada_por, 'Tu propuesta no procedió', btrim(p_motivo), '/mis-propuestas');
end $$;

-- ---------------------------------------------------------------------
-- Lo que ya existía y ahora también puede la selección
-- ---------------------------------------------------------------------
create or replace function public.conteo_proponer(p_articulo uuid, p_en_taller integer, p_nota text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  a   public.articulo;
  e   record;
  nuevo uuid;
begin
  select * into a from public.articulo where id = p_articulo;
  if not found or not a.activo then
    raise exception 'El artículo no existe o está dado de baja.';
  end if;
  if p_en_taller is null or p_en_taller < 0 then
    raise exception 'Escribe cuántos hay en el taller.';
  end if;
  select * into e from public.v_existencias where articulo_id = p_articulo;
  update public.conteo_propuesto
     set estado = 'DESCARTADO', resuelto_por = yo.id, resuelto_en = now(), motivo = 'Reemplazado por un conteo nuevo'
   where articulo_id = p_articulo and contado_por = yo.id and estado = 'PENDIENTE';
  insert into public.conteo_propuesto (articulo_id, en_taller, sistema, nota, contado_por)
  values (p_articulo, p_en_taller, e.en_taller, nullif(btrim(p_nota), ''), yo.id)
  returning id into nuevo;
  return jsonb_build_object('id', nuevo, 'sistema', e.en_taller, 'diferencia', p_en_taller - e.en_taller);
end $$;

create or replace function public.ubicacion_proponer(p_articulo uuid, p_contenedor uuid, p_nota text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('SESION', app.roles_con_seleccion());
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
  if yo.rol::text in ('DOCENTE', 'SELECCION') then
    perform app.avisar_responsables('Propuesta de ubicación', format('%s: está en %s', a.nombre, c.codigo), '/por-revisar');
  end if;
  return nueva;
end $$;

create or replace function public.incidencia_reportar(
  p_id uuid, p_articulo uuid, p_tipo public.tipo_incidencia, p_cantidad integer, p_prestamo uuid,
  p_nota text, p_fotos jsonb, p_sin_foto text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo              public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  resp_usuario    uuid;
  resp_solicitante uuid;
begin
  if p_tipo = 'CONSUMO' then
    raise exception 'El consumo se registra con "Registrar uso".';
  end if;
  if exists (select 1 from public.incidencia i where i.id = p_id) then
    return p_id;   -- reintento del mismo reporte
  end if;
  -- Si viene de un préstamo, queda a cargo de quien lo tiene.
  select pa.responsable_usuario_id, pa.responsable_solicitante_id into resp_usuario, resp_solicitante
    from app.v_prestamos_abiertos pa where pa.prestamo_id = p_prestamo;
  return app.crear_incidencia(yo.id, p_id, p_articulo, p_tipo, p_cantidad, p_prestamo, p_nota, p_fotos, p_sin_foto,
                              resp_usuario, resp_solicitante);
end $$;

create or replace function public.inventario_contar(p_inventario uuid, p_articulo uuid, p_cantidad integer,
                                                    p_contenedor uuid default null, p_nota text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('SESION', app.roles_con_seleccion());
  i   public.inventario_periodico;
  e   record;
begin
  select * into i from public.inventario_periodico where id = p_inventario;
  if not found or i.estado <> 'ABIERTO' then
    raise exception 'Ese inventario ya está cerrado.';
  end if;
  if not exists (select 1 from app.inventario_alcance(p_inventario) x where x.articulo_id = p_articulo) then
    raise exception 'Ese artículo no está en el alcance de este inventario: regístralo como hallazgo.';
  end if;
  if p_cantidad is null or p_cantidad < 0 then
    raise exception 'Escribe cuántos hay.';
  end if;
  if exists (select 1 from public.inventario_decision x where x.inventario_id = p_inventario and x.articulo_id = p_articulo and x.decision is not null) then
    raise exception 'Ese artículo ya se revisó. Si hay que contarlo otra vez, pide que lo manden a recontar.';
  end if;
  select * into e from public.v_existencias where articulo_id = p_articulo;
  update public.conteo_linea
     set cantidad_fisica = p_cantidad, cantidad_sistema = e.en_taller, contado_en = now(), nota = nullif(btrim(p_nota), ''),
         contenedor_id = coalesce(p_contenedor, contenedor_id)
   where inventario_id = p_inventario and articulo_id = p_articulo and contado_por = yo.id and not anulado;
  if not found then
    insert into public.conteo_linea (inventario_id, articulo_id, contenedor_id, cantidad_sistema, cantidad_fisica, nota, contado_por)
    values (p_inventario, p_articulo, p_contenedor, e.en_taller, p_cantidad, nullif(btrim(p_nota), ''), yo.id);
  end if;
end $$;

-- Sus propios reportes de daño o pérdida (mismo cuerpo, solo cambia quién puede).
create or replace function public.mis_reportes()
returns table (id uuid, tipo text, estado text, articulo_id uuid, codigo text, nombre text, cantidad integer, nota text,
               reportada_en timestamptz, resuelta_por text, motivo_resolucion text, fotos text[], comentarios jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', app.roles_con_seleccion());
begin
  return query
    select i.id, i.tipo::text, i.estado::text, a.id, a.codigo, a.nombre, i.cantidad, i.nota, i.reportada_en,
           app.nombre_usuario(i.resuelta_por), i.motivo_resolucion,
           coalesce((select array_agg(f.url order by f.tomada_en) from public.foto f where f.incidencia_id = i.id), '{}'),
           coalesce((select jsonb_agg(jsonb_build_object('autor', app.nombre_usuario(c.autor_id), 'texto', c.texto, 'en', c.en)
                                      order by c.en)
                     from public.incidencia_comentario c where c.incidencia_id = i.id), '[]'::jsonb)
    from public.incidencia i join public.articulo a on a.id = i.articulo_id
    where i.reportada_por = yo.id
    order by i.estado <> 'PENDIENTE', i.reportada_en desc
    limit 100;
end $$;

create or replace function public.avisos_sin_leer() returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', app.roles_con_seleccion());
begin
  return (select count(*)::integer from public.aviso a where a.usuario_id = yo.id and a.leido_en is null);
end $$;

create or replace function public.avisos_listar() returns table (id uuid, titulo text, cuerpo text, ruta text, creado_en timestamptz, leido boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION', app.roles_con_seleccion());
begin
  return query
    select a.id, a.titulo, a.cuerpo, a.ruta, a.creado_en, a.leido_en is not null
    from public.aviso a where a.usuario_id = yo.id
    order by a.creado_en desc limit 50;
end $$;

-- ---------------------------------------------------------------------
-- Cuentas de selección: las crea y administra el responsable, y no llevan PIN
-- ---------------------------------------------------------------------
create or replace function public.cuenta_autorizar(p_accion text, p_rol public.rol_usuario default null, p_usuario uuid default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo      public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  destino public.usuario;
begin
  if p_accion not in ('CREAR', 'DESACTIVAR', 'REACTIVAR', 'CONTRASENA') then
    raise exception 'Acción desconocida: %', p_accion;
  end if;

  if p_accion = 'CREAR' then
    if p_rol is null then
      raise exception 'Falta el rol de la cuenta.';
    end if;
    if yo.rol = 'RESPONSABLE' and p_rol::text not in ('DOCENTE', 'SELECCION') then
      raise exception 'El responsable del laboratorio crea cuentas de docentes y de la selección de robótica.'
        using errcode = 'PT403', detail = 'ROL';
    end if;
  else
    select * into destino from public.usuario where id = p_usuario;
    if not found then
      raise exception 'La cuenta no existe.';
    end if;
    if yo.rol = 'RESPONSABLE' and destino.rol::text not in ('DOCENTE', 'SELECCION') and destino.id <> yo.id then
      raise exception 'El responsable del laboratorio administra cuentas de docentes y de la selección de robótica.'
        using errcode = 'PT403', detail = 'ROL';
    end if;
    if p_accion = 'DESACTIVAR' and destino.id = yo.id then
      raise exception 'No puedes desactivar tu propia cuenta.';
    end if;
  end if;

  perform app.exigir_confirmacion();
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'CUENTA_' || p_accion || '_AUTORIZADA', 'usuario', p_usuario::text, jsonb_build_object('rol', p_rol));
  return yo.id;
end $$;

create or replace function public.pin_establecer(p_usuario uuid, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo      public.usuario := app.exigir('CONTRASENA');
  destino public.usuario;
begin
  select * into destino from public.usuario where id = p_usuario for update;
  if not found then
    raise exception 'La cuenta no existe.';
  end if;
  if destino.rol::text = 'SELECCION' then
    raise exception 'La selección de robótica entra con su correo y su contraseña, no con PIN.'
      using errcode = 'PT403', detail = 'ROL';
  end if;
  if destino.id <> yo.id then
    if yo.rol = 'DOCENTE' then
      raise exception 'Solo puedes cambiar tu propio PIN.' using errcode = 'PT403', detail = 'ROL';
    end if;
    if yo.rol = 'RESPONSABLE' and destino.rol <> 'DOCENTE' then
      raise exception 'El responsable del laboratorio solo administra cuentas de docentes.' using errcode = 'PT403', detail = 'ROL';
    end if;
  end if;
  perform app.validar_pin_nuevo(p_pin);
  perform app.exigir_confirmacion();

  update public.usuario
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 8)),
         pin_intentos_fallidos = 0, pin_bloqueado_hasta = null
   where id = destino.id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id)
  values (yo.id, 'PIN_ESTABLECIDO', 'usuario', destino.id::text);
end $$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'app.roles_con_seleccion()',
    'app.avisar(uuid, text, text, text)',
    'public.foto_verificar(uuid, boolean, text)',
    'public.fotos_por_verificar()',
    'public.articulos_parecidos(text)',
    'public.propuesta_crear(uuid, text, jsonb, uuid, integer, jsonb, text)',
    'public.propuestas_listar(text)',
    'public.propuesta_aprobar(uuid, jsonb)',
    'public.propuesta_descartar(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
