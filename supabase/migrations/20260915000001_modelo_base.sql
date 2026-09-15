-- =====================================================================
-- 0001 · Modelo base del inventario (Fase 1)
--
-- Tipos, tablas y reglas de integridad. El cálculo de existencias y la
-- validación de movimientos están en 0002; los permisos en 0003.
--
-- Reglas que este archivo ya hace cumplir:
--   * Nada se borra: artículos, contenedores, fotos, pendientes, etc.
--   * Los movimientos y la bitácora no se editan ni se borran.
--   * La cantidad de un artículo no se edita a mano (solo por movimientos).
--   * VEX y FTC no se mezclan (categoría y contenedores).
-- =====================================================================

create schema if not exists app;
comment on schema app is 'Funciones internas del inventario. No se exponen por la API.';

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.categoria_articulo as enum (
  'VEX', 'FTC', 'HERRAMIENTAS', 'HERRAMIENTAS_ELECTRICAS', 'CONSUMIBLES', 'COMUN', 'SIN_CLASIFICAR');
create type public.estado_inventario as enum (
  'SIN_CLASIFICAR', 'POR_CONTAR', 'POR_VERIFICAR', 'VERIFICADO', 'DESGLOSADO', 'DADO_DE_BAJA');
create type public.estado_fisico as enum (
  'NUEVO', 'USADO', 'INCOMPLETO', 'DAÑADO', 'SIN_ABRIR', 'VACIO');
create type public.tipo_etiquetado as enum ('INDIVIDUAL', 'CONTENEDOR', 'LOTE');
create type public.tipo_movimiento as enum (
  'PRESTAMO', 'DEVOLUCION', 'CONSUMO', 'PERDIDA', 'DAÑO', 'REPARACION', 'ALTA', 'BAJA', 'AJUSTE_CONTEO');
create type public.origen_movimiento as enum ('APP', 'IMPORTACION', 'SOLICITUD', 'INVENTARIO', 'SIN_CONEXION');
create type public.rol_usuario as enum ('DOCENTE', 'RESPONSABLE', 'SUBADMIN');
create type public.tipo_solicitante as enum ('ALUMNO', 'MAESTRO', 'OTRO');
create type public.estado_solicitud as enum (
  'PENDIENTE', 'APROBADA', 'RECHAZADA', 'ENTREGADO', 'DEVUELTA', 'VENCIDA', 'CANCELADA');
create type public.estado_codigo as enum ('VIGENTE', 'USADO', 'EXPIRADO', 'ANULADO', 'BLOQUEADO');
create type public.tipo_foto as enum (
  'GENERAL', 'PLACA_SERIE', 'ETIQUETA_RESGUARDO', 'DAÑO', 'ENTREGA', 'CONTEO');
create type public.tipo_incidencia as enum ('PERDIDA', 'DAÑO', 'CONSUMO');
create type public.estado_incidencia as enum ('PENDIENTE', 'CONFIRMADA', 'DESCARTADA');
create type public.tipo_tarea as enum (
  'CONTAR', 'VERIFICAR_DATO', 'ABRIR_REVISAR', 'REGISTRAR_SERIE', 'IDENTIFICAR_ETIQUETAR',
  'FALTA_PIEZA', 'DEFINIR_VEX_FTC', 'CONFIRMAR_VACIO', 'LOCALIZAR_CONTENIDO');
create type public.origen_tarea as enum ('IMPORTACION', 'SISTEMA', 'USUARIO');
create type public.estado_inventario_periodico as enum ('ABIERTO', 'CERRADO');
create type public.decision_conteo as enum ('AJUSTE', 'INCIDENCIA', 'RECONTAR');

-- ---------------------------------------------------------------------
-- Utilidades comunes
-- ---------------------------------------------------------------------

-- Número de orden de cambios. La app baja "todo lo posterior al número N"
-- al reconectar (F-17, regla 5); por eso se usa una secuencia y no la hora.
create sequence app.cambio_seq;

