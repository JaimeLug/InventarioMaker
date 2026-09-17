-- =====================================================================
-- 0010 · Pendientes, conteos, desglose de kits, inventario periódico y "avisarme" (Fase 4b)
--
-- Flujos: F-15 resolución de pendientes, F-13 conteos (en lote), desglose de kits con plantillas de
-- contenido de fábrica, F-16 inventario periódico, y aviso por correo cuando un artículo vuelve a estar.
--
-- Decisiones de la Fase 4b (aprobadas el 2026-09-17):
--   * Cualquiera con cuenta cuenta (docentes incluidos); responsable o sub administración autoriza.
--     Los conteos se aplican en lote con UNA sola reconfirmación de contraseña.
--   * VERIFICADO significa lo mismo en todo el sistema: contado (sin ~), sin pendientes abiertos,
--     con foto principal y con ubicación.
--   * Un kit se desglosa por unidades. Las abiertas salen del kit ("Desglosado") o, si se abrieron
--     todas, el kit puede quedarse como empaque vacío.
--   * Las listas de contenido de fábrica son plantillas: precargan lo esperado y dejan el faltante.
--   * Inventario periódico por contenedor o por lista; lo no contado queda "no contado", nunca cero.
-- =====================================================================

insert into public.configuracion (clave, valor, descripcion) values
  ('aviso_disponible_dias',            '30', 'Días que dura un "avísame cuando regrese"'),
  ('avisos_disponible_por_hora',       '5',  '"Avísame cuando regrese" por hora desde un mismo dispositivo'),
  ('avisos_disponible_por_hora_red',   '30', '"Avísame cuando regrese" por hora desde una misma red')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------------
-- VERIFICADO: una sola regla
-- ---------------------------------------------------------------------
create function app.verificable(p_articulo uuid, p_ignorar_contar boolean default false) returns boolean
language sql stable security definer set search_path = '' as $$
  select a.activo and not a.cantidad_estimada and not a.conteo_desconocido
     and exists (select 1 from public.foto f where f.articulo_id = a.id and f.es_principal)
     and (a.contenedor_id is not null or btrim(coalesce(a.ubicacion, '')) <> '')
     and not exists (select 1 from public.tarea_pendiente t
                     where t.articulo_id = a.id and not t.resuelta and (not p_ignorar_contar or t.tipo <> 'CONTAR'))
  from public.articulo a where a.id = p_articulo
$$;

-- Estado después de un conteo (lo usan ajuste_conteo y la reactivación): el CONTAR que se está resolviendo no cuenta.
create or replace function app.estado_tras_conteo(p_articulo uuid) returns public.estado_inventario
language sql stable security definer set search_path = '' as $$
  select case
    when a.estado_inventario not in ('POR_CONTAR', 'POR_VERIFICAR') then a.estado_inventario
    when app.verificable(a.id, true) then 'VERIFICADO'
    else 'POR_VERIFICAR'
  end::public.estado_inventario
  from public.articulo a where a.id = p_articulo
$$;

