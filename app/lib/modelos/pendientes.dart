DateTime? _f(Object? v) => v == null ? null : DateTime.parse(v as String);

class PendienteAbierto {
  const PendienteAbierto({
    required this.id,
    required this.articuloId,
    required this.tipo,
    required this.descripcion,
    required this.prioridadAlta,
    required this.creadaEn,
  });

  final String id;
  final String articuloId;
  final String tipo;
  final String descripcion;
  final bool prioridadAlta;
  final DateTime creadaEn;

  factory PendienteAbierto.desdeMapa(Map<String, dynamic> m) => PendienteAbierto(
        id: m['id'] as String,
        articuloId: m['articulo_id'] as String,
        tipo: m['tipo'] as String,
        descripcion: m['descripcion'] as String,
        prioridadAlta: (m['prioridad'] as int? ?? 0) == 1,
        creadaEn: _f(m['creada_en'])!,
      );
}

class AportePendiente {
  const AportePendiente({required this.autor, required this.nota, required this.en, this.foto});

  final String autor;
  final String nota;
  final String? foto;
  final DateTime en;

  factory AportePendiente.desdeMapa(Map<String, dynamic> m) =>
      AportePendiente(autor: m['autor'] as String? ?? '', nota: m['nota'] as String, foto: m['foto_url'] as String?, en: _f(m['en'])!);
}

class ConteoPorAplicar {
  const ConteoPorAplicar({
    required this.id,
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.estimada,
    required this.enTaller,
    required this.sistema,
    required this.contadoPor,
    required this.contadoEn,
    required this.mio,
    this.nota,
  });

  final String id;
  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final bool estimada;
  final int enTaller;
  final int sistema;
  final String? nota;
  final String contadoPor;
  final DateTime contadoEn;
  final bool mio;

  int get diferencia => enTaller - sistema;

  factory ConteoPorAplicar.desdeMapa(Map<String, dynamic> m) => ConteoPorAplicar(
        id: m['id'] as String,
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String? ?? 'pieza',
        estimada: m['estimada'] as bool? ?? false,
        enTaller: m['en_taller'] as int,
        sistema: m['sistema'] as int,
        nota: m['nota'] as String?,
        contadoPor: m['contado_por'] as String? ?? '',
        contadoEn: _f(m['contado_en'])!,
        mio: m['mio'] as bool? ?? false,
      );
}

class PlantillaKit {
  const PlantillaKit({required this.id, required this.nombre, required this.categoria, this.sku, this.nota});

  final String id;
  final String nombre;
  final String? sku;
  final String categoria;
  final String? nota;

  factory PlantillaKit.desdeMapa(Map<String, dynamic> m) => PlantillaKit(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        sku: m['sku'] as String?,
        categoria: m['categoria'] as String,
        nota: m['nota'] as String?,
      );
}

/// Un renglón del desglose de un kit (editable mientras es borrador).
class LineaDesglose {
  LineaDesglose({
    required this.descripcion,
    this.plantillaLineaId,
    this.seccion,
    this.sku,
    this.esperada,
    this.encontrada,
    this.articuloDestinoId,
    this.articuloDestino,
    this.unidad = 'pieza',
    this.esConsumible = false,
    this.nota,
    this.articuloCreado,
  });

  String descripcion;
  String? plantillaLineaId;
  String? seccion;
  String? sku;
  int? esperada;
  int? encontrada;
  String? articuloDestinoId;
  String? articuloDestino;
  String unidad;
  bool esConsumible;
  String? nota;
  final String? articuloCreado;

  int get faltante => esperada == null ? 0 : (esperada! - (encontrada ?? 0)).clamp(0, 1 << 30);

  factory LineaDesglose.desdeMapa(Map<String, dynamic> m) => LineaDesglose(
        descripcion: m['descripcion'] as String,
        plantillaLineaId: m['plantilla_linea_id'] as String?,
        seccion: m['seccion'] as String?,
        sku: m['sku'] as String?,
        esperada: m['esperada'] as int?,
        encontrada: m['encontrada'] as int?,
        articuloDestinoId: m['articulo_destino_id'] as String?,
        articuloDestino: m['articulo_destino'] as String?,
        unidad: m['unidad'] as String? ?? 'pieza',
        esConsumible: m['es_consumible'] as bool? ?? false,
        nota: m['nota'] as String?,
        articuloCreado: m['articulo_creado'] as String?,
      );

  Map<String, dynamic> aMapa() => {
        'descripcion': descripcion,
        'plantilla_linea_id': plantillaLineaId,
        'seccion': seccion,
        'sku': sku,
        'esperada': esperada,
        'encontrada': encontrada,
        'articulo_destino_id': articuloDestinoId,
        'unidad': unidad,
        'es_consumible': esConsumible,
        'nota': nota,
      };
}

class Desglose {
  Desglose({
    required this.id,
    required this.estado,
    required this.unidades,
    required this.articuloId,
    required this.articuloCodigo,
    required this.articuloNombre,
    required this.categoria,
    required this.existencia,
    required this.enTaller,
    required this.lineas,
    this.plantilla,
    this.destino,
    this.nota,
  });

  final String id;
  final String estado;
  int unidades;
  final String articuloId;
  final String articuloCodigo;
  final String articuloNombre;
  final String categoria;
  final int existencia;
  final int enTaller;
  final String? plantilla;
  final String? destino;
  String? nota;
  final List<LineaDesglose> lineas;

  bool get borrador => estado == 'BORRADOR';

