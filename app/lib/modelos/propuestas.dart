/// Fase 11: lo que propone la selección de robótica y el responsable aprueba.
library;

class Propuesta {
  const Propuesta({
    required this.id,
    required this.tipo,
    required this.datos,
    required this.fotos,
    required this.estado,
    required this.creadaPor,
    required this.creadaEn,
    this.articuloId,
    this.codigo,
    this.nombreActual,
    this.cantidad,
    this.nota,
    this.motivo,
  });

  final String id;

  /// 'ALTA' (artículo nuevo) o 'CORRECCION' (cambios a uno que ya existe).
  final String tipo;
  final String? articuloId;
  final String? codigo;
  final String? nombreActual;

  /// Los campos propuestos: nombre, categoría, marca, observaciones…
  final Map<String, dynamic> datos;
  final int? cantidad;
  final List<String> fotos;
  final String? nota;

  /// 'PENDIENTE', 'APROBADA' o 'DESCARTADA'.
  final String estado;
  final String creadaPor;
  final DateTime creadaEn;

  /// Por qué no procedió, cuando se descartó.
  final String? motivo;

  bool get esAlta => tipo == 'ALTA';
  String get nombre => (datos['nombre'] as String?) ?? nombreActual ?? 'Sin nombre';

  factory Propuesta.desdeMapa(Map<String, dynamic> m) => Propuesta(
        id: m['id'] as String,
        tipo: m['tipo'] as String,
        articuloId: m['articulo_id'] as String?,
        codigo: m['codigo'] as String?,
        nombreActual: m['nombre_actual'] as String?,
        datos: Map<String, dynamic>.from((m['datos'] as Map?) ?? const {}),
        cantidad: m['cantidad'] as int?,
        fotos: [
          for (final f in (m['fotos'] as List? ?? const []))
            if (f is Map && f['ruta'] != null) f['ruta'] as String,
        ],
        nota: m['nota'] as String?,
        estado: m['estado'] as String,
        creadaPor: m['creada_por'] as String? ?? '',
        creadaEn: DateTime.parse(m['creada_en'] as String).toLocal(),
        motivo: m['motivo'] as String?,
      );
}

/// Un artículo que quizá es el mismo que se está por proponer.
class ArticuloParecido {
  const ArticuloParecido({required this.id, required this.codigo, required this.nombre, this.marcaModelo, this.foto});

  final String id;
  final String codigo;
  final String nombre;
  final String? marcaModelo;
  final String? foto;

  factory ArticuloParecido.desdeMapa(Map<String, dynamic> m) => ArticuloParecido(
        id: m['id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        marcaModelo: m['marca_modelo'] as String?,
        foto: m['foto'] as String?,
      );
}

/// Una foto que subió la selección y espera el visto bueno.
class FotoPorVerificar {
  const FotoPorVerificar({
    required this.id,
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.url,
    required this.tomadaPor,
    required this.tomadaEn,
  });

  final String id;
  final String articuloId;
  final String codigo;
  final String nombre;
  final String url;
  final String tomadaPor;
  final DateTime tomadaEn;

  factory FotoPorVerificar.desdeMapa(Map<String, dynamic> m) => FotoPorVerificar(
        id: m['id'] as String,
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        url: m['url'] as String,
        tomadaPor: m['tomada_por'] as String? ?? '',
        tomadaEn: DateTime.parse(m['tomada_en'] as String).toLocal(),
      );
}