create function app.tocar() returns trigger
language plpgsql as $$
begin
  new.version := nextval('app.cambio_seq');
  if tg_op = 'UPDATE' then
    new.actualizado_en := now();
  end if;
  return new;
end $$;

create function app.versionar() returns trigger
language plpgsql as $$
begin
  new.version := nextval('app.cambio_seq');
  return new;
end $$;

create function app.prohibir_borrado() returns trigger
language plpgsql as $$
begin
  raise exception 'No se borran registros de %: se da de baja o se corrige con un movimiento', tg_table_name;
end $$;

create function app.prohibir_edicion() returns trigger
language plpgsql as $$
begin
  raise exception 'Los registros de % no se editan ni se borran', tg_table_name;
end $$;

-- ---------------------------------------------------------------------
-- Personas
-- ---------------------------------------------------------------------
create table public.usuario (
  id                    uuid primary key references auth.users (id),
  nombre                text not null check (btrim(nombre) <> ''),
  correo                text,
  rol                   public.rol_usuario not null,
  activo                boolean not null default true,
  pin_hash              text,
  pin_intentos_fallidos integer not null default 0,
  pin_bloqueado_hasta   timestamptz,
  creado_en             timestamptz not null default now(),
  actualizado_en        timestamptz not null default now(),
  version               bigint not null default 0
);
comment on table public.usuario is 'Personas con cuenta. Las cuentas las crea el responsable o sub administración.';

create table public.solicitante (
  id                 uuid primary key default gen_random_uuid(),
  nombre_completo    text not null check (btrim(nombre_completo) <> ''),
  tipo               public.tipo_solicitante not null,
  matricula_o_clave  text not null check (btrim(matricula_o_clave) <> ''),
  grupo_area         text,
  telefono           text,
  correo             text,
  bloqueado          boolean not null default false,
  bloqueo_manual     boolean not null default false,
  posible_duplicado  boolean not null default false,
  nota               text,
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now(),
  version            bigint not null default 0
);
comment on table public.solicitante is 'Personas sin cuenta que quedan a cargo de material (alumnos, maestros, otros).';
create unique index solicitante_matricula_unica
  on public.solicitante (tipo, lower(btrim(matricula_o_clave)))
  where not posible_duplicado;

-- ---------------------------------------------------------------------
-- Contenedores (ubicaciones con QR propio; pueden anidarse)
-- ---------------------------------------------------------------------
create sequence app.contenedor_codigo_seq;

create table public.contenedor (
  id                  uuid primary key default gen_random_uuid(),
  codigo              text not null unique
                        default ('C-' || lpad(nextval('app.contenedor_codigo_seq')::text, 4, '0')),
  nombre              text not null check (btrim(nombre) <> ''),
  tipo                text not null default 'CAJON'
                        check (tipo in ('GABINETE', 'CAJON', 'CANASTA', 'GAVETA', 'BOLSA', 'REPISA', 'CAJA', 'OTRO')),
  padre_id            uuid references public.contenedor (id),
  categoria_exclusiva public.categoria_articulo check (categoria_exclusiva in ('VEX', 'FTC')),
  foto_url            text,
  nota                text,
  activo              boolean not null default true,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now(),
  version             bigint not null default 0,
  check (padre_id is distinct from id)
);
comment on column public.contenedor.categoria_exclusiva is
  'Si es VEX o FTC, solo puede contener artículos de esa categoría. Piezas VEX/FTC solo viven en contenedores exclusivos.';

-- ---------------------------------------------------------------------
-- Artículos
-- ---------------------------------------------------------------------
-- Los importados usan A-<ref_foto>; los nuevos arrancan en A-1001.
create sequence app.articulo_codigo_seq start 1001;

