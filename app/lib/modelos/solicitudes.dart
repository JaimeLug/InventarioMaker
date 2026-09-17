import 'catalogos.dart';

DateTime? _f(Object? v) => v == null ? null : DateTime.parse(v as String);
Map<String, dynamic> _m(Object? v) => v == null ? const {} : Map<String, dynamic>.from(v as Map);
List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

enum EstadoSolicitud {
  pendiente('PENDIENTE', 'En revisión'),
  aprobada('APROBADA', 'Aprobada: pasa a recoger'),
  rechazada('RECHAZADA', 'Rechazada'),
  entregado('ENTREGADO', 'Entregada'),
  devuelta('DEVUELTA', 'Devuelta'),
  vencida('VENCIDA', 'Vencida'),
  cancelada('CANCELADA', 'Cancelada');

  const EstadoSolicitud(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static EstadoSolicitud desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);

  bool get abierta => this == pendiente || this == aprobada;
  bool get conMaterial => this == entregado || this == vencida;
}

/// Motivos que se ofrecen al pedir (F-04 paso 4). "Otro" pide escribirlo.
const motivosSolicitud = ['Proyecto de clase', 'Concurso', 'Práctica', 'Uso en clase con mi grupo', 'Otro'];

/// Motivos de rechazo (F-06 paso 5).
const motivosRechazo = ['No hay disponible', 'Uso no justificado', 'Adeudo', 'Material delicado', 'Otro'];

const tiposIdentificacion = {
  'TRANSPORTE': 'Credencial de transporte',
  'DOCUMENTO_ESCOLAR': 'Documento escolar con foto',
  'INE': 'INE',
  'OTRA': 'Otra identificación con foto',
};

/// Cuándo pasa a recoger: fija la vigencia del código de entrega (P-11).
const vigenciasCodigo = {
  'RATO': 'Ahora o en un rato (1 h 30 min)',
  'HOY': 'Hoy más tarde (hasta el fin de la jornada)',
  'MANANA': 'Mañana (hasta 24 horas)',
};

class LineaSolicitud {
  const LineaSolicitud({
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    this.aprobada,
    this.pendiente = 0,
    this.disponible,
    this.prestable = true,
    this.foto,
  });

  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final int cantidad;
  final int? aprobada;
  final int pendiente;
  final int? disponible;
  final bool prestable;
  final String? foto;

  int get cantidadFinal => aprobada ?? cantidad;

  factory LineaSolicitud.desdeMapa(Map<String, dynamic> m) => LineaSolicitud(
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String? ?? 'pieza',
        cantidad: m['cantidad'] as int,
        aprobada: m['aprobada'] as int?,
        pendiente: m['pendiente'] as int? ?? 0,
        disponible: m['disponible'] as int?,
        prestable: m['prestable'] as bool? ?? true,
        foto: m['foto'] as String?,
      );
}

/// Lo que ve quien pidió, con su enlace secreto (sin cuenta).
class SolicitudPublica {
  const SolicitudPublica({
    required this.folio,
    required this.estado,
    required this.confirmada,
    required this.enlaceDeCorreo,
    required this.creadaEn,
    required this.motivo,
    required this.fechaDevolucion,
    required this.nombre,
    required this.lineas,
    required this.codigoAceptado,
    this.matricula,
    this.grupo,
    this.correo,
    this.recogerHasta,
    this.motivoRechazo,
    this.motivoCancelacion,
    this.notaAprobacion,
    this.entregadaEn,
    this.autorizo,
  });

  final String folio;
  final EstadoSolicitud estado;
  final bool confirmada;
  final bool enlaceDeCorreo;
  final DateTime creadaEn;
  final String motivo;
  final DateTime fechaDevolucion;
  final String nombre;
  final String? matricula;
  final String? grupo;
  final String? correo;
  final DateTime? recogerHasta;
  final String? motivoRechazo;
  final String? motivoCancelacion;
  final String? notaAprobacion;
  final DateTime? entregadaEn;
  final String? autorizo;
  final bool codigoAceptado;
  final List<LineaSolicitud> lineas;

