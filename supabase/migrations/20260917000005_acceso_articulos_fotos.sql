-- =====================================================================
-- 0005 · Acceso, cuentas, alta y edición de artículos, fotos (Fase 2)
--
-- Niveles de acceso (docs/flujos.md, sección 0):
--   SESION      N1  cualquier sesión vigente, abierta con PIN o con contraseña
--   CONTRASENA  N2  la sesión se abrió con contraseña
--   confirmar   N3  además, la contraseña se reconfirmó hace menos de 5 minutos;
--                   la reconfirmación se gasta en una sola acción
--
-- La app reconoce estos errores (el código se vuelve estado HTTP en la API):
--   PT401  sin sesión o sesión vencida        -> pedir acceso y reintentar
--   PT403  detalle ROL | NIVEL_CONTRASENA | CONFIRMAR_CONTRASENA | CUENTA_INACTIVA
--
-- Toda escritura pasa por funciones de este archivo; las tablas siguen cerradas.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

insert into public.configuracion (clave, valor, descripcion) values
  ('reconfirmacion_minutos',  '5', 'Minutos que vale una reconfirmación de contraseña para una acción grave'),
  ('contrasena_intentos_max', '5', 'Reconfirmaciones fallidas antes de esperar')
on conflict (clave) do nothing;

-- Reconfirmaciones de contraseña vigentes, una por sesión.
create table public.reconfirmacion (
  session_id  uuid primary key,
  usuario_id  uuid not null references public.usuario (id),
  hasta       timestamptz not null
);
alter table public.reconfirmacion enable row level security;
revoke all on public.reconfirmacion from anon, authenticated;

-- ---------------------------------------------------------------------
-- Sesión
-- ---------------------------------------------------------------------
create function app.sesion_id() returns uuid
language sql stable set search_path = '' as $$
  select nullif(auth.jwt() ->> 'session_id', '')::uuid
$$;

-- Supabase firma en el token con qué método se abrió la sesión.
-- Contraseña = "password"; el acceso con PIN entra por enlace de un solo uso ("otp").
create function app.nivel_sesion() returns text
language sql stable set search_path = '' as $$
  select case
    when auth.uid() is null then 'PUBLICO'
    when exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) m
                 where m ->> 'method' = 'password') then 'CONTRASENA'
    else 'PIN'
  end
$$;

-- La jornada se cuenta desde que se abrió la sesión, aunque el token se renueve.
create function app.sesion_expira_en() returns timestamptz
language sql stable security definer set search_path = '' as $$
  select s.created_at + make_interval(hours => app.config_int('sesion_horas'))
  from auth.sessions s
  where s.id = app.sesion_id() and s.user_id = auth.uid()
$$;

create function app.exigir(p_nivel text default 'SESION', p_roles public.rol_usuario[] default null)
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
  if p_nivel = 'CONTRASENA' and app.nivel_sesion() <> 'CONTRASENA' then
    raise exception 'Esta acción necesita que entres con tu contraseña.'
      using errcode = 'PT403', detail = 'NIVEL_CONTRASENA';
  end if;
  if p_roles is not null and not (u.rol = any (p_roles)) then
    raise exception 'Tu cuenta no puede hacer esto.' using errcode = 'PT403', detail = 'ROL';
  end if;
  return u;
end $$;

-- Gasta la reconfirmación de esta sesión. Si no hay, la app pide la contraseña y reintenta.
create function app.exigir_confirmacion() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.reconfirmacion
   where session_id = app.sesion_id() and usuario_id = auth.uid() and hasta > now();
  if not found then
    raise exception 'Confirma tu contraseña para continuar.' using errcode = 'PT403', detail = 'CONFIRMAR_CONTRASENA';
  end if;
end $$;

create function public.mi_sesion() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  u      public.usuario;
  expira timestamptz;