create table public.articulo (
  id                  uuid primary key default gen_random_uuid(),
  codigo              text not null unique
                        default ('A-' || lpad(nextval('app.articulo_codigo_seq')::text, 4, '0')),
  ref_foto            integer unique,
  nombre              text not null check (btrim(nombre) <> ''),
  marca_modelo        text,
  categoria           public.categoria_articulo not null,
  subcategoria        text,
  cantidad            integer,
  cantidad_texto      text,
  cantidad_estimada   boolean not null default false,
  conteo_desconocido  boolean not null default false,
  unidad              text not null default 'pieza',
  estado_inventario   public.estado_inventario not null default 'POR_VERIFICAR',
  estado_fisico       public.estado_fisico,
  estado_fisico_texto text,
  etiquetado          public.tipo_etiquetado not null default 'CONTENEDOR',
  contenedor_id       uuid references public.contenedor (id),
  ubicacion           text,
  num_resguardo       text unique,
  num_serie           text unique,
  observaciones       text,
  es_consumible       boolean not null default false,
  minimo_reposicion   integer check (minimo_reposicion >= 0),
  activo              boolean not null default true,
  desglosado_de_id    uuid references public.articulo (id),
  datos_origen        jsonb,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now(),
  version             bigint not null default 0,
  check (activo = (estado_inventario not in ('DESGLOSADO', 'DADO_DE_BAJA'))),
  check (not activo or ((categoria = 'SIN_CLASIFICAR') = (estado_inventario = 'SIN_CLASIFICAR')))
);
comment on column public.articulo.cantidad is
  'Copia de la existencia calculada desde los movimientos. Solo la cambia el disparador de movimientos; si no cuadra, aparece en v_descuadres.';
comment on column public.articulo.ref_foto is 'Ref. original del levantamiento fotográfico (Excel).';
comment on column public.articulo.conteo_desconocido is
  'La cantidad del Excel no traía número ("varias"). No se presta hasta contarlo.';
comment on column public.articulo.ubicacion is 'Texto libre heredado del Excel. La ubicación formal es contenedor_id.';
comment on column public.articulo.datos_origen is 'Renglón original del Excel, para trazabilidad.';

create index articulo_categoria_idx on public.articulo (categoria) where activo;
create index articulo_contenedor_idx on public.articulo (contenedor_id);

-- ---------------------------------------------------------------------
-- Solicitudes de préstamo (personas sin cuenta)
-- ---------------------------------------------------------------------
create sequence app.solicitud_folio_seq;

create table public.solicitud (
  id                             uuid primary key default gen_random_uuid(),
  folio                          text not null unique
                                   default ('LM-' || lpad(nextval('app.solicitud_folio_seq')::text, 4, '0')),
  solicitante_id                 uuid not null references public.solicitante (id),
  estado                         public.estado_solicitud not null default 'PENDIENTE',
  motivo                         text not null check (btrim(motivo) <> ''),
  fecha_devolucion_comprometida  timestamptz not null,
  token_hash                     text,
  creada_en                      timestamptz not null default now(),
  autorizada_por                 uuid references public.usuario (id),
  autorizada_en                  timestamptz,
  recoger_hasta                  timestamptz,
  motivo_rechazo                 text,
  motivo_cancelacion             text,
  firma_url                      text,
  foto_entrega_url               text,
  entregada_en                   timestamptz,
  actualizado_en                 timestamptz not null default now(),
  version                        bigint not null default 0,
  check (estado <> 'RECHAZADA' or btrim(coalesce(motivo_rechazo, '')) <> ''),
  check (estado not in ('APROBADA', 'ENTREGADO', 'DEVUELTA', 'VENCIDA') or autorizada_por is not null)
);

create table public.solicitud_linea (
  id                 uuid primary key default gen_random_uuid(),
  solicitud_id       uuid not null references public.solicitud (id),
  articulo_id        uuid not null references public.articulo (id),
  cantidad           integer not null check (cantidad > 0),
  cantidad_aprobada  integer check (cantidad_aprobada >= 0 and cantidad_aprobada <= cantidad),
  unique (solicitud_id, articulo_id)
);