-- Sube de estado cuando se cumple la regla (nunca baja). La llaman los disparadores de abajo.
create function app.revisar_verificado(p_articulo uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  a public.articulo;
begin
  select * into a from public.articulo where id = p_articulo;
  if not found or a.estado_inventario not in ('POR_CONTAR', 'POR_VERIFICAR') then
    return;
  end if;
  if app.verificable(p_articulo) then
    update public.articulo set estado_inventario = 'VERIFICADO' where id = p_articulo;
  elsif a.estado_inventario = 'POR_CONTAR' and not a.cantidad_estimada and not a.conteo_desconocido then
    update public.articulo set estado_inventario = 'POR_VERIFICAR' where id = p_articulo;
  end if;
end $$;

create function app.tras_cambio_verificable() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.articulo_id is not null then
    perform app.revisar_verificado(new.articulo_id);
  end if;
  return null;
end $$;

create function app.tras_cambio_articulo_verificable() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app.revisar_verificado(new.id);
  return null;
end $$;

create trigger verificable after insert or update of resuelta on public.tarea_pendiente
  for each row execute function app.tras_cambio_verificable();
create trigger verificable after insert or update of es_principal on public.foto
  for each row execute function app.tras_cambio_verificable();
create trigger verificable after update of contenedor_id, ubicacion, cantidad_estimada, conteo_desconocido on public.articulo
  for each row execute function app.tras_cambio_articulo_verificable();

-- ---------------------------------------------------------------------
-- F-15 Pendientes: aportes de docentes y resolución guiada
-- ---------------------------------------------------------------------
create table public.tarea_aporte (
  id        uuid primary key default gen_random_uuid(),
  tarea_id  uuid not null references public.tarea_pendiente (id),
  autor_id  uuid not null references public.usuario (id),
  nota      text not null check (btrim(nota) <> ''),
  foto_url  text check (foto_url !~* '^[a-z][a-z0-9+.-]*://'),
  en        timestamptz not null default now()
);
create index tarea_aporte_idx on public.tarea_aporte (tarea_id, en);

-- Un docente deja lo que vio ("abrí la caja, adentro hay…") y, si quiere, una foto del artículo.
create function public.pendiente_aportar(p_tarea uuid, p_nota text, p_foto text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
  t  public.tarea_pendiente;
begin
  select * into t from public.tarea_pendiente where id = p_tarea;
  if not found or t.resuelta then
    raise exception 'Ese pendiente ya no está abierto.';
  end if;
  if btrim(coalesce(p_nota, '')) = '' then
    raise exception 'Escribe lo que encontraste.';
  end if;
  if p_foto is not null then
    if p_foto not like 'articulos/' || t.articulo_id::text || '/%' or not app.archivo_existe('fotos', p_foto) then
      raise exception 'La foto no terminó de subirse. Intenta de nuevo.';
    end if;
    insert into public.foto (articulo_id, url, tipo, tomada_por, es_principal)
    values (t.articulo_id, p_foto, 'GENERAL', yo.id,
            not exists (select 1 from public.foto f where f.articulo_id = t.articulo_id and f.es_principal));
  end if;
  insert into public.tarea_aporte (tarea_id, autor_id, nota, foto_url) values (p_tarea, yo.id, btrim(p_nota), p_foto);
end $$;

create function public.pendiente_aportes(p_tarea uuid)
returns table (autor text, nota text, foto_url text, en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select app.nombre_usuario(x.autor_id), x.nota, x.foto_url, x.en
    from public.tarea_aporte x where x.tarea_id = p_tarea order by x.en;
end $$;

-- p_datos según el tipo:
--   todos:                 {"accion": "DESCARTAR", "motivo": "…"}  (ya no aplica)
--   VERIFICAR_DATO:        {"cambios": {…campos de articulo_editar…}, "nota": "…"}
--   REGISTRAR_SERIE:       {"num_serie": "…", "foto": "articulos/<id>/…", "nota": "…"}
--   IDENTIFICAR_ETIQUETAR: {"contenedor_id": "…", "etiquetado": "INDIVIDUAL|CONTENEDOR|LOTE", "nota": "…"}
--   FALTA_PIEZA:           {"resultado": "COMPLETO|INCOMPLETO|REPORTADO", "nota": "…"}
--   CONFIRMAR_VACIO:       {"vacio": true|false, "nota": "…"}
--   LOCALIZAR_CONTENIDO:   {"encontrado": true|false, "nota": "…"}
--   DEFINIR_VEX_FTC:       {"categoria": "VEX|FTC|HERRAMIENTAS|…", "nota": "…"}  (reconfirmar contraseña)
--   CONTAR y ABRIR_REVISAR se resuelven solos al aplicar un conteo o terminar un desglose.
create function public.pendiente_resolver(p_tarea uuid, p_datos jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  t         public.tarea_pendiente;
  a         public.articulo;
  d         jsonb := coalesce(p_datos, '{}'::jsonb);
  v_nota    text := nullif(btrim(coalesce(d ->> 'nota', '')), '');
  v_cat     public.categoria_articulo;
  v_etq     public.tipo_etiquetado;
  resumen   text;
begin
  select * into t from public.tarea_pendiente where id = p_tarea for update;
  if not found then
    raise exception 'El pendiente no existe.';
  end if;
  if t.resuelta then
    raise exception 'Ese pendiente ya se resolvió (por %).', coalesce(app.nombre_usuario(t.resuelta_por), 'el sistema');
  end if;
  select * into a from public.articulo where id = t.articulo_id for update;

  if d ->> 'accion' = 'DESCARTAR' then
    if length(btrim(coalesce(d ->> 'motivo', ''))) < 10 then
      raise exception 'Explica por qué ya no aplica (al menos 10 letras).';
    end if;
    resumen := 'Ya no aplica: ' || btrim(d ->> 'motivo');
  else
    case t.tipo
      when 'CONTAR' then
        raise exception 'Este pendiente se resuelve al aplicar un conteo (Conteos).';
      when 'ABRIR_REVISAR' then
        raise exception 'Este pendiente se resuelve al terminar el desglose del artículo.';

      when 'VERIFICAR_DATO' then
        if jsonb_typeof(d -> 'cambios') = 'object' and d -> 'cambios' <> '{}'::jsonb then
          perform public.articulo_editar(a.id, d -> 'cambios', v_nota);
          resumen := 'Dato corregido' || coalesce(': ' || v_nota, '');
        else
          resumen := 'Dato verificado, es correcto' || coalesce(': ' || v_nota, '');
        end if;

      when 'REGISTRAR_SERIE' then
        if btrim(coalesce(d ->> 'num_serie', '')) = '' then
          raise exception 'Escribe el número de serie o la medida.';
        end if;
        begin
          update public.articulo set num_serie = btrim(d ->> 'num_serie') where id = a.id;
        exception when unique_violation then
          raise exception 'Ese número de serie ya está registrado en otro artículo.';
        end;
        if d ->> 'foto' is not null then
          if d ->> 'foto' not like 'articulos/' || a.id::text || '/%' or not app.archivo_existe('fotos', d ->> 'foto') then
            raise exception 'La foto de la placa no terminó de subirse. Intenta de nuevo.';
          end if;
          insert into public.foto (articulo_id, url, tipo, tomada_por, es_principal)
          values (a.id, d ->> 'foto', 'PLACA_SERIE', yo.id,
                  not exists (select 1 from public.foto f where f.articulo_id = a.id and f.es_principal));
        end if;
        resumen := 'Serie: ' || btrim(d ->> 'num_serie');

      when 'IDENTIFICAR_ETIQUETAR' then
        if d ->> 'contenedor_id' is null and d ->> 'etiquetado' is null then
          raise exception 'Elige dónde vive o cómo se etiqueta.';
        end if;
        if d ->> 'contenedor_id' is not null then
          perform app.mover_articulo(yo.id, a.id, (d ->> 'contenedor_id')::uuid, 'PENDIENTE');
        end if;
        if d ->> 'etiquetado' is not null then
          v_etq := (d ->> 'etiquetado')::public.tipo_etiquetado;
          update public.articulo set etiquetado = v_etq where id = a.id;
        end if;
        resumen := concat_ws(' · ', case when d ->> 'contenedor_id' is not null then 'Ubicado en ' || app.ruta_contenedor((d ->> 'contenedor_id')::uuid) end,
                             case when v_etq is not null then 'Etiquetado ' || lower(v_etq::text) end, v_nota);

      when 'FALTA_PIEZA' then
        if coalesce(d ->> 'resultado', '') not in ('COMPLETO', 'INCOMPLETO', 'REPORTADO') then
          raise exception 'Elige si se completó, queda incompleto o se levantó un reporte.';
        end if;
        if v_nota is null then
          raise exception 'Escribe qué se encontró.';
        end if;
        if d ->> 'resultado' = 'INCOMPLETO' then
          update public.articulo set estado_fisico = 'INCOMPLETO' where id = a.id;
        end if;
        resumen := case d ->> 'resultado' when 'COMPLETO' then 'Se completó' when 'INCOMPLETO' then 'Queda incompleto'
                   else 'Se levantó reporte de pérdida' end || ': ' || v_nota;

      when 'CONFIRMAR_VACIO' then
        if d -> 'vacio' is null then
          raise exception 'Indica si está vacío.';
        end if;
        if (d ->> 'vacio')::boolean then
          update public.articulo set estado_fisico = 'VACIO' where id = a.id;
          if not exists (select 1 from public.tarea_pendiente x where x.articulo_id = a.id and x.tipo = 'LOCALIZAR_CONTENIDO' and not x.resuelta) then
            insert into public.tarea_pendiente (articulo_id, tipo, descripcion, origen, prioridad, creada_por)
            values (a.id, 'LOCALIZAR_CONTENIDO', 'Está vacío: localizar su contenido o darlo por faltante', 'SISTEMA', 1, yo.id);
          end if;
          resumen := 'Confirmado vacío' || coalesce(': ' || v_nota, '');
        else
          if v_nota is null then
            raise exception 'Escribe qué contiene.';
          end if;
          resumen := 'Tiene contenido: ' || v_nota;
        end if;

      when 'LOCALIZAR_CONTENIDO' then
        if d -> 'encontrado' is null or v_nota is null then
          raise exception 'Indica si apareció y escribe dónde o qué se hizo.';
        end if;
        resumen := case when (d ->> 'encontrado')::boolean then 'Contenido localizado: ' else 'Contenido no localizado: ' end || v_nota;

      when 'DEFINIR_VEX_FTC' then
        begin
          v_cat := (d ->> 'categoria')::public.categoria_articulo;
        exception when others then
          raise exception 'Elige la categoría.';
        end;
        if v_cat is null or v_cat = 'SIN_CLASIFICAR' then
          raise exception 'Elige la categoría.';
        end if;
        perform app.exigir_confirmacion();
        -- Si el contenedor actual no la admite, el artículo se queda sin ubicación.
        if a.contenedor_id is not null and exists (
             select 1 from public.contenedor c where c.id = a.contenedor_id
               and ((v_cat in ('VEX', 'FTC') and c.categoria_exclusiva is distinct from v_cat)
                    or (c.categoria_exclusiva is not null and c.categoria_exclusiva <> v_cat))) then
          perform app.mover_articulo(yo.id, a.id, null, 'PENDIENTE');
        end if;
        if a.categoria in ('VEX', 'FTC') and v_cat in ('VEX', 'FTC') and a.categoria <> v_cat then
          perform set_config('app.justificacion', coalesce(v_nota, 'Definido en pendientes'), true);
        end if;
        update public.articulo
           set categoria = v_cat, es_consumible = (v_cat = 'CONSUMIBLES') or es_consumible,
               estado_inventario = case when estado_inventario = 'SIN_CLASIFICAR'
                                        then case when conteo_desconocido or cantidad_estimada then 'POR_CONTAR' else 'POR_VERIFICAR' end::public.estado_inventario
                                        else estado_inventario end
         where id = a.id;
        resumen := 'Categoría: ' || v_cat || coalesce(' · ' || v_nota, '');

      else
        raise exception 'Tipo de pendiente desconocido.';
    end case;
  end if;

  update public.tarea_pendiente
     set resuelta = true, resuelta_por = yo.id, resuelta_en = now(), nota_resolucion = left(resumen, 1000)
   where id = p_tarea;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'PENDIENTE_RESUELTO', 'articulo', a.id::text, jsonb_build_object('tipo', t.tipo, 'resumen', resumen));
end $$;

-- ---------------------------------------------------------------------
-- F-13 Conteos: cualquiera cuenta, administración aplica en lote
-- ---------------------------------------------------------------------
create table public.conteo_propuesto (
  id              uuid primary key default gen_random_uuid(),
  articulo_id     uuid not null references public.articulo (id),
  en_taller       integer not null check (en_taller >= 0),
  sistema         integer not null,
  nota            text,
  contado_por     uuid not null references public.usuario (id),
  contado_en      timestamptz not null default now(),
  estado          text not null default 'PENDIENTE' check (estado in ('PENDIENTE', 'APLICADO', 'DESCARTADO')),
  resuelto_por    uuid references public.usuario (id),
  resuelto_en     timestamptz,
  motivo          text,
  movimiento_id   uuid references public.movimiento (id),
  check ((estado = 'PENDIENTE') = (resuelto_en is null))
);
comment on column public.conteo_propuesto.sistema is 'Lo que el sistema decía que había EN EL TALLER al momento de contar.';
create index conteo_propuesto_pendiente_idx on public.conteo_propuesto (contado_en) where estado = 'PENDIENTE';

create function public.conteo_proponer(p_articulo uuid, p_en_taller integer, p_nota text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('SESION');
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

create function public.conteos_por_aplicar()
returns table (id uuid, articulo_id uuid, codigo text, nombre text, unidad text, estimada boolean, en_taller integer,
               sistema integer, diferencia integer, nota text, contado_por text, contado_en timestamptz, mio boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  return query
    select c.id, a.id, a.codigo, a.nombre, a.unidad, a.cantidad_estimada or a.conteo_desconocido, c.en_taller, c.sistema,
           c.en_taller - c.sistema, c.nota, app.nombre_usuario(c.contado_por), c.contado_en, c.contado_por = yo.id
    from public.conteo_propuesto c join public.articulo a on a.id = c.articulo_id
    where c.estado = 'PENDIENTE' and (yo.rol <> 'DOCENTE' or c.contado_por = yo.id)
    order by a.nombre, c.contado_en;
end $$;

-- p_notas: {"<id del conteo>": "explicación"} para las diferencias que no traen nota.
create function public.conteos_aplicar(p_ids uuid[], p_notas jsonb default '{}') returns jsonb
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

create function public.conteos_descartar(p_ids uuid[], p_motivo text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  n  integer;
begin
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Escribe por qué se descarta.';
  end if;
  update public.conteo_propuesto set estado = 'DESCARTADO', resuelto_por = yo.id, resuelto_en = now(), motivo = btrim(p_motivo)
   where id = any (p_ids) and estado = 'PENDIENTE';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Plantillas de kit (contenido de fábrica) y desglose
-- ---------------------------------------------------------------------
create table public.plantilla_kit (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null unique,
  sku        text,
  categoria  public.categoria_articulo not null,
  fuente     text,
  nota       text,
  activa     boolean not null default true,
  creada_en  timestamptz not null default now()
);

create table public.plantilla_kit_linea (
  id            uuid primary key default gen_random_uuid(),
  plantilla_id  uuid not null references public.plantilla_kit (id),
  orden         integer not null,
  seccion       text,
  sku           text,
  descripcion   text not null,
  cantidad      integer check (cantidad is null or cantidad >= 0),
  unidad        text not null default 'pieza',
  nota          text,
  unique (plantilla_id, orden)
);
comment on column public.plantilla_kit_linea.cantidad is 'Por unidad de kit. Null = "varios": se cuenta al abrir.';

alter table public.articulo add column desglosado_de uuid references public.articulo (id);
comment on column public.articulo.desglosado_de is 'Kit del que salió este artículo al desglosarlo.';

create table public.desglose (
  id             uuid primary key default gen_random_uuid(),
  articulo_id    uuid not null references public.articulo (id),
  unidades       integer not null check (unidades > 0),
  plantilla_id   uuid references public.plantilla_kit (id),
  estado         text not null default 'BORRADOR' check (estado in ('BORRADOR', 'TERMINADO', 'CANCELADO')),
  destino        text check (destino in ('DESGLOSADO', 'EMPAQUE')),
  nota           text,
  creado_por     uuid not null references public.usuario (id),
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  terminado_por  uuid references public.usuario (id),
  terminado_en   timestamptz,
  check ((estado = 'TERMINADO') = (destino is not null and terminado_en is not null))
);
create unique index desglose_un_borrador on public.desglose (articulo_id) where estado = 'BORRADOR';

-- Renglones del borrador: se reescriben mientras se captura; al terminar quedan fijos.
create table public.desglose_linea (
  id                   uuid primary key default gen_random_uuid(),
  desglose_id          uuid not null references public.desglose (id),
  orden                integer not null,
  plantilla_linea_id   uuid references public.plantilla_kit_linea (id),
  seccion              text,
  sku                  text,
  descripcion          text not null,
  esperada             integer check (esperada is null or esperada >= 0),
  encontrada           integer check (encontrada is null or encontrada >= 0),
  articulo_destino_id  uuid references public.articulo (id),
  unidad               text not null default 'pieza',
  es_consumible        boolean not null default false,
  nota                 text,
  articulo_creado_id   uuid references public.articulo (id)
);
create index desglose_linea_idx on public.desglose_linea (desglose_id, orden);

create function app.desglose_linea_fija() returns trigger
language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from public.desglose d where d.id = coalesce(old.desglose_id, new.desglose_id) and d.estado <> 'BORRADOR')
     and current_setting('app.terminando_desglose', true) is distinct from 'si' then
    raise exception 'Un desglose terminado o cancelado ya no se modifica.';
  end if;
  return coalesce(new, old);
end $$;
create trigger fija before insert or update or delete on public.desglose_linea for each row execute function app.desglose_linea_fija();

create function app.desglose_json(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', d.id, 'estado', d.estado, 'unidades', d.unidades, 'destino', d.destino, 'nota', d.nota,
    'creado_por', app.nombre_usuario(d.creado_por), 'creado_en', d.creado_en,
    'terminado_por', app.nombre_usuario(d.terminado_por), 'terminado_en', d.terminado_en,
    'plantilla', (select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'sku', p.sku) from public.plantilla_kit p where p.id = d.plantilla_id),
    'articulo', (select jsonb_build_object('id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'categoria', a.categoria,
                                           'unidad', a.unidad, 'existencia', e.existencia, 'en_taller', e.en_taller)
                 from public.articulo a join public.v_existencias e on e.articulo_id = a.id where a.id = d.articulo_id),
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', l.id, 'orden', l.orden, 'plantilla_linea_id', l.plantilla_linea_id, 'seccion', l.seccion, 'sku', l.sku,
                 'descripcion', l.descripcion, 'esperada', l.esperada, 'encontrada', l.encontrada,
                 'articulo_destino_id', l.articulo_destino_id,
                 'articulo_destino', (select x.codigo || ' ' || x.nombre from public.articulo x where x.id = l.articulo_destino_id),
                 'unidad', l.unidad, 'es_consumible', l.es_consumible, 'nota', l.nota,
                 'articulo_creado', (select x.codigo from public.articulo x where x.id = l.articulo_creado_id))
               order by l.orden), '[]'::jsonb) from public.desglose_linea l where l.desglose_id = d.id))
  from public.desglose d where d.id = p_id