begin
  if auth.uid() is null then
    return null;
  end if;
  select * into u from public.usuario where id = auth.uid();
  if not found then
    return jsonb_build_object('activo', false, 'vigente', false);
  end if;
  expira := app.sesion_expira_en();
  return jsonb_build_object(
    'id', u.id, 'nombre', u.nombre, 'rol', u.rol, 'activo', u.activo,
    'nivel', app.nivel_sesion(), 'expira_en', expira, 'vigente', coalesce(expira > now(), false),
    'tiene_pin', u.pin_hash is not null);
end $$;

-- No lanza error al fallar: así el intento fallido sí queda registrado.
create function public.confirmar_contrasena(p_contrasena text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA');
  maximo integer := app.config_int('contrasena_intentos_max');
  fallas integer;
  hash   text;
begin
  select count(*) into fallas from public.bitacora
   where usuario_id = yo.id and evento = 'CONTRASENA_FALLIDA'
     and en > now() - make_interval(mins => app.config_int('pin_bloqueo_minutos'));
  if fallas >= maximo then
    return jsonb_build_object('ok', false, 'motivo', 'BLOQUEADO',
      'mensaje', format('Demasiados intentos. Espera %s minutos.', app.config_int('pin_bloqueo_minutos')));
  end if;

  select encrypted_password into hash from auth.users where id = yo.id;
  if p_contrasena is null or hash is null or extensions.crypt(p_contrasena, hash) <> hash then
    insert into public.bitacora (usuario_id, evento, tabla, registro_id)
    values (yo.id, 'CONTRASENA_FALLIDA', 'usuario', yo.id::text);
    return jsonb_build_object('ok', false, 'motivo', 'INCORRECTA', 'restantes', maximo - fallas - 1,
      'mensaje', format('Contraseña incorrecta. Te quedan %s intentos.', maximo - fallas - 1));
  end if;

  insert into public.reconfirmacion (session_id, usuario_id, hasta)
  values (app.sesion_id(), yo.id, now() + make_interval(mins => app.config_int('reconfirmacion_minutos')))
  on conflict (session_id) do update set usuario_id = excluded.usuario_id, hasta = excluded.hasta;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- PIN
-- ---------------------------------------------------------------------
create function app.validar_pin_nuevo(p_pin text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN debe tener de 4 a 6 números.';
  end if;
  if p_pin ~ '^(.)\1+$' then
    raise exception 'El PIN no puede ser el mismo número repetido.';
  end if;
  if position(p_pin in '01234567890123456') > 0 or position(p_pin in '98765432109876543') > 0 then
    raise exception 'El PIN no puede ser una secuencia como 1234.';
  end if;
end $$;

-- Nombres para elegir en la pantalla de PIN. Solo nombres de cuentas activas con PIN.
create function public.pin_usuarios() returns table (id uuid, nombre text)
language sql stable security definer set search_path = '' as $$
  select u.id, u.nombre from public.usuario u
  where u.activo and u.pin_hash is not null
  order by u.nombre
$$;

-- Solo la llama la función del servidor "acceso-pin" (llave secreta).
-- No lanza error al fallar: así los intentos fallidos se cuentan.
create function public.pin_verificar(p_usuario uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u      public.usuario;
  maximo integer := app.config_int('pin_intentos_max');
  espera integer := app.config_int('pin_bloqueo_minutos');
  fallas integer;
begin
  select * into u from public.usuario where id = p_usuario for update;
  if not found or not u.activo or u.pin_hash is null then
    return jsonb_build_object('ok', false, 'motivo', 'NO_DISPONIBLE', 'mensaje', 'Esa cuenta no puede entrar con PIN.');
  end if;
  if u.pin_bloqueado_hasta > now() then
    return jsonb_build_object('ok', false, 'motivo', 'BLOQUEADO', 'mensaje',
      format('Demasiados intentos. Podrás intentar de nuevo a las %s.',
             to_char(u.pin_bloqueado_hasta at time zone app.zona_horaria(), 'HH24:MI')));
  end if;

  if p_pin is not null and extensions.crypt(p_pin, u.pin_hash) = u.pin_hash then
    update public.usuario set pin_intentos_fallidos = 0, pin_bloqueado_hasta = null where id = u.id;
    insert into public.bitacora (usuario_id, evento, tabla, registro_id) values (u.id, 'ACCESO_PIN', 'usuario', u.id::text);
    return jsonb_build_object('ok', true, 'correo', (select a.email from auth.users a where a.id = u.id));
  end if;

  fallas := u.pin_intentos_fallidos + 1;
  if fallas >= maximo then
    update public.usuario set pin_intentos_fallidos = 0, pin_bloqueado_hasta = now() + make_interval(mins => espera)
     where id = u.id;
    insert into public.bitacora (usuario_id, evento, tabla, registro_id) values (u.id, 'PIN_BLOQUEADO', 'usuario', u.id::text);
    return jsonb_build_object('ok', false, 'motivo', 'BLOQUEADO',
      'mensaje', format('PIN incorrecto. Por seguridad, esta cuenta no podrá usar PIN durante %s minutos.', espera));
  end if;
  update public.usuario set pin_intentos_fallidos = fallas where id = u.id;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id) values (u.id, 'PIN_FALLIDO', 'usuario', u.id::text);
  return jsonb_build_object('ok', false, 'motivo', 'PIN_INCORRECTO', 'restantes', maximo - fallas,
    'mensaje', format('PIN incorrecto. Te quedan %s intentos.', maximo - fallas));
end $$;

create function public.pin_establecer(p_usuario uuid, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo      public.usuario := app.exigir('CONTRASENA');
  destino public.usuario;
begin
  select * into destino from public.usuario where id = p_usuario for update;
  if not found then
    raise exception 'La cuenta no existe.';
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
-- Cuentas (las crea el responsable o sub administración; no hay registro público)
-- ---------------------------------------------------------------------
create function public.cuentas_listar()
returns table (id uuid, nombre text, correo text, rol public.rol_usuario, activo boolean,
               tiene_pin boolean, pin_bloqueado_hasta timestamptz, creado_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select u.id, u.nombre, u.correo, u.rol, u.activo, u.pin_hash is not null, u.pin_bloqueado_hasta, u.creado_en
    from public.usuario u
    order by u.activo desc, u.nombre;
end $$;

-- La función del servidor "cuentas" la llama con el token de quien opera,
-- antes de tocar Supabase Auth con la llave secreta.
create function public.cuenta_autorizar(p_accion text, p_rol public.rol_usuario default null, p_usuario uuid default null)
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
    if yo.rol = 'RESPONSABLE' and p_rol <> 'DOCENTE' then
      raise exception 'El responsable del laboratorio solo puede crear cuentas de docentes.' using errcode = 'PT403', detail = 'ROL';
    end if;
  else
    select * into destino from public.usuario where id = p_usuario;
    if not found then
      raise exception 'La cuenta no existe.';
    end if;
    if yo.rol = 'RESPONSABLE' and destino.rol <> 'DOCENTE' and destino.id <> yo.id then
      raise exception 'El responsable del laboratorio solo administra cuentas de docentes.' using errcode = 'PT403', detail = 'ROL';
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

-- Solo la función del servidor, después de crear la cuenta en Supabase Auth.
create function public.cuenta_registrar(p_id uuid, p_nombre text, p_rol public.rol_usuario, p_correo text, p_creada_por uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.usuario (id, nombre, correo, rol) values (p_id, btrim(p_nombre), nullif(btrim(p_correo), ''), p_rol);
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (p_creada_por, 'CUENTA_CREADA', 'usuario', p_id::text, jsonb_build_object('nombre', p_nombre, 'rol', p_rol));
end $$;

create function public.cuenta_cambiar_estado(p_id uuid, p_activo boolean, p_por uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.usuario set activo = p_activo where id = p_id;
  if not found then
    raise exception 'La cuenta no existe.';
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id)
  values (p_por, case when p_activo then 'CUENTA_REACTIVADA' else 'CUENTA_DESACTIVADA' end, 'usuario', p_id::text);
end $$;

-- ---------------------------------------------------------------------
-- Artículos
-- ---------------------------------------------------------------------
create function app.archivo_existe(p_bucket text, p_ruta text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if to_regclass('storage.objects') is null then
    return true;
  end if;
  return exists (select 1 from storage.objects o where o.bucket_id = p_bucket and o.name = p_ruta);
end $$;

create function app.campos_no_editables(p_datos jsonb) returns text
language sql immutable set search_path = '' as $$
  select string_agg(k, ', ' order by k)
  from jsonb_object_keys(coalesce(p_datos, '{}'::jsonb)) k
  where k <> all (array['nombre', 'marca_modelo', 'categoria', 'subcategoria', 'unidad', 'estado_fisico',
                        'estado_fisico_texto', 'etiquetado', 'ubicacion', 'num_resguardo', 'num_serie',
                        'observaciones', 'es_consumible', 'minimo_reposicion'])
$$;

-- Alta (F-11). El id lo genera la app para poder subir las fotos a articulos/<id>/ antes de llamar.
create function public.articulo_crear(p_id uuid, p_datos jsonb, p_cantidad integer, p_fotos jsonb, p_comando uuid default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  resultado jsonb;
  d         public.articulo;
  f         jsonb;
  ruta      text;
  tipo      public.tipo_foto;
  n         integer := 0;
begin
  if p_comando is not null then
    select c.resultado into resultado from public.comando_aplicado c where c.id = p_comando;
    if found then
      return resultado;
    end if;
  end if;

  if app.campos_no_editables(p_datos) is not null then
    raise exception 'Estos datos no se capturan en el alta: %', app.campos_no_editables(p_datos);
  end if;
  d := jsonb_populate_record(null::public.articulo, p_datos);
  if btrim(coalesce(d.nombre, '')) = '' then
    raise exception 'Escribe el nombre del artículo.';
  end if;
  if d.categoria is null or d.categoria = 'SIN_CLASIFICAR' then
    raise exception 'Elige la categoría del artículo.';
  end if;
  if p_cantidad < 0 then
    raise exception 'La cantidad no puede ser negativa.';
  end if;
  if p_fotos is null or jsonb_typeof(p_fotos) <> 'array' or jsonb_array_length(p_fotos) = 0 then
    raise exception 'Agrega al menos una foto del artículo.';
  end if;

  begin
    insert into public.articulo (
      id, nombre, marca_modelo, categoria, subcategoria, unidad, estado_fisico, estado_fisico_texto,
      etiquetado, ubicacion, num_resguardo, num_serie, observaciones, es_consumible, minimo_reposicion,
      cantidad_estimada, conteo_desconocido, estado_inventario)
    values (
      p_id, btrim(d.nombre), nullif(btrim(d.marca_modelo), ''), d.categoria, nullif(btrim(d.subcategoria), ''),
      coalesce(nullif(btrim(d.unidad), ''), 'pieza'), d.estado_fisico, d.estado_fisico_texto,
      coalesce(d.etiquetado, case when d.es_consumible then 'LOTE' else 'CONTENEDOR' end::public.tipo_etiquetado),
      nullif(btrim(d.ubicacion), ''), nullif(btrim(d.num_resguardo), ''), nullif(btrim(d.num_serie), ''),
      d.observaciones, coalesce(d.es_consumible, false), d.minimo_reposicion,
      p_cantidad is null, p_cantidad is null,
      case when p_cantidad is null then 'POR_CONTAR' else 'VERIFICADO' end::public.estado_inventario);
  exception when unique_violation then
    raise exception 'Ese número de serie o de resguardo ya está registrado en otro artículo.';
  end;

  for f in select * from jsonb_array_elements(p_fotos) loop
    ruta := f ->> 'ruta';
    tipo := coalesce(f ->> 'tipo', 'GENERAL')::public.tipo_foto;
    if ruta is null or ruta not like 'articulos/' || p_id::text || '/%' then
      raise exception 'Ruta de foto inválida: %', ruta;
    end if;
    if tipo not in ('GENERAL', 'PLACA_SERIE', 'ETIQUETA_RESGUARDO') then
      raise exception 'Ese tipo de foto se agrega desde un reporte o una entrega.';
    end if;
    if not app.archivo_existe('fotos', ruta) then
      raise exception 'Una de las fotos no terminó de subirse. Intenta de nuevo.';
    end if;
    insert into public.foto (articulo_id, url, es_principal, tipo, tomada_por)
    values (p_id, ruta, n = 0, tipo, yo.id);
    n := n + 1;
  end loop;

  if p_cantidad > 0 then
    insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen, comando_id)
    values (p_id, 'ALTA', p_cantidad, 'Alta en la app', yo.id, yo.id, 'APP', p_comando);
  elsif p_cantidad is null then
    insert into public.tarea_pendiente (articulo_id, tipo, descripcion, origen, creada_por)
    values (p_id, 'CONTAR', 'Se dio de alta sin conteo: contar físicamente', 'SISTEMA', yo.id);
  end if;

  select jsonb_build_object('id', a.id, 'codigo', a.codigo) into resultado from public.articulo a where a.id = p_id;
  if p_comando is not null then
    insert into public.comando_aplicado (id, usuario_id, tipo, resultado) values (p_comando, yo.id, 'ARTICULO_CREAR', resultado);
  end if;
  return resultado;
end $$;

-- Edición de datos (no de cantidades: esas solo cambian con movimientos).
create function public.articulo_editar(p_id uuid, p_cambios jsonb, p_justificacion text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  actual public.articulo;
  nuevo  public.articulo;
begin
  select * into actual from public.articulo where id = p_id for update;
  if not found then
    raise exception 'El artículo no existe.';
  end if;
  if not actual.activo then
    raise exception 'No se edita un artículo dado de baja.';
  end if;
  if app.campos_no_editables(p_cambios) is not null then
    raise exception 'Estos datos no se editan aquí: %', app.campos_no_editables(p_cambios);
  end if;

  nuevo := jsonb_populate_record(actual, p_cambios);
  if btrim(coalesce(nuevo.nombre, '')) = '' then
    raise exception 'El nombre no puede quedar vacío.';
  end if;
  if nuevo.categoria = 'SIN_CLASIFICAR' and actual.categoria <> 'SIN_CLASIFICAR' then
    raise exception 'Un artículo clasificado no puede volver a "Sin clasificar".';
  end if;
  if actual.categoria in ('VEX', 'FTC') and nuevo.categoria in ('VEX', 'FTC') and actual.categoria <> nuevo.categoria then
    if btrim(coalesce(p_justificacion, '')) = '' then
      raise exception 'Para pasar un artículo entre VEX y FTC escribe por qué.';
    end if;
    perform app.exigir_confirmacion();
  end if;

  perform set_config('app.justificacion', coalesce(p_justificacion, ''), true);
  begin
    update public.articulo set
      nombre = btrim(nuevo.nombre), marca_modelo = nullif(btrim(nuevo.marca_modelo), ''), categoria = nuevo.categoria,
      subcategoria = nullif(btrim(nuevo.subcategoria), ''), unidad = coalesce(nullif(btrim(nuevo.unidad), ''), 'pieza'),
      estado_fisico = nuevo.estado_fisico, estado_fisico_texto = nuevo.estado_fisico_texto,
      etiquetado = nuevo.etiquetado, ubicacion = nullif(btrim(nuevo.ubicacion), ''),
      num_resguardo = nullif(btrim(nuevo.num_resguardo), ''), num_serie = nullif(btrim(nuevo.num_serie), ''),
      observaciones = nuevo.observaciones, es_consumible = nuevo.es_consumible, minimo_reposicion = nuevo.minimo_reposicion,
      -- Al clasificar algo que estaba "Sin clasificar", pasa a por contar o por verificar.
      estado_inventario = case
        when actual.categoria = 'SIN_CLASIFICAR' and nuevo.categoria <> 'SIN_CLASIFICAR' then
          case when actual.conteo_desconocido or actual.cantidad_estimada then 'POR_CONTAR' else 'POR_VERIFICAR' end::public.estado_inventario
        else estado_inventario end
    where id = p_id;
  exception when unique_violation then
    raise exception 'Ese número de serie o de resguardo ya está registrado en otro artículo.';
  end;
  return jsonb_build_object('id', p_id);
end $$;

-- ---------------------------------------------------------------------
-- Fotos (se acumulan: no se reemplazan ni se borran)
-- ---------------------------------------------------------------------
create function public.foto_agregar(p_articulo uuid, p_ruta text, p_tipo public.tipo_foto default 'GENERAL',
                                    p_principal boolean default false)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo            public.usuario := app.exigir('SESION');
  a             public.articulo;
  hay_principal boolean;
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

  insert into public.foto (articulo_id, url, tipo, tomada_por, es_principal)
  values (p_articulo, p_ruta, p_tipo, yo.id, p_principal or not hay_principal)
  returning id into nueva;
  return nueva;
end $$;

create function public.foto_hacer_principal(p_foto uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  articulo uuid;
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  select f.articulo_id into articulo from public.foto f
   where f.id = p_foto and f.articulo_id is not null
     and f.solicitud_id is null and f.incidencia_id is null and f.movimiento_id is null;
  if articulo is null then
    raise exception 'Esa foto no puede ser la principal.';
  end if;
  update public.foto set es_principal = false where articulo_id = articulo and es_principal and id <> p_foto;
  update public.foto set es_principal = true where id = p_foto;
end $$;

-- ---------------------------------------------------------------------
-- Almacén de fotos del catálogo
-- ---------------------------------------------------------------------
-- Público para ver (el catálogo es abierto). Las fotos privadas de solicitudes e
-- incidencias irán en otro almacén privado (Fase 3b).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create function app.puede_subir_foto() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return true;
exception when others then
  return false;
end $$;

-- Solo se sube (no hay reglas para reemplazar ni borrar): las fotos se acumulan.
create policy fotos_subir_articulos on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = 'articulos' and app.puede_subir_foto());

-- ---------------------------------------------------------------------
-- Permisos de ejecución
-- ---------------------------------------------------------------------
revoke execute on all functions in schema app from public;
grant execute on function app.puede_subir_foto() to authenticated;

revoke all on function
  public.mi_sesion(), public.pin_usuarios(), public.confirmar_contrasena(text), public.pin_verificar(uuid, text),
  public.pin_establecer(uuid, text), public.cuentas_listar(), public.cuenta_autorizar(text, public.rol_usuario, uuid),
  public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid), public.cuenta_cambiar_estado(uuid, boolean, uuid),
  public.articulo_crear(uuid, jsonb, integer, jsonb, uuid), public.articulo_editar(uuid, jsonb, text),
  public.foto_agregar(uuid, text, public.tipo_foto, boolean), public.foto_hacer_principal(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.mi_sesion(), public.pin_usuarios() to anon, authenticated;
grant execute on function
  public.confirmar_contrasena(text), public.pin_establecer(uuid, text), public.cuentas_listar(),
  public.cuenta_autorizar(text, public.rol_usuario, uuid),
  public.articulo_crear(uuid, jsonb, integer, jsonb, uuid), public.articulo_editar(uuid, jsonb, text),
  public.foto_agregar(uuid, text, public.tipo_foto, boolean), public.foto_hacer_principal(uuid)
to authenticated;
grant execute on function
  public.pin_verificar(uuid, text), public.cuenta_registrar(uuid, text, public.rol_usuario, text, uuid),
  public.cuenta_cambiar_estado(uuid, boolean, uuid)
to service_role;