create table public.codigo_entrega (
  id                 uuid primary key default gen_random_uuid(),
  solicitud_id       uuid not null references public.solicitud (id),
  codigo_hash        text not null,
  generado_por       uuid not null references public.usuario (id),
  generado_en        timestamptz not null default now(),
  expira_en          timestamptz not null,
  estado             public.estado_codigo not null default 'VIGENTE',
  intentos_fallidos  integer not null default 0,
  usado_en           timestamptz,
  usado              boolean generated always as (estado = 'USADO') stored,
  check (expira_en > generado_en),
  check ((estado = 'USADO') = (usado_en is not null))
);
-- Solo un código vigente por solicitud.
create unique index codigo_entrega_un_vigente on public.codigo_entrega (solicitud_id) where estado = 'VIGENTE';

-- ---------------------------------------------------------------------
-- Inventario periódico
-- ---------------------------------------------------------------------
create table public.inventario_periodico (
  id             uuid primary key default gen_random_uuid(),
  alcance        jsonb not null default '{"todo": true}',
  estado         public.estado_inventario_periodico not null default 'ABIERTO',
  fecha_inicio   timestamptz not null default now(),
  abierto_por    uuid not null references public.usuario (id),
  fecha_cierre   timestamptz,
  cerrado_por    uuid references public.usuario (id),
  check ((estado = 'CERRADO') = (fecha_cierre is not null and cerrado_por is not null))
);
create unique index inventario_un_abierto on public.inventario_periodico ((true)) where estado = 'ABIERTO';

create table public.conteo_linea (
  id                uuid primary key default gen_random_uuid(),
  inventario_id     uuid not null references public.inventario_periodico (id),
  articulo_id       uuid not null references public.articulo (id),
  contenedor_id     uuid references public.contenedor (id),
  cantidad_sistema  integer not null,
  cantidad_fisica   integer not null check (cantidad_fisica >= 0),
  diferencia        integer generated always as (cantidad_fisica - cantidad_sistema) stored,
  nota              text,
  contado_por       uuid not null references public.usuario (id),
  contado_en        timestamptz not null default now(),
  decision          public.decision_conteo
);
comment on column public.conteo_linea.cantidad_sistema is
  'Lo que debía haber EN EL TALLER al momento de contar (sin lo prestado).';