  factory SolicitudPublica.desdeMapa(Map<String, dynamic> m) {
    final s = _m(m['solicitante']);
    return SolicitudPublica(
      folio: m['folio'] as String,
      estado: EstadoSolicitud.desde(m['estado'] as String),
      confirmada: m['confirmada'] as bool,
      enlaceDeCorreo: m['enlace_de_correo'] as bool? ?? false,
      creadaEn: _f(m['creada_en'])!,
      motivo: m['motivo'] as String,
      fechaDevolucion: _f(m['fecha_devolucion'])!,
      nombre: s['nombre'] as String? ?? '',
      matricula: s['matricula'] as String?,
      grupo: s['grupo'] as String?,
      correo: m['correo'] as String?,
      recogerHasta: _f(m['recoger_hasta']),
      motivoRechazo: m['motivo_rechazo'] as String?,
      motivoCancelacion: m['motivo_cancelacion'] as String?,
      notaAprobacion: m['nota_aprobacion'] as String?,
      entregadaEn: _f(m['entregada_en']),
      autorizo: m['autorizo'] as String?,
      codigoAceptado: m['codigo_aceptado'] as bool? ?? false,
      lineas: _l(m['lineas']).map(LineaSolicitud.desdeMapa).toList(),
    );
  }

  int get piezasPendientes => lineas.fold(0, (s, l) => s + l.pendiente);
  int get piezasEntregadas => lineas.fold(0, (s, l) => s + l.cantidadFinal);
}

/// Resultado de enviar una solicitud.
class SolicitudEnviada {
  const SolicitudEnviada({
    required this.folio,
    required this.token,
    required this.reconocido,
    required this.iniciales,
    required this.sinCorreo,
    this.correo,
  });

  final String folio;
  final String token;
  final bool reconocido;
  final String iniciales;
  final String? correo;
  final bool sinCorreo;

  factory SolicitudEnviada.desdeMapa(Map<String, dynamic> m) => SolicitudEnviada(
        folio: m['folio'] as String,
        token: m['token'] as String,
        reconocido: m['reconocido'] as bool? ?? false,
        iniciales: m['iniciales'] as String? ?? '',
        correo: m['correo'] as String?,
        sinCorreo: m['sin_correo'] as bool? ?? false,
      );
}

/// Renglón de la bandeja de solicitudes.
class SolicitudResumen {
  const SolicitudResumen({
    required this.id,
    required this.folio,
    required this.estado,
    required this.creadaEn,
    required this.solicitante,
    required this.verificada,
    required this.posibleDuplicado,
    required this.articulos,
    required this.piezas,
    required this.fechaDevolucion,
    required this.vencida,
    this.confirmadaEn,
    this.recogerHasta,
    this.alerta,
  });

  final String id;
  final String folio;
  final EstadoSolicitud estado;
  final DateTime creadaEn;
  final DateTime? confirmadaEn;
  final String solicitante;
  final bool verificada;
  final bool posibleDuplicado;
  final int articulos;
  final int piezas;
  final DateTime fechaDevolucion;
  final DateTime? recogerHasta;
  final bool vencida;
  final String? alerta;

  factory SolicitudResumen.desdeMapa(Map<String, dynamic> m) => SolicitudResumen(
        id: m['id'] as String,
        folio: m['folio'] as String,
        estado: EstadoSolicitud.desde(m['estado'] as String),
        creadaEn: _f(m['creada_en'])!,
        confirmadaEn: _f(m['confirmada_en']),
        solicitante: m['solicitante'] as String,
        verificada: m['verificada'] as bool,
        posibleDuplicado: m['posible_duplicado'] as bool,
        articulos: m['articulos'] as int,
        piezas: m['piezas'] as int,
        fechaDevolucion: _f(m['fecha_devolucion'])!,
        recogerHasta: _f(m['recoger_hasta']),
        vencida: m['vencida'] as bool,
        alerta: m['alerta'] as String?,
      );
}

class CodigoEntrega {
  const CodigoEntrega({required this.estado, required this.expiraEn, this.codigo, this.usadoEn, this.entregaAnuladaEn, this.intentosFallidos = 0});

  final String estado;
  final DateTime expiraEn;
  final String? codigo;
  final DateTime? usadoEn;
  final DateTime? entregaAnuladaEn;
  final int intentosFallidos;

  factory CodigoEntrega.desdeMapa(Map<String, dynamic> m) => CodigoEntrega(
        estado: m['estado'] as String,
        expiraEn: _f(m['expira_en'])!,
        codigo: m['codigo'] as String?,
        usadoEn: _f(m['usado_en']),
        entregaAnuladaEn: _f(m['entrega_anulada_en']),
        intentosFallidos: m['intentos_fallidos'] as int? ?? 0,
      );

  bool get vigente => estado == 'VIGENTE' && expiraEn.isAfter(DateTime.now()) && codigo != null;