$$;

-- Abre (o retoma) el borrador del desglose de un kit.
create function public.desglose_iniciar(p_articulo uuid, p_unidades integer, p_plantilla uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo     public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  a      public.articulo;
  e      record;
  p      public.plantilla_kit;
  v_id   uuid;
begin
  select id into v_id from public.desglose where articulo_id = p_articulo and estado = 'BORRADOR';
  if v_id is not null then
    return app.desglose_json(v_id);
  end if;
  select * into a from public.articulo where id = p_articulo;
  if not found or not a.activo then
    raise exception 'El artículo no existe o está dado de baja.';
  end if;
  select * into e from public.v_existencias where articulo_id = p_articulo;
  if p_unidades is null or p_unidades < 1 or p_unidades > greatest(e.en_taller, 1) then
    raise exception 'Se pueden abrir de 1 a % unidades (las que están en el taller).', greatest(e.en_taller, 1);
  end if;
  if p_plantilla is not null then
    select * into p from public.plantilla_kit where id = p_plantilla and activa;
    if not found then
      raise exception 'La lista de contenido no existe.';
    end if;
    if a.categoria in ('VEX', 'FTC') and p.categoria <> a.categoria then
      raise exception 'La lista "%" es de %; el kit es %.', p.nombre, p.categoria, a.categoria;
    end if;
  end if;
  insert into public.desglose (articulo_id, unidades, plantilla_id, creado_por)
  values (p_articulo, p_unidades, p_plantilla, yo.id) returning id into v_id;
  insert into public.desglose_linea (desglose_id, orden, plantilla_linea_id, seccion, sku, descripcion, esperada, unidad, nota)
  select v_id, l.orden, l.id, l.seccion, l.sku, l.descripcion, l.cantidad * p_unidades, l.unidad, null
  from public.plantilla_kit_linea l where l.plantilla_id = p_plantilla;
  return app.desglose_json(v_id);
end $$;

-- Guarda el borrador tal como está en pantalla (reemplaza los renglones).
create function public.desglose_guardar(p_id uuid, p_unidades integer, p_lineas jsonb, p_nota text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  d   public.desglose;
  e   record;
  l   jsonb;
  i   integer := 0;
begin
  select * into d from public.desglose where id = p_id for update;
  if not found or d.estado <> 'BORRADOR' then
    raise exception 'Ese desglose ya no está en borrador.';
  end if;
  select * into e from public.v_existencias where articulo_id = d.articulo_id;
  if p_unidades is null or p_unidades < 1 or p_unidades > greatest(e.en_taller, 1) then
    raise exception 'Se pueden abrir de 1 a % unidades.', greatest(e.en_taller, 1);
  end if;
  if jsonb_typeof(coalesce(p_lineas, '[]'::jsonb)) <> 'array' then
    raise exception 'Renglones inválidos.';
  end if;
  delete from public.desglose_linea where desglose_id = p_id;
  for l in select * from jsonb_array_elements(coalesce(p_lineas, '[]'::jsonb)) loop
    i := i + 1;
    if btrim(coalesce(l ->> 'descripcion', '')) = '' then
      raise exception 'El renglón % no tiene descripción.', i;
    end if;
    insert into public.desglose_linea (desglose_id, orden, plantilla_linea_id, seccion, sku, descripcion, esperada, encontrada,
                                       articulo_destino_id, unidad, es_consumible, nota)
    values (p_id, i, (l ->> 'plantilla_linea_id')::uuid, nullif(btrim(l ->> 'seccion'), ''), nullif(btrim(l ->> 'sku'), ''),
            btrim(l ->> 'descripcion'), (l ->> 'esperada')::integer, (l ->> 'encontrada')::integer,
            (l ->> 'articulo_destino_id')::uuid, coalesce(nullif(btrim(l ->> 'unidad'), ''), 'pieza'),
            coalesce((l ->> 'es_consumible')::boolean, false), nullif(btrim(l ->> 'nota'), ''));
  end loop;
  update public.desglose set unidades = p_unidades, nota = nullif(btrim(p_nota), ''), actualizado_en = now() where id = p_id;
  return app.desglose_json(p_id);
end $$;

create function public.desglose_detalle(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return app.desglose_json(p_id);
end $$;

create function public.desgloses_de_articulo(p_articulo uuid)
returns table (id uuid, estado text, unidades integer, destino text, plantilla text, creado_en timestamptz, terminado_en timestamptz,
               renglones integer, faltantes integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select d.id, d.estado, d.unidades, d.destino, p.nombre, d.creado_en, d.terminado_en,
           (select count(*)::integer from public.desglose_linea l where l.desglose_id = d.id),
           (select count(*)::integer from public.desglose_linea l
             where l.desglose_id = d.id and l.esperada is not null and coalesce(l.encontrada, 0) < l.esperada)
    from public.desglose d left join public.plantilla_kit p on p.id = d.plantilla_id
    where d.articulo_id = p_articulo
    order by d.creado_en desc;
end $$;

-- Terminar: crea o suma las piezas y saca del kit las unidades abiertas (o lo deja como empaque).
create function public.desglose_terminar(p_id uuid, p_destino text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo        public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  d         public.desglose;
  k         public.articulo;
  e         record;
  l         record;
  destino   public.articulo;
  nuevo     uuid;
  creados   integer := 0;
  sumados   integer := 0;
  faltantes integer := 0;
  c         public.contenedor;
begin
  select * into d from public.desglose where id = p_id for update;
  if not found or d.estado <> 'BORRADOR' then
    raise exception 'Ese desglose ya no está en borrador.';
  end if;
  if p_destino is null or p_destino not in ('DESGLOSADO', 'EMPAQUE') then
    raise exception 'Elige qué pasa con el kit.';
  end if;
  select * into k from public.articulo where id = d.articulo_id for update;
  select * into e from public.v_existencias where articulo_id = k.id;
  if p_destino = 'EMPAQUE' and d.unidades < e.existencia then
    raise exception 'Solo se deja como empaque si se abrieron todas las unidades (% de %).', d.unidades, e.existencia;
  end if;
  if not exists (select 1 from public.desglose_linea x where x.desglose_id = p_id and coalesce(x.encontrada, 0) > 0) then
    raise exception 'No capturaste nada encontrado. Si el kit estaba vacío, resuelve el pendiente como "vacío".';
  end if;
  -- Revisiones antes de gastar la reconfirmación.
  for l in select * from public.desglose_linea x where x.desglose_id = p_id and coalesce(x.encontrada, 0) > 0 loop
    if l.articulo_destino_id is not null then
      select * into destino from public.articulo where id = l.articulo_destino_id;
      if not destino.activo then
        raise exception '"%" está dado de baja: elige otro o créalo nuevo.', destino.nombre;
      end if;
      if destino.categoria <> k.categoria then
        raise exception '"%" es % y el kit es %: las piezas se suman a artículos de la misma categoría.',
          destino.nombre, destino.categoria, k.categoria;
      end if;
    end if;
  end loop;
  perform app.exigir_confirmacion();

  if k.contenedor_id is not null then
    select * into c from public.contenedor where id = k.contenedor_id;
  end if;

  perform set_config('app.terminando_desglose', 'si', true);
  for l in select * from public.desglose_linea x where x.desglose_id = p_id order by x.orden loop
    if l.esperada is not null and coalesce(l.encontrada, 0) < l.esperada then
      faltantes := faltantes + 1;
    end if;
    continue when coalesce(l.encontrada, 0) = 0;
    if l.articulo_destino_id is not null then
      nuevo := l.articulo_destino_id;
      sumados := sumados + 1;
    else
      insert into public.articulo (nombre, marca_modelo, categoria, subcategoria, unidad, es_consumible, etiquetado,
                                   estado_inventario, estado_fisico, contenedor_id, desglosado_de, observaciones)
      values (l.descripcion, l.sku, k.categoria, k.subcategoria, l.unidad, l.es_consumible,
              case when l.es_consumible then 'LOTE' else 'CONTENEDOR' end::public.tipo_etiquetado,
              'POR_VERIFICAR', 'NUEVO',
              case when c.id is not null and (c.categoria_exclusiva is not distinct from k.categoria
                                              or (c.categoria_exclusiva is null and k.categoria not in ('VEX', 'FTC'))) then c.id end,
              k.id, concat_ws(' · ', 'Salió del kit ' || k.codigo, l.nota))
      returning id into nuevo;
      update public.desglose_linea set articulo_creado_id = nuevo where id = l.id;
      creados := creados + 1;
    end if;
    insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
    values (nuevo, 'ALTA', l.encontrada, format('Desglose de %s %s', k.codigo, k.nombre), yo.id, yo.id, 'APP');
  end loop;

  if p_destino = 'DESGLOSADO' then
    insert into public.movimiento (articulo_id, tipo, cantidad, nota, autorizado_por, registrado_por, origen)
    values (k.id, 'BAJA', d.unidades,
            format('Desglosado: %s pieza(s) nuevas, %s sumadas a existentes, %s renglón(es) con faltante', creados, sumados, faltantes),
            yo.id, yo.id, 'APP');
    if d.unidades >= e.existencia then
      update public.articulo set activo = false, estado_inventario = 'DESGLOSADO' where id = k.id;
    end if;
  else
    update public.articulo
       set estado_fisico = 'VACIO',
           observaciones = concat_ws(' · ', observaciones, 'Empaque vacío: contenido desglosado el ' || app.fecha_local(now()))
     where id = k.id;
  end if;
  if p_destino = 'EMPAQUE' or d.unidades >= e.existencia then
    update public.tarea_pendiente
       set resuelta = true, resuelta_por = yo.id, resuelta_en = now(),
           nota_resolucion = format('Desglosado: %s nuevas, %s sumadas, %s con faltante', creados, sumados, faltantes)
     where articulo_id = k.id and tipo in ('ABRIR_REVISAR', 'LOCALIZAR_CONTENIDO') and not resuelta;
  end if;

  update public.desglose set estado = 'TERMINADO', destino = p_destino, terminado_por = yo.id, terminado_en = now() where id = p_id;
  perform set_config('app.terminando_desglose', 'no', true);
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'DESGLOSE', 'articulo', k.id::text,
          jsonb_build_object('unidades', d.unidades, 'destino', p_destino, 'creados', creados, 'sumados', sumados, 'faltantes', faltantes));
  return jsonb_build_object('creados', creados, 'sumados', sumados, 'faltantes', faltantes);
end $$;

create function public.desglose_cancelar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
begin
  update public.desglose set estado = 'CANCELADO', actualizado_en = now() where id = p_id and estado = 'BORRADOR';
  if not found then
    raise exception 'Ese desglose ya no está en borrador.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- F-16 Inventario periódico
-- ---------------------------------------------------------------------
alter table public.inventario_periodico
  add column nombre text,
  add column nota   text;

alter table public.conteo_linea
  add column anulado boolean not null default false;
comment on column public.conteo_linea.anulado is 'Se mandó a recontar: ya no cuenta para la diferencia.';
create index conteo_linea_articulo_idx on public.conteo_linea (inventario_id, articulo_id) where not anulado;

create table public.inventario_decision (
  inventario_id  uuid not null references public.inventario_periodico (id),
  articulo_id    uuid not null references public.articulo (id),
  decision       text check (decision in ('AJUSTE', 'INCIDENCIA')),
  nota           text,
  decidido_por   uuid references public.usuario (id),
  decidido_en    timestamptz,
  incidencia_id  uuid references public.incidencia (id),
  movimiento_id  uuid references public.movimiento (id),
  primary key (inventario_id, articulo_id)
);

create table public.inventario_hallazgo (
  id             uuid primary key default gen_random_uuid(),
  inventario_id  uuid not null references public.inventario_periodico (id),
  contenedor_id  uuid references public.contenedor (id),
  articulo_id    uuid references public.articulo (id),
  descripcion    text not null check (btrim(descripcion) <> ''),
  cantidad       integer check (cantidad is null or cantidad > 0),
  foto_url       text check (foto_url !~* '^[a-z][a-z0-9+.-]*://'),
  reportado_por  uuid not null references public.usuario (id),
  reportado_en   timestamptz not null default now(),
  decision       text check (decision in ('MOVIDO', 'ALTA', 'IGNORADO')),
  nota           text,
  resuelto_por   uuid references public.usuario (id),
  resuelto_en    timestamptz
);

-- Artículos dentro del alcance: {"todo": true} | {"categorias": [...]} | {"contenedores": [ids]} (con lo que tengan adentro).
create function app.inventario_alcance(p_inventario uuid) returns table (articulo_id uuid)
language sql stable security definer set search_path = '' as $$
  with inv as (select alcance from public.inventario_periodico where id = p_inventario)
  select a.id from public.articulo a, inv
  where a.activo and (
    coalesce((inv.alcance ->> 'todo')::boolean, false)
    or a.categoria::text in (select jsonb_array_elements_text(coalesce(inv.alcance -> 'categorias', '[]'::jsonb)))
    or a.contenedor_id in (
      with recursive abajo as (
        select c.id from public.contenedor c
        where c.id::text in (select jsonb_array_elements_text(coalesce(inv.alcance -> 'contenedores', '[]'::jsonb)))
        union
        select h.id from public.contenedor h join abajo on h.padre_id = abajo.id
      )
      select id from abajo))
$$;

create function public.inventario_abrir(p_nombre text, p_alcance jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  nuevo uuid;
  n     integer;
begin
  if length(btrim(coalesce(p_nombre, ''))) < 3 then
    raise exception 'Ponle un nombre al inventario (ej. Inventario de fin de semestre).';
  end if;
  if jsonb_typeof(p_alcance) <> 'object' then
    raise exception 'Elige el alcance.';
  end if;
  begin
    insert into public.inventario_periodico (nombre, alcance, abierto_por) values (btrim(p_nombre), p_alcance, yo.id)
    returning id into nuevo;
  exception when unique_violation then
    raise exception 'Ya hay un inventario abierto: ciérralo antes de abrir otro.';
  end;
  select count(*) into n from app.inventario_alcance(nuevo);
  if n = 0 then
    raise exception 'El alcance elegido no tiene artículos.';
  end if;
  insert into public.bitacora (usuario_id, evento, tabla, registro_id, datos)
  values (yo.id, 'INVENTARIO_ABIERTO', 'inventario_periodico', nuevo::text, jsonb_build_object('nombre', btrim(p_nombre), 'alcance', p_alcance, 'articulos', n));
  return nuevo;
end $$;

create function public.inventarios_listar()
returns table (id uuid, nombre text, estado text, fecha_inicio timestamptz, fecha_cierre timestamptz, abrio text, cerro text,
               articulos integer, contados integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select i.id, coalesce(i.nombre, 'Inventario'), i.estado::text, i.fecha_inicio, i.fecha_cierre,
           app.nombre_usuario(i.abierto_por), app.nombre_usuario(i.cerrado_por),
           (select count(*)::integer from app.inventario_alcance(i.id)),
           (select count(distinct l.articulo_id)::integer from public.conteo_linea l where l.inventario_id = i.id and not l.anulado)
    from public.inventario_periodico i
    order by i.estado = 'ABIERTO' desc, i.fecha_inicio desc
    limit 50;
end $$;

create function public.inventario_articulos(p_inventario uuid)
returns table (articulo_id uuid, codigo text, nombre text, unidad text, categoria text, subcategoria text, contenedor_id uuid,
               contenedor_codigo text, ruta text, en_taller integer, mi_conteo integer, conteos integer, decidido boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('SESION');
begin
  return query
    select a.id, a.codigo, a.nombre, a.unidad, a.categoria::text, a.subcategoria, a.contenedor_id, c.codigo,
           app.ruta_contenedor(a.contenedor_id), e.en_taller,
           (select l.cantidad_fisica from public.conteo_linea l
             where l.inventario_id = p_inventario and l.articulo_id = a.id and l.contado_por = yo.id and not l.anulado
             order by l.contado_en desc limit 1),
           (select count(*)::integer from public.conteo_linea l where l.inventario_id = p_inventario and l.articulo_id = a.id and not l.anulado),
           exists (select 1 from public.inventario_decision x where x.inventario_id = p_inventario and x.articulo_id = a.id and x.decision is not null)
    from app.inventario_alcance(p_inventario) al
    join public.articulo a on a.id = al.articulo_id
    join public.v_existencias e on e.articulo_id = a.id
    left join public.contenedor c on c.id = a.contenedor_id
    order by app.ruta_contenedor(a.contenedor_id) nulls last, a.nombre;
end $$;

create function public.inventario_contar(p_inventario uuid, p_articulo uuid, p_cantidad integer, p_contenedor uuid default null,
                                         p_nota text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo  public.usuario := app.exigir('SESION');
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

create function public.inventario_hallazgo_registrar(p_inventario uuid, p_descripcion text, p_contenedor uuid default null,
                                                     p_articulo uuid default null, p_cantidad integer default null, p_foto text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  yo    public.usuario := app.exigir('SESION');
  nuevo uuid;
begin
  if not exists (select 1 from public.inventario_periodico where id = p_inventario and estado = 'ABIERTO') then
    raise exception 'Ese inventario ya está cerrado.';
  end if;
  if btrim(coalesce(p_descripcion, '')) = '' then
    raise exception 'Describe lo que encontraste.';
  end if;
  if p_foto is not null and (p_foto not like 'inventarios/' || p_inventario::text || '/%' or not app.archivo_existe('fotos', p_foto)) then
    raise exception 'La foto no terminó de subirse. Intenta de nuevo.';
  end if;
  insert into public.inventario_hallazgo (inventario_id, contenedor_id, articulo_id, descripcion, cantidad, foto_url, reportado_por)
  values (p_inventario, p_contenedor, p_articulo, btrim(p_descripcion), p_cantidad, p_foto, yo.id)
  returning id into nuevo;
  return nuevo;
end $$;

-- Por artículo: lo contado, la diferencia y si los contadores no coinciden.
create function app.inventario_resumen(p_inventario uuid)
returns table (articulo_id uuid, contados integer, sistema integer, fisico integer, diferencia integer, conflicto boolean, contadores text)
language sql stable security definer set search_path = '' as $$
  select al.articulo_id,
         count(l.id)::integer,
         (array_agg(l.cantidad_sistema order by l.contado_en desc))[1],
         (array_agg(l.cantidad_fisica order by l.contado_en desc))[1],
         (array_agg(l.cantidad_fisica - l.cantidad_sistema order by l.contado_en desc))[1],
         count(distinct l.cantidad_fisica - l.cantidad_sistema) > 1,
         string_agg(app.nombre_usuario(l.contado_por) || ': ' || l.cantidad_fisica, ', ' order by l.contado_en)
  from app.inventario_alcance(p_inventario) al
  left join public.conteo_linea l on l.inventario_id = p_inventario and l.articulo_id = al.articulo_id and not l.anulado
  group by al.articulo_id
$$;

create function public.inventario_diferencias(p_inventario uuid)
returns table (articulo_id uuid, codigo text, nombre text, unidad text, categoria text, ruta text, contados integer,
               sistema integer, fisico integer, diferencia integer, conflicto boolean, contadores text,
               decision text, nota text, en_taller_ahora integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  return query
    select r.articulo_id, a.codigo, a.nombre, a.unidad, a.categoria::text, app.ruta_contenedor(a.contenedor_id), r.contados,
           r.sistema, r.fisico, r.diferencia, r.conflicto, r.contadores, x.decision, x.nota, e.en_taller
    from app.inventario_resumen(p_inventario) r
    join public.articulo a on a.id = r.articulo_id
    join public.v_existencias e on e.articulo_id = a.id
    left join public.inventario_decision x on x.inventario_id = p_inventario and x.articulo_id = r.articulo_id
    order by r.contados = 0, r.conflicto desc, abs(coalesce(r.diferencia, 0)) desc, a.nombre;
end $$;

-- AJUSTE (se aplica al cerrar), INCIDENCIA (reporte de pérdida ya, si faltan) o RECONTAR (se anulan los conteos).
create function public.inventario_decidir(p_inventario uuid, p_articulo uuid, p_decision text, p_nota text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo   public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  i    public.inventario_periodico;
  r    record;
  inc  uuid;
begin
  select * into i from public.inventario_periodico where id = p_inventario;
  if not found or i.estado <> 'ABIERTO' then
    raise exception 'Ese inventario ya está cerrado.';
  end if;
  select * into r from app.inventario_resumen(p_inventario) x where x.articulo_id = p_articulo;
  if not found then
    raise exception 'Ese artículo no está en el alcance de este inventario.';
  end if;
  if p_decision = 'RECONTAR' then
    update public.conteo_linea set anulado = true where inventario_id = p_inventario and articulo_id = p_articulo and not anulado;
    update public.inventario_decision set decision = null, nota = null, decidido_por = yo.id, decidido_en = now()
     where inventario_id = p_inventario and articulo_id = p_articulo and incidencia_id is null;
    return;
  end if;
  if r.contados = 0 then
    raise exception 'Ese artículo no se ha contado.';
  end if;
  if r.conflicto then
    raise exception 'Los conteos no coinciden (%): mándalo a recontar.', r.contadores;
  end if;
  if p_decision = 'AJUSTE' then
    if r.diferencia <> 0 and btrim(coalesce(p_nota, '')) = '' then
      raise exception 'Explica la diferencia (%).', r.diferencia;
    end if;
  elsif p_decision = 'INCIDENCIA' then
    if r.diferencia >= 0 then
      raise exception 'Solo se levanta reporte de pérdida cuando faltan piezas.';
    end if;
    if length(btrim(coalesce(p_nota, ''))) < 15 then
      raise exception 'Describe el faltante (al menos 15 letras).';
    end if;
    inc := app.crear_incidencia(yo.id, null, p_articulo, 'PERDIDA', -r.diferencia, null, p_nota, '[]'::jsonb,
                                'Faltante detectado en el inventario "' || coalesce(i.nombre, 'periódico') || '"', null, null);
  else
    raise exception 'Decisión desconocida.';
  end if;
  insert into public.inventario_decision (inventario_id, articulo_id, decision, nota, decidido_por, decidido_en, incidencia_id)
  values (p_inventario, p_articulo, p_decision, nullif(btrim(p_nota), ''), yo.id, now(), inc)
  on conflict (inventario_id, articulo_id) do update
    set decision = excluded.decision, nota = excluded.nota, decidido_por = excluded.decidido_por,
        decidido_en = excluded.decidido_en, incidencia_id = coalesce(excluded.incidencia_id, inventario_decision.incidencia_id);
end $$;

create function public.inventario_hallazgos(p_inventario uuid)
returns table (id uuid, descripcion text, cantidad integer, contenedor text, articulo_id uuid, articulo text, foto_url text,
               reportado_por text, reportado_en timestamptz, decision text, nota text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.exigir('SESION');
  return query
    select h.id, h.descripcion, h.cantidad, app.ruta_contenedor(h.contenedor_id), h.articulo_id,
           (select a.codigo || ' ' || a.nombre from public.articulo a where a.id = h.articulo_id), h.foto_url,
           app.nombre_usuario(h.reportado_por), h.reportado_en, h.decision, h.nota
    from public.inventario_hallazgo h where h.inventario_id = p_inventario order by h.reportado_en;
end $$;

create function public.inventario_hallazgo_resolver(p_id uuid, p_decision text, p_nota text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  yo public.usuario := app.exigir('CONTRASENA', array['RESPONSABLE', 'SUBADMIN']::public.rol_usuario[]);
  h  public.inventario_hallazgo;
begin
  select * into h from public.inventario_hallazgo where id = p_id for update;
  if not found or h.decision is not null then
    raise exception 'Ese hallazgo ya se resolvió.';
  end if;
  if p_decision = 'MOVIDO' then
    if h.articulo_id is null or h.contenedor_id is null then
      raise exception 'Para moverlo, el hallazgo debe decir qué artículo es y en qué contenedor estaba.';
    end if;
    perform app.mover_articulo(yo.id, h.articulo_id, h.contenedor_id, 'INVENTARIO');
  elsif p_decision not in ('ALTA', 'IGNORADO') then
    raise exception 'Decisión desconocida.';
  end if;
  update public.inventario_hallazgo set decision = p_decision, nota = nullif(btrim(p_nota), ''), resuelto_por = yo.id, resuelto_en = now()
   where id = p_id;
end $$;

create function public.inventario_cerrar(p_inventario uuid) returns jsonb
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

-- ---------------------------------------------------------------------
-- "Avísame cuando regrese"
-- ---------------------------------------------------------------------
create table public.aviso_disponible (
  id           uuid primary key default gen_random_uuid(),
  articulo_id  uuid not null references public.articulo (id),
  correo       text not null,
  ip_hash      text,
  dispositivo  text,
  creado_en    timestamptz not null default now(),
  vence_en     timestamptz not null,
  estado       text not null default 'PENDIENTE' check (estado in ('PENDIENTE', 'AVISADO', 'VENCIDO')),
  avisado_en   timestamptz
);
create index aviso_disponible_pendiente_idx on public.aviso_disponible (articulo_id) where estado = 'PENDIENTE';

-- Solo la función del servidor "solicitud-publica" (conoce la red, para el freno).
create function public.aviso_disponible_crear(p_articulo uuid, p_correo text, p_ip text, p_dispositivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_correo text := lower(btrim(coalesce(p_correo, '')));
  v_disp   text := left(coalesce(nullif(btrim(p_dispositivo), ''), 'sin-dispositivo'), 64);
  v_red    text := app.huella('red:' || coalesce(p_ip, ''));
  a        public.articulo;
  e        record;
begin
  select * into a from public.articulo where id = p_articulo;
  if not found or not a.activo then
    raise exception 'El artículo no existe o está dado de baja.';
  end if;
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Escribe un correo válido.';
  end if;
  select * into e from public.v_existencias where articulo_id = p_articulo;
  if e.prestable and e.disponible > 0 then
    raise exception 'Ya hay disponible: puedes pedirlo ahora.';
  end if;
  if exists (select 1 from public.aviso_disponible x where x.articulo_id = p_articulo and x.correo = v_correo and x.estado = 'PENDIENTE') then
    return jsonb_build_object('ok', true, 'mensaje', 'Ya estaba registrado: te avisaremos a ese correo.');
  end if;
  if (select count(*) from public.limite_evento x where x.tipo = 'AVISO' and x.clave = 'd:' || v_disp and x.en > now() - interval '1 hour')
       >= app.config_int('avisos_disponible_por_hora')
     or (select count(*) from public.limite_evento x where x.tipo = 'AVISO' and x.clave = 'r:' || v_red and x.en > now() - interval '1 hour')
       >= app.config_int('avisos_disponible_por_hora_red') then
    raise exception 'Se pidieron demasiados avisos desde aquí. Intenta más tarde.';
  end if;
  insert into public.limite_evento (tipo, clave) values ('AVISO', 'd:' || v_disp), ('AVISO', 'r:' || v_red);
  insert into public.aviso_disponible (articulo_id, correo, ip_hash, dispositivo, vence_en)
  values (p_articulo, v_correo, v_red, v_disp, now() + make_interval(days => app.config_int('aviso_disponible_dias')));
  return jsonb_build_object('ok', true, 'mensaje', format('Listo: te avisaremos a %s cuando haya "%s" disponible (hasta %s días).',
                                                          app.enmascarar_correo(v_correo), a.nombre, app.config_int('aviso_disponible_dias')));
end $$;

create function app.revisar_avisos_disponible() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  n integer := 0;
begin
  update public.aviso_disponible set estado = 'VENCIDO' where estado = 'PENDIENTE' and vence_en < now();
  for r in select x.id, x.correo, a.id as articulo_id, a.nombre, a.codigo
             from public.aviso_disponible x
             join public.articulo a on a.id = x.articulo_id
             join public.v_existencias e on e.articulo_id = a.id
            where x.estado = 'PENDIENTE' and a.activo and e.prestable and e.disponible > 0
            for update of x skip locked loop
    perform app.encolar_correo(r.correo, format('Ya hay "%s" disponible', r.nombre),
      format(E'Hola:\n\nPediste que te avisáramos: "%s" (%s) ya está disponible en el Laboratorio Maker.\n\n'
             'Puedes pedirlo aquí (si alguien más lo pide antes, se lo llevan primero):\n%s/articulo/%s\n\nLaboratorio Maker',
             r.nombre, r.codigo, rtrim(coalesce(app.config_texto('url_app'), ''), '/'), r.articulo_id));
    update public.aviso_disponible set estado = 'AVISADO', avisado_en = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Almacén: fotos de hallazgos y de aportes (público, como el catálogo)
-- ---------------------------------------------------------------------
create policy fotos_subir_inventarios on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = 'inventarios' and app.puede_subir_foto());

-- ---------------------------------------------------------------------
-- Seguridad de las tablas nuevas y tareas automáticas
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['tarea_aporte', 'conteo_propuesto', 'plantilla_kit', 'plantilla_kit_linea', 'desglose', 'desglose_linea',
                           'inventario_decision', 'inventario_hallazgo', 'aviso_disponible'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    if t <> 'desglose_linea' then
      execute format('create trigger sin_borrado before delete on public.%I for each row execute function app.prohibir_borrado()', t);
    end if;
  end loop;
end $$;
create trigger solo_agregar before update or delete on public.tarea_aporte for each row execute function app.prohibir_edicion();

-- Las listas de contenido de fábrica son de consulta libre.
grant select on public.plantilla_kit, public.plantilla_kit_linea to anon, authenticated;
create policy lectura_publica on public.plantilla_kit       for select to anon, authenticated using (true);
create policy lectura_publica on public.plantilla_kit_linea for select to anon, authenticated using (true);

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $cron$select cron.schedule('inventario-tareas', '*/5 * * * *',
      'select app.tareas_periodicas(); select app.revisar_avisos_disponible(); select app.caducar_envios(); select app.despertar_envios() where app.hay_trabajo_para_avisos();')$cron$;
  end if;
end $$;

revoke execute on all functions in schema app from public;
grant execute on function app.puede_subir_foto(), app.puede_subir_foto_contenedor(), app.puede_subir_privado(text),
                          app.puede_ver_privado(text), app.ruta_contenedor(uuid) to authenticated;
grant execute on function app.ruta_contenedor(uuid) to anon;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma, p.proname
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('pendiente_aportar', 'pendiente_aportes', 'pendiente_resolver', 'conteo_proponer', 'conteos_por_aplicar',
                        'conteos_aplicar', 'conteos_descartar', 'desglose_iniciar', 'desglose_guardar', 'desglose_detalle',
                        'desgloses_de_articulo', 'desglose_terminar', 'desglose_cancelar', 'inventario_abrir', 'inventarios_listar',
                        'inventario_articulos', 'inventario_contar', 'inventario_hallazgo_registrar', 'inventario_diferencias',
                        'inventario_decidir', 'inventario_hallazgos', 'inventario_hallazgo_resolver', 'inventario_cerrar',
                        'aviso_disponible_crear')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.proname = 'aviso_disponible_crear' then
      execute format('grant execute on function %s to service_role', f.firma);
    else
      execute format('grant execute on function %s to authenticated', f.firma);
    end if;
  end loop;
end $$;