-- ---------------------------------------------------------------------
-- Movimientos: el corazón. Solo se agregan.
-- ---------------------------------------------------------------------
create table public.movimiento (
  id                          uuid primary key default gen_random_uuid(),
  articulo_id                 uuid not null references public.articulo (id),
  tipo                        public.tipo_movimiento not null,
  cantidad                    integer not null,
  fecha                       timestamptz not null default now(),
  fecha_dispositivo           timestamptz,
  nota                        text,
  foto_url                    text,
  movimiento_origen_id        uuid references public.movimiento (id),
  autorizado_por              uuid references public.usuario (id),
  registrado_por              uuid references public.usuario (id),
  responsable_usuario_id      uuid references public.usuario (id),
  responsable_solicitante_id  uuid references public.solicitante (id),
  solicitud_id                uuid references public.solicitud (id),
  incidencia_id               uuid,  -- FK se agrega después de crear incidencia
  inventario_id               uuid references public.inventario_periodico (id),
  fecha_compromiso            timestamptz,
  de_fuera_de_servicio        boolean not null default false,
  origen                      public.origen_movimiento not null default 'APP',
  comando_id                  uuid unique,
  conflicto                   boolean not null default false,
  conflicto_motivo            text,
  version                     bigint not null default 0,

  -- Solo el ajuste lleva signo; todo lo demás es positivo.
  check ((tipo = 'AJUSTE_CONTEO' and cantidad <> 0) or (tipo <> 'AJUSTE_CONTEO' and cantidad > 0)),
  -- A lo más un responsable nominal...
  check (num_nonnulls(responsable_usuario_id, responsable_solicitante_id) <= 1),
  -- ...y exactamente uno cuando el material sale del taller (regla de negocio 5).
  check (tipo <> 'PRESTAMO' or num_nonnulls(responsable_usuario_id, responsable_solicitante_id) = 1),
  check (tipo <> 'DEVOLUCION' or movimiento_origen_id is not null),
  -- Todo movimiento lo autoriza alguien con cuenta, salvo la carga inicial del Excel.
  check (origen = 'IMPORTACION' or autorizado_por is not null),
  -- Justificación obligatoria en lo que reduce o corrige existencias.
  check (tipo not in ('PERDIDA', 'DAÑO', 'BAJA', 'AJUSTE_CONTEO') or btrim(coalesce(nota, '')) <> ''),
  check (not conflicto or btrim(coalesce(conflicto_motivo, '')) <> ''),
  check (not de_fuera_de_servicio or (tipo in ('BAJA', 'PERDIDA') and movimiento_origen_id is null))
);
comment on table public.movimiento is 'Bitácora de todo lo que le pasa a un artículo. Nunca se edita ni se borra.';
comment on column public.movimiento.autorizado_por is 'Usuario con cuenta que dio el visto bueno. NO es quien queda a cargo.';
comment on column public.movimiento.comando_id is 'Identificador generado en el dispositivo; evita duplicados al reintentar (F-17).';
comment on column public.movimiento.conflicto is 'Aceptado aunque rompía una regla, porque se capturó sin conexión y el material sí se movió (F-17).';

create index movimiento_articulo_idx on public.movimiento (articulo_id);
create index movimiento_origen_idx on public.movimiento (movimiento_origen_id);
create index movimiento_fecha_idx on public.movimiento (fecha);

-- ---------------------------------------------------------------------
-- Incidencias: pérdidas, daños y consumos que esperan confirmación
-- ---------------------------------------------------------------------
create table public.incidencia (
  id                          uuid primary key default gen_random_uuid(),
  articulo_id                 uuid not null references public.articulo (id),
  tipo                        public.tipo_incidencia not null,
  cantidad                    integer not null check (cantidad > 0),
  estado                      public.estado_incidencia not null default 'PENDIENTE',
  nota                        text not null check (btrim(nota) <> ''),
  sin_foto_justificacion      text,
  en_taller                   boolean not null,
  prestamo_id                 uuid references public.movimiento (id),
  responsable_usuario_id      uuid references public.usuario (id),
  responsable_solicitante_id  uuid references public.solicitante (id),
  reportada_por               uuid not null references public.usuario (id),
  reportada_en                timestamptz not null default now(),
  resuelta_por                uuid references public.usuario (id),
  resuelta_en                 timestamptz,
  motivo_resolucion           text,
  movimiento_id               uuid references public.movimiento (id),
  comando_id                  uuid unique,
  actualizado_en              timestamptz not null default now(),
  version                     bigint not null default 0,
  check (num_nonnulls(responsable_usuario_id, responsable_solicitante_id) <= 1),
  check (not en_taller or prestamo_id is null),
  check ((estado = 'PENDIENTE') = (resuelta_en is null)),
  check (estado <> 'DESCARTADA' or btrim(coalesce(motivo_resolucion, '')) <> '')
);
comment on column public.incidencia.en_taller is
  'Las unidades estaban en el taller: quedan retenidas (no se prestan) mientras la incidencia esté pendiente.';

alter table public.movimiento
  add constraint movimiento_incidencia_fk foreign key (incidencia_id) references public.incidencia (id);