  /// El solicitante ya lo escribió y la entrega sigue en curso.
  bool get aceptado => estado == 'USADO' && entregaAnuladaEn == null;

  String get nombreEstado => switch (estado) {
        'VIGENTE' => expiraEn.isAfter(DateTime.now()) ? 'Vigente' : 'Venció',
        'USADO' => 'Usado',
        'EXPIRADO' => 'Venció sin usarse',
        'ANULADO' => 'Reemplazado por otro',
        'BLOQUEADO' => 'Bloqueado por intentos',
        _ => estado,
      };
}

class FichaSolicitante {
  const FichaSolicitante({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.matricula,
    required this.correoConfirmado,
    required this.posibleDuplicado,
    required this.prestamosAnteriores,
    required this.conRetraso,
    this.grupo,
    this.telefono,
    this.correo,
    this.nota,
    this.verificadaPor,
    this.verificadaEn,
    this.impedimento,
  });

  final String id;
  final String nombre;
  final TipoSolicitante tipo;
  final String matricula;
  final String? grupo;
  final String? telefono;
  final String? correo;
  final String? nota;
  final String? verificadaPor;
  final DateTime? verificadaEn;
  final bool correoConfirmado;
  final bool posibleDuplicado;
  final String? impedimento;
  final int prestamosAnteriores;
  final int conRetraso;

  factory FichaSolicitante.desdeMapa(Map<String, dynamic> m) => FichaSolicitante(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        tipo: TipoSolicitante.desde(m['tipo'] as String),
        matricula: m['matricula'] as String,
        grupo: m['grupo'] as String?,
        telefono: m['telefono'] as String?,
        correo: m['correo'] as String?,
        nota: m['nota'] as String?,
        verificadaPor: m['verificada_por'] as String?,
        verificadaEn: _f(m['verificada_en']),
        correoConfirmado: m['correo_confirmado'] as bool? ?? false,
        posibleDuplicado: m['posible_duplicado'] as bool? ?? false,
        impedimento: m['impedimento'] as String?,
        prestamosAnteriores: m['prestamos_anteriores'] as int? ?? 0,
        conRetraso: m['con_retraso'] as int? ?? 0,
      );

  String get historial => prestamosAnteriores == 0
      ? 'Primer préstamo'
      : '$prestamosAnteriores préstamo${prestamosAnteriores == 1 ? '' : 's'} anterior${prestamosAnteriores == 1 ? '' : 'es'}'
          '${conRetraso == 0 ? ', todos a tiempo' : ', $conRetraso con retraso'}';
}

class SolicitudDetalle {
  const SolicitudDetalle({
    required this.id,
    required this.folio,
    required this.estado,
    required this.motivo,
    required this.creadaEn,
    required this.fechaDevolucion,
    required this.solicitante,
    required this.lineas,
    required this.codigos,
    required this.fotosEntrega,
    required this.hayIdentificacion,
    required this.identificacionBorrada,
    required this.prestamos,
    required this.otroCorreo,
    this.confirmadaEn,
    this.confirmadaComo,
    this.recogerHasta,
    this.autorizo,
    this.notaAprobacion,
    this.motivoRechazo,
    this.motivoCancelacion,
    this.entregadaEn,
    this.entrego,
    this.tipoIdentificacion,
    this.noFuiYoEn,
    this.codigo,
  });

  final String id;
  final String folio;
  final EstadoSolicitud estado;
  final String motivo;
  final DateTime creadaEn;
  final DateTime? confirmadaEn;
  final String? confirmadaComo;
  final DateTime fechaDevolucion;
  final DateTime? recogerHasta;
  final String? autorizo;
  final String? notaAprobacion;
  final String? motivoRechazo;
  final String? motivoCancelacion;
  final DateTime? entregadaEn;
  final String? entrego;
  final String? tipoIdentificacion;
  final DateTime? noFuiYoEn;
  final bool otroCorreo;
  final FichaSolicitante solicitante;
  final List<LineaSolicitud> lineas;
  final CodigoEntrega? codigo;
  final List<CodigoEntrega> codigos;
  final List<String> fotosEntrega;
  final bool hayIdentificacion;
  final bool identificacionBorrada;
  final List<Map<String, dynamic>> prestamos;