  factory Desglose.desdeMapa(Map<String, dynamic> m) {
    final a = Map<String, dynamic>.from(m['articulo'] as Map);
    return Desglose(
      id: m['id'] as String,
      estado: m['estado'] as String,
      unidades: m['unidades'] as int,
      destino: m['destino'] as String?,
      nota: m['nota'] as String?,
      plantilla: m['plantilla'] == null ? null : (m['plantilla'] as Map)['nombre'] as String,
      articuloId: a['id'] as String,
      articuloCodigo: a['codigo'] as String,
      articuloNombre: a['nombre'] as String,
      categoria: a['categoria'] as String,
      existencia: a['existencia'] as int? ?? 0,
      enTaller: a['en_taller'] as int? ?? 0,
      lineas: [for (final l in (m['lineas'] as List? ?? const [])) LineaDesglose.desdeMapa(Map<String, dynamic>.from(l as Map))],
    );
  }
}

class InventarioResumen {
  const InventarioResumen({
    required this.id,
    required this.nombre,
    required this.abierto,
    required this.fechaInicio,
    required this.articulos,
    required this.contados,
    this.fechaCierre,
    this.abrio,
    this.cerro,
  });

  final String id;
  final String nombre;
  final bool abierto;
  final DateTime fechaInicio;
  final DateTime? fechaCierre;
  final String? abrio;
  final String? cerro;
  final int articulos;
  final int contados;

  factory InventarioResumen.desdeMapa(Map<String, dynamic> m) => InventarioResumen(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        abierto: m['estado'] == 'ABIERTO',
        fechaInicio: _f(m['fecha_inicio'])!,
        fechaCierre: _f(m['fecha_cierre']),
        abrio: m['abrio'] as String?,
        cerro: m['cerro'] as String?,
        articulos: m['articulos'] as int? ?? 0,
        contados: m['contados'] as int? ?? 0,
      );
}

class ArticuloDeInventario {
  const ArticuloDeInventario({
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    required this.enTaller,
    required this.conteos,
    required this.decidido,
    this.subcategoria,
    this.contenedorId,
    this.contenedorCodigo,
    this.ruta,
    this.miConteo,
  });

  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final String categoria;
  final String? subcategoria;
  final String? contenedorId;
  final String? contenedorCodigo;
  final String? ruta;
  final int enTaller;
  final int? miConteo;
  final int conteos;
  final bool decidido;

  factory ArticuloDeInventario.desdeMapa(Map<String, dynamic> m) => ArticuloDeInventario(
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String? ?? 'pieza',
        categoria: m['categoria'] as String,
        subcategoria: m['subcategoria'] as String?,
        contenedorId: m['contenedor_id'] as String?,
        contenedorCodigo: m['contenedor_codigo'] as String?,
        ruta: m['ruta'] as String?,
        enTaller: m['en_taller'] as int? ?? 0,
        miConteo: m['mi_conteo'] as int?,
        conteos: m['conteos'] as int? ?? 0,
        decidido: m['decidido'] as bool? ?? false,
      );
}

class DiferenciaInventario {
  const DiferenciaInventario({
    required this.articuloId,
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.contados,
    required this.conflicto,
    required this.enTallerAhora,
    this.ruta,
    this.sistema,
    this.fisico,
    this.diferencia,
    this.contadores,
    this.decision,
    this.nota,
  });

  final String articuloId;
  final String codigo;
  final String nombre;
  final String unidad;
  final String? ruta;
  final int contados;
  final int? sistema;
  final int? fisico;
  final int? diferencia;
  final bool conflicto;
  final String? contadores;
  final String? decision;
  final String? nota;
  final int enTallerAhora;

  bool get pendiente => contados > 0 && (conflicto || (diferencia != 0 && decision == null));

  factory DiferenciaInventario.desdeMapa(Map<String, dynamic> m) => DiferenciaInventario(
        articuloId: m['articulo_id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String? ?? 'pieza',
        ruta: m['ruta'] as String?,
        contados: m['contados'] as int? ?? 0,
        sistema: m['sistema'] as int?,
        fisico: m['fisico'] as int?,
        diferencia: m['diferencia'] as int?,
        conflicto: m['conflicto'] as bool? ?? false,
        contadores: m['contadores'] as String?,
        decision: m['decision'] as String?,
        nota: m['nota'] as String?,
        enTallerAhora: m['en_taller_ahora'] as int? ?? 0,
      );
}

class Hallazgo {
  const Hallazgo({
    required this.id,
    required this.descripcion,
    required this.reportadoPor,
    required this.reportadoEn,
    this.cantidad,
    this.contenedor,
    this.articuloId,
    this.articulo,
    this.foto,
    this.decision,
    this.nota,
  });

  final String id;
  final String descripcion;
  final int? cantidad;
  final String? contenedor;
  final String? articuloId;
  final String? articulo;
  final String? foto;
  final String reportadoPor;
  final DateTime reportadoEn;
  final String? decision;
  final String? nota;

  factory Hallazgo.desdeMapa(Map<String, dynamic> m) => Hallazgo(
        id: m['id'] as String,
        descripcion: m['descripcion'] as String,
        cantidad: m['cantidad'] as int?,
        contenedor: m['contenedor'] as String?,
        articuloId: m['articulo_id'] as String?,
        articulo: m['articulo'] as String?,
        foto: m['foto_url'] as String?,
        reportadoPor: m['reportado_por'] as String? ?? '',
        reportadoEn: _f(m['reportado_en'])!,
        decision: m['decision'] as String?,
        nota: m['nota'] as String?,
      );
}