-- ---------------------------------------------------------------------
-- Fotos: se acumulan, no se reemplazan
-- ---------------------------------------------------------------------
create table public.foto (
  id             uuid primary key default gen_random_uuid(),
  articulo_id    uuid references public.articulo (id),
  contenedor_id  uuid references public.contenedor (id),
  url            text not null,
  es_principal   boolean not null default false,
  tipo           public.tipo_foto not null default 'GENERAL',
  tomada_por     uuid references public.usuario (id),
  tomada_en      timestamptz not null default now(),
  movimiento_id  uuid references public.movimiento (id),
  incidencia_id  uuid references public.incidencia (id),
  solicitud_id   uuid references public.solicitud (id),
  version        bigint not null default 0,
  check (num_nonnulls(articulo_id, contenedor_id, solicitud_id) >= 1),
  check (not es_principal or articulo_id is not null)
);
create unique index foto_una_principal on public.foto (articulo_id) where es_principal;

-- ---------------------------------------------------------------------
-- Pendientes (tareas por verificar)
-- ---------------------------------------------------------------------
create table public.tarea_pendiente (
  id               uuid primary key default gen_random_uuid(),
  articulo_id      uuid not null references public.articulo (id),
  tipo             public.tipo_tarea not null,
  descripcion      text not null,
  origen           public.origen_tarea not null default 'USUARIO',
  prioridad        smallint not null default 0 check (prioridad in (0, 1)),
  creada_en        timestamptz not null default now(),
  creada_por       uuid references public.usuario (id),
  resuelta         boolean not null default false,
  resuelta_por     uuid references public.usuario (id),
  resuelta_en      timestamptz,
  nota_resolucion  text,
  actualizado_en   timestamptz not null default now(),
  version          bigint not null default 0,
  check (resuelta = (resuelta_en is not null))
);
-- La importación no duplica pendientes aunque se corra varias veces.
create unique index tarea_importacion_unica on public.tarea_pendiente (articulo_id, tipo) where origen = 'IMPORTACION';

-- ---------------------------------------------------------------------
-- Comandos aplicados (idempotencia de la cola sin conexión, F-17)
-- ---------------------------------------------------------------------
create table public.comando_aplicado (
  id                 uuid primary key,
  usuario_id         uuid references public.usuario (id),
  tipo               text not null,
  fecha_dispositivo  timestamptz,
  recibido_en        timestamptz not null default now(),
  resultado          jsonb not null
);

-- ---------------------------------------------------------------------
-- Bitácora de cambios (ediciones de datos, accesos, códigos, exportaciones)
-- ---------------------------------------------------------------------
create table public.bitacora (
  id           bigint generated always as identity primary key,
  en           timestamptz not null default now(),
  usuario_id   uuid,
  evento       text not null,
  tabla        text,
  registro_id  text,
  datos        jsonb
);
create index bitacora_registro_idx on public.bitacora (tabla, registro_id);

-- ---------------------------------------------------------------------
-- Configuración (la cambia sub administración)
-- ---------------------------------------------------------------------
create table public.configuracion (
  clave        text primary key,
  valor        jsonb not null,
  descripcion  text not null
);

insert into public.configuracion (clave, valor, descripcion) values
  ('dias_vencimiento',                   '7',  'Días para marcar como vencido un préstamo sin fecha comprometida'),
  ('codigo_vigencia_minutos',            '90', 'Vigencia por defecto del código de entrega'),
  ('codigo_vigencia_max_horas',          '24', 'Vigencia máxima del código de entrega'),
  ('codigo_intentos_max',                '5',  'Intentos fallidos antes de bloquear un código'),
  ('solicitud_sin_respuesta_dias_habiles','3', 'Días hábiles para cancelar una solicitud sin respuesta'),
  ('aprobada_sin_recoger_dias_habiles',  '2',  'Días hábiles para cancelar una solicitud aprobada que no se recogió'),
  ('plazo_max_alumno_dias',              '14', 'Plazo máximo de préstamo para alumnos'),
  ('plazo_max_maestro_dias',             '30', 'Plazo máximo de préstamo para maestros'),
  ('pin_intentos_max',                   '5',  'Intentos fallidos de PIN antes de bloquear'),
  ('pin_bloqueo_minutos',                '15', 'Minutos de bloqueo tras fallar el PIN'),
  ('sesion_horas',                       '8',  'Duración de la sesión (jornada)');

