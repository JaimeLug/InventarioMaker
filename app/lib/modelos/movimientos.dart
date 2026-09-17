import 'catalogos.dart';

DateTime _fecha(Object? v) => DateTime.parse(v as String);
DateTime? _fechaOpcional(Object? v) => v == null ? null : DateTime.parse(v as String);

/// Préstamo abierto de un artículo, visto al recibir su devolución.
class PrestamoAbierto {
  const PrestamoAbierto({
    required this.id,
    required this.cantidadPrestada,
    required this.pendiente,
    required this.fecha,
    required this.venceEn,
    required this.vencido,
    required this.aCargo,
    this.autorizo,
  });

  final String id;
  final int cantidadPrestada;
  final int pendiente;
  final DateTime fecha;
  final DateTime venceEn;
  final bool vencido;
  final String aCargo;
  final String? autorizo;

  factory PrestamoAbierto.desdeMapa(Map<String, dynamic> m) => PrestamoAbierto(
        id: m['prestamo_id'] as String,
        cantidadPrestada: m['cantidad_prestada'] as int,
        pendiente: m['pendiente'] as int,
        fecha: _fecha(m['fecha']),
        venceEn: _fecha(m['vence_en']),
        vencido: m['vencido'] as bool,
        aCargo: m['a_cargo'] as String,
        autorizo: m['autorizo'] as String?,
      );
}

/// Renglón de "Mis préstamos" y de "Préstamos abiertos".
class PrestamoListado {
  const PrestamoListado({
    required this.id,
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.pendiente,
    required this.venceEn,
    required this.vencido,
    required this.aCargo,
    this.aMiNombre = false,
    this.autorizo,
    this.extensiones = 0,
  });

  final String id;
  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final int pendiente;
  final DateTime venceEn;
  final bool vencido;
  final String aCargo;
  final bool aMiNombre;
  final String? autorizo;
  final int extensiones;

  factory PrestamoListado.desdeMapa(Map<String, dynamic> m) => PrestamoListado(
        id: m['prestamo_id'] as String,
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String,
        pendiente: m['pendiente'] as int,
        venceEn: _fecha(m['vence_en']),
        vencido: m['vencido'] as bool,
        aCargo: m['a_cargo'] as String,
        aMiNombre: m['a_mi_nombre'] as bool? ?? false,
        autorizo: m['autorizo'] as String?,
        extensiones: m['extensiones'] as int? ?? 0,
      );
}

class SolicitanteEncontrado {
  const SolicitanteEncontrado({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.bloqueado,
    required this.verificada,
    required this.vencidos,
    this.grupo,
  });

  final String id;
  final String nombre;
  final TipoSolicitante tipo;
  final String? grupo;
  final bool bloqueado;
  final bool verificada;
  final int vencidos;

  factory SolicitanteEncontrado.desdeMapa(Map<String, dynamic> m) => SolicitanteEncontrado(
        id: m['id'] as String,
        nombre: m['nombre_completo'] as String,
        tipo: TipoSolicitante.desde(m['tipo'] as String),
        grupo: m['grupo_area'] as String?,
        bloqueado: m['bloqueado'] as bool,
        verificada: m['verificada'] as bool,
        vencidos: m['vencidos'] as int,
      );
}

class Comentario {
  const Comentario(this.autor, this.texto, this.en);

  final String autor;
  final String texto;
  final DateTime en;

  static List<Comentario> lista(Object? v) => [
        for (final c in (v as List? ?? const []))
          Comentario(c['autor'] as String? ?? '', c['texto'] as String, _fecha(c['en'])),
      ];
}

/// Reporte de pérdida, daño o consumo por revisar (o uno propio, en "Mis reportes").
class Incidencia {
  const Incidencia({
    required this.id,
    required this.tipo,
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.cantidad,
    required this.nota,
    required this.reportadaEn,
    required this.fotos,
    required this.comentarios,
    this.unidad = 'pieza',
    this.estado = 'PENDIENTE',
    this.enTaller = true,
    this.sinFotoJustificacion,
    this.reportadaPor,
    this.aCargo,
    this.resueltaPor,
    this.motivoResolucion,
  });

  final String id;
  final String tipo;
  final String estado;
  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final int cantidad;
  final bool enTaller;
  final String nota;
  final String? sinFotoJustificacion;
  final String? reportadaPor;
  final DateTime reportadaEn;
  final String? aCargo;
  final String? resueltaPor;
  final String? motivoResolucion;
  final List<String> fotos;
  final List<Comentario> comentarios;

  factory Incidencia.desdeMapa(Map<String, dynamic> m) => Incidencia(
        id: m['id'] as String,
        tipo: m['tipo'] as String,
        estado: m['estado'] as String? ?? 'PENDIENTE',
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String? ?? 'pieza',
        cantidad: m['cantidad'] as int,
        enTaller: m['en_taller'] as bool? ?? true,
        nota: m['nota'] as String,
        sinFotoJustificacion: m['sin_foto_justificacion'] as String?,
        reportadaPor: m['reportada_por'] as String?,
        reportadaEn: _fecha(m['reportada_en']),
        aCargo: m['a_cargo'] as String?,
        resueltaPor: m['resuelta_por'] as String?,
        motivoResolucion: m['motivo_resolucion'] as String?,
        fotos: [for (final f in (m['fotos'] as List? ?? const [])) f as String],
        comentarios: Comentario.lista(m['comentarios']),
      );

  String get nombreTipo => switch (tipo) {
        'PERDIDA' => 'Pérdida',
        'DANO' => 'Daño',
        _ => 'Consumo',
      };

  String get nombreEstado => switch (estado) {
        'CONFIRMADA' => 'Confirmado',
        'DESCARTADA' => 'Descartado',
        _ => 'En revisión',
      };
}

/// Movimiento con nombres (solo responsable y sub administración).
class MovimientoDetallado {
  const MovimientoDetallado({
    required this.tipo,
    required this.fecha,
    required this.conflicto,
    this.cantidad,
    this.nota,
    this.autorizo,
    this.aCargo,
  });

  final String tipo;
  final int? cantidad;
  final DateTime fecha;
  final String? nota;
  final String? autorizo;
  final String? aCargo;
  final bool conflicto;

  factory MovimientoDetallado.desdeMapa(Map<String, dynamic> m) => MovimientoDetallado(
        tipo: m['tipo'] as String,
        cantidad: m['cantidad'] as int?,
        fecha: _fecha(m['fecha']),
        nota: m['nota'] as String?,
        autorizo: m['autorizo'] as String?,
        aCargo: m['a_cargo'] as String?,
        conflicto: m['conflicto'] as bool? ?? false,
      );

  String get nombre => nombresMovimiento[tipo] ?? tipo;
}

class EventoBitacora {
  const EventoBitacora({required this.id, required this.en, required this.evento, this.usuario, this.referencia, this.datos});

  final int id;
  final DateTime en;
  final String evento;
  final String? usuario;
  final String? referencia;
  final Map<String, dynamic>? datos;

  factory EventoBitacora.desdeMapa(Map<String, dynamic> m) => EventoBitacora(
        id: m['id'] as int,
        en: _fecha(m['en']),
        evento: m['evento'] as String,
        usuario: m['usuario'] as String?,
        referencia: m['referencia'] as String?,
        datos: m['datos'] == null ? null : Map<String, dynamic>.from(m['datos'] as Map),
      );
}

/// Fecha de devolución por defecto en un préstamo directo (la que también usa el servidor).
DateTime? fechaHoraOpcional(Object? v) => _fechaOpcional(v);