  factory SolicitudDetalle.desdeMapa(Map<String, dynamic> m) => SolicitudDetalle(
        id: m['id'] as String,
        folio: m['folio'] as String,
        estado: EstadoSolicitud.desde(m['estado'] as String),
        motivo: m['motivo'] as String,
        creadaEn: _f(m['creada_en'])!,
        confirmadaEn: _f(m['confirmada_en']),
        confirmadaComo: m['confirmada_como'] as String?,
        fechaDevolucion: _f(m['fecha_devolucion'])!,
        recogerHasta: _f(m['recoger_hasta']),
        autorizo: m['autorizo'] as String?,
        notaAprobacion: m['nota_aprobacion'] as String?,
        motivoRechazo: m['motivo_rechazo'] as String?,
        motivoCancelacion: m['motivo_cancelacion'] as String?,
        entregadaEn: _f(m['entregada_en']),
        entrego: m['entrego'] as String?,
        tipoIdentificacion: m['tipo_identificacion'] as String?,
        noFuiYoEn: _f(m['no_fui_yo_en']),
        otroCorreo: m['otro_correo'] as bool? ?? false,
        solicitante: FichaSolicitante.desdeMapa(_m(m['solicitante'])),
        lineas: _l(m['lineas']).map(LineaSolicitud.desdeMapa).toList(),
        codigo: m['codigo'] == null ? null : CodigoEntrega.desdeMapa(_m(m['codigo'])),
        codigos: _l(m['codigos']).map(CodigoEntrega.desdeMapa).toList(),
        fotosEntrega: [for (final f in (m['fotos_entrega'] as List? ?? const [])) f as String],
        hayIdentificacion: m['hay_identificacion'] as bool? ?? false,
        identificacionBorrada: m['identificacion_borrada'] as bool? ?? false,
        prestamos: _l(m['prestamos']),
      );
}

class Adeudo {
  const Adeudo({
    required this.personaTipo,
    required this.personaId,
    required this.nombre,
    required this.detalle,
    required this.piezas,
    required this.prestamos,
    required this.desde,
    required this.vencidos,
    required this.bloqueado,
  });

  final String personaTipo;
  final String personaId;
  final String nombre;
  final String detalle;
  final int piezas;
  final int prestamos;
  final DateTime desde;
  final int vencidos;
  final bool bloqueado;

  factory Adeudo.desdeMapa(Map<String, dynamic> m) => Adeudo(
        personaTipo: m['persona_tipo'] as String,
        personaId: m['persona_id'] as String,
        nombre: m['nombre'] as String,
        detalle: m['detalle'] as String? ?? '',
        piezas: m['piezas'] as int,
        prestamos: m['prestamos'] as int,
        desde: _f(m['desde'])!,
        vencidos: m['vencidos'] as int,
        bloqueado: m['bloqueado'] as bool,
      );
}

class Aviso {
  const Aviso({required this.id, required this.titulo, required this.creadoEn, required this.leido, this.cuerpo, this.ruta});

  final String id;
  final String titulo;
  final String? cuerpo;
  final String? ruta;
  final DateTime creadoEn;
  final bool leido;

  factory Aviso.desdeMapa(Map<String, dynamic> m) => Aviso(
        id: m['id'] as String,
        titulo: m['titulo'] as String,
        cuerpo: m['cuerpo'] as String?,
        ruta: m['ruta'] as String?,
        creadoEn: _f(m['creado_en'])!,
        leido: m['leido'] as bool,
      );
}

/// Un artículo en "Mi solicitud" (se guarda solo en este dispositivo).
class LineaCarrito {
  LineaCarrito({required this.articuloId, required this.codigo, required this.nombre, required this.unidad, required this.cantidad, this.foto});

  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final String? foto;
  int cantidad;

  Map<String, dynamic> aMapa() =>
      {'articulo_id': articuloId, 'codigo': codigo, 'nombre': nombre, 'unidad': unidad, 'foto': foto, 'cantidad': cantidad};

  factory LineaCarrito.desdeMapa(Map<String, dynamic> m) => LineaCarrito(
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String? ?? 'pieza',
        foto: m['foto'] as String?,
        cantidad: m['cantidad'] as int,
      );
}

/// Una solicitud cuyo enlace se guardó en este dispositivo.
class SolicitudGuardada {
  const SolicitudGuardada({required this.folio, required this.token, required this.enviadaEn});

  final String folio;
  final String token;
  final DateTime enviadaEn;

  Map<String, dynamic> aMapa() => {'folio': folio, 'token': token, 'enviada_en': enviadaEn.toIso8601String()};

  factory SolicitudGuardada.desdeMapa(Map<String, dynamic> m) =>
      SolicitudGuardada(folio: m['folio'] as String, token: m['token'] as String, enviadaEn: DateTime.parse(m['enviada_en'] as String));
}