create function app.config_int(p_clave text) returns integer
language sql stable security definer set search_path = public as $$
  select (valor #>> '{}')::integer from public.configuracion where clave = p_clave
$$;

-- ---------------------------------------------------------------------
-- Disparadores de versión, borrado y edición
-- ---------------------------------------------------------------------
create trigger tocar before insert or update on public.usuario             for each row execute function app.tocar();
create trigger tocar before insert or update on public.solicitante         for each row execute function app.tocar();
create trigger tocar before insert or update on public.contenedor          for each row execute function app.tocar();
create trigger tocar before insert or update on public.articulo            for each row execute function app.tocar();
create trigger tocar before insert or update on public.solicitud           for each row execute function app.tocar();
create trigger tocar before insert or update on public.incidencia          for each row execute function app.tocar();
create trigger tocar before insert or update on public.tarea_pendiente     for each row execute function app.tocar();
create trigger versionar before insert or update on public.foto            for each row execute function app.versionar();
create trigger versionar before insert on public.movimiento                for each row execute function app.versionar();

create trigger sin_borrado before delete on public.usuario              for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.solicitante          for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.contenedor           for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.articulo             for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.solicitud            for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.solicitud_linea      for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.codigo_entrega       for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.inventario_periodico for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.conteo_linea         for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.incidencia           for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.foto                 for each row execute function app.prohibir_borrado();
create trigger sin_borrado before delete on public.tarea_pendiente      for each row execute function app.prohibir_borrado();

create trigger solo_agregar before update or delete on public.movimiento       for each row execute function app.prohibir_edicion();
create trigger sin_truncar before truncate on public.movimiento               for each statement execute function app.prohibir_edicion();
create trigger solo_agregar before update or delete on public.bitacora         for each row execute function app.prohibir_edicion();
create trigger sin_truncar before truncate on public.bitacora                 for each statement execute function app.prohibir_edicion();
create trigger solo_agregar before update or delete on public.comando_aplicado for each row execute function app.prohibir_edicion();

-- ---------------------------------------------------------------------
-- La cantidad no se edita a mano
-- ---------------------------------------------------------------------
create function app.proteger_cantidad() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('app.cambio_cantidad', true), '') = 'si' then
    return new;
  end if;
  if tg_op = 'INSERT' and new.cantidad is not null then
    raise exception 'La cantidad de "%" no se captura directo: registra un movimiento de alta', new.nombre;
  end if;
  if tg_op = 'UPDATE' and new.cantidad is distinct from old.cantidad then
    raise exception 'La cantidad de "%" no se edita: registra un movimiento', new.nombre;
  end if;
  return new;
end $$;

create trigger proteger_cantidad before insert or update on public.articulo
  for each row execute function app.proteger_cantidad();

-- ---------------------------------------------------------------------
-- VEX y FTC no se mezclan
-- ---------------------------------------------------------------------
create function app.validar_categoria_articulo() returns trigger
language plpgsql as $$
declare
  c public.contenedor%rowtype;
begin
  if tg_op = 'UPDATE'
     and old.categoria in ('VEX', 'FTC') and new.categoria in ('VEX', 'FTC')
     and old.categoria <> new.categoria
     and btrim(coalesce(current_setting('app.justificacion', true), '')) = '' then
    raise exception 'VEX y FTC no se mezclan: pasar "%" de % a % requiere justificación',
      new.nombre, old.categoria, new.categoria;
  end if;

  if new.contenedor_id is not null
     and (tg_op = 'INSERT'
          or new.contenedor_id is distinct from old.contenedor_id
          or new.categoria is distinct from old.categoria) then
    select * into c from public.contenedor where id = new.contenedor_id;
    if new.categoria in ('VEX', 'FTC') and c.categoria_exclusiva is distinct from new.categoria then
      raise exception 'VEX y FTC no se mezclan: "%" es % y el contenedor % no es exclusivo de %',
        new.nombre, new.categoria, c.codigo, new.categoria;
    end if;
    if c.categoria_exclusiva is not null and c.categoria_exclusiva <> new.categoria then
      raise exception 'El contenedor % es solo para %; "%" es %',
        c.codigo, c.categoria_exclusiva, new.nombre, new.categoria;
    end if;
  end if;
  return new;
end $$;

create trigger validar_categoria before insert or update on public.articulo
  for each row execute function app.validar_categoria_articulo();

create function app.validar_contenedor() returns trigger
language plpgsql as $$
declare
  cat_padre public.categoria_articulo;
begin
  if new.padre_id is not null then
    if exists (
      with recursive arriba as (
        select id, padre_id from public.contenedor where id = new.padre_id
        union all
        select c.id, c.padre_id from public.contenedor c join arriba on c.id = arriba.padre_id
      )
      select 1 from arriba where id = new.id
    ) then
      raise exception 'El contenedor % no puede quedar dentro de sí mismo', new.codigo;
    end if;

    select categoria_exclusiva into cat_padre from public.contenedor where id = new.padre_id;
    if cat_padre is not null and new.categoria_exclusiva is distinct from cat_padre then
      raise exception 'El contenedor padre es solo para %; "%" también debe serlo', cat_padre, new.nombre;
    end if;
  end if;

  if tg_op = 'UPDATE' and new.categoria_exclusiva is distinct from old.categoria_exclusiva then
    if exists (select 1 from public.articulo a
               where a.contenedor_id = new.id and a.activo
                 and (a.categoria is distinct from new.categoria_exclusiva)
                 and (new.categoria_exclusiva is not null or a.categoria in ('VEX', 'FTC'))) then
      raise exception 'No se puede cambiar la categoría de %: tiene artículos que no corresponden', new.codigo;
    end if;
    if new.categoria_exclusiva is not null and exists (
        select 1 from public.contenedor h
        where h.padre_id = new.id and h.categoria_exclusiva is distinct from new.categoria_exclusiva) then
      raise exception 'No se puede cambiar la categoría de %: tiene contenedores internos de otra categoría', new.codigo;
    end if;
  end if;
  return new;
end $$;

create trigger validar_contenedor before insert or update on public.contenedor
  for each row execute function app.validar_contenedor();

-- ---------------------------------------------------------------------
-- Bitácora de ediciones de artículos y contenedores
-- ---------------------------------------------------------------------
create function app.registrar_edicion() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  nuevo    jsonb := to_jsonb(new);
  anterior jsonb := to_jsonb(old);
  cambios  jsonb := '{}';
  k        text;
begin
  for k in select jsonb_object_keys(nuevo) loop
    if k in ('version', 'actualizado_en', 'cantidad') then
      continue;
    end if;
    if (nuevo -> k) is distinct from (anterior -> k) then
      cambios := cambios || jsonb_build_object(k, jsonb_build_object('antes', anterior -> k, 'despues', nuevo -> k));
    end if;
  end loop;

  if cambios <> '{}' then
    insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
    values (auth.uid(), 'EDICION', tg_table_name, new.id::text,
            jsonb_build_object('cambios', cambios,
                               'justificacion', nullif(btrim(coalesce(current_setting('app.justificacion', true), '')), '')));
  end if;
  return new;
end $$;

create trigger bitacora after update on public.articulo   for each row execute function app.registrar_edicion();
create trigger bitacora after update on public.contenedor for each row execute function app.registrar_edicion();
