import '../util/texto.dart';
import 'catalogos.dart';

/// Un renglón de la vista pública v_inventario: datos del artículo y sus cifras.
class Articulo {
  Articulo({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.categoria,
    required this.unidad,
    required this.estadoInventario,
    required this.etiquetado,
    required this.esConsumible,
    required this.activo,
    required this.cantidadEstimada,
    required this.conteoDesconocido,
    required this.existencia,
    required this.prestado,
    required this.fueraServicio,
    required this.apartado,
    required this.retenido,
    required this.disponible,
    required this.prestable,
    required this.pendientesAbiertos,
    this.refFoto,
    this.marcaModelo,
    this.subcategoria,
    this.cantidadTexto,
    this.estadoFisico,
    this.estadoFisicoTexto,
    this.ubicacionRuta,
    this.ubicacionTexto,
    this.numResguardo,
    this.numSerie,
    this.observaciones,
    this.minimoReposicion,
    this.prestadoHasta,
    this.fotoPrincipal,
    this.bajaOficio,
    this.bajaEnTramite = false,
  });

  final String id;
  final String codigo;
  final int? refFoto;
  final String nombre;
  final String? marcaModelo;
  final Categoria categoria;
  final String? subcategoria;
  final String unidad;
  final String? cantidadTexto;
  final bool cantidadEstimada;
  final bool conteoDesconocido;
  final EstadoInventario estadoInventario;
  final EstadoFisico? estadoFisico;
  final String? estadoFisicoTexto;
  final Etiquetado etiquetado;
  final String? ubicacionRuta;
  final String? ubicacionTexto;
  final String? numResguardo;
  final String? numSerie;
  final String? observaciones;
  final bool esConsumible;
  final int? minimoReposicion;
  final bool activo;
  final int existencia;
  final int prestado;
  final int fueraServicio;
  final int apartado;
  final int retenido;
  final int disponible;
  final bool prestable;
  final DateTime? prestadoHasta;
  final int pendientesAbiertos;

  /// Ruta de la foto principal dentro del almacén.
  final String? fotoPrincipal;

  final String? bajaOficio;

  /// Dado de baja, con resguardo y sin número de oficio todavía.
  final bool bajaEnTramite;

  factory Articulo.desdeMapa(Map<String, dynamic> m) => Articulo(
        id: m['id'] as String,
        codigo: m['codigo'] as String,
        refFoto: m['ref_foto'] as int?,
        nombre: m['nombre'] as String,
        marcaModelo: _sinMarca(m['marca_modelo'] as String?),
        categoria: Categoria.desde(m['categoria'] as String),
        subcategoria: m['subcategoria'] as String?,
        unidad: m['unidad'] as String,
        cantidadTexto: m['cantidad_texto'] as String?,
        cantidadEstimada: m['cantidad_estimada'] as bool,
        conteoDesconocido: m['conteo_desconocido'] as bool,
        estadoInventario: EstadoInventario.desde(m['estado_inventario'] as String),
        estadoFisico: EstadoFisico.desde(m['estado_fisico'] as String?),
        estadoFisicoTexto: m['estado_fisico_texto'] as String?,
        etiquetado: Etiquetado.desde(m['etiquetado'] as String),
        ubicacionRuta: m['ubicacion_ruta'] as String?,
        ubicacionTexto: m['ubicacion_texto'] as String?,
        numResguardo: m['num_resguardo'] as String?,
        numSerie: m['num_serie'] as String?,
        observaciones: m['observaciones'] as String?,
        esConsumible: m['es_consumible'] as bool,
        minimoReposicion: m['minimo_reposicion'] as int?,
        activo: m['activo'] as bool,
        existencia: m['existencia'] as int,
        prestado: m['prestado'] as int,
        fueraServicio: m['fuera_servicio'] as int,
        apartado: m['apartado'] as int,
        retenido: m['retenido'] as int,
        disponible: m['disponible'] as int,
        prestable: m['prestable'] as bool,
        prestadoHasta: m['prestado_hasta'] == null ? null : DateTime.parse(m['prestado_hasta'] as String),
        pendientesAbiertos: m['pendientes_abiertos'] as int,
        fotoPrincipal: m['foto_principal_url'] as String?,
        bajaOficio: m['baja_oficio'] as String?,
        bajaEnTramite: m['baja_en_tramite'] as bool? ?? false,
      );

  /// En el Excel "s/m" significa sin marca: no se muestra como si fuera una.
  static String? _sinMarca(String? marca) =>
      marca == null || RegExp(r'^\s*s\s*/\s*m\s*$', caseSensitive: false).hasMatch(marca) ? null : marca;

  /// "~14 piezas" si es estimada, "Sin contar" si nunca se contó.
  String get cantidadMostrada {
    if (conteoDesconocido) return 'Sin contar';
    return '${cantidadEstimada ? '~' : ''}${conUnidad(existencia, unidad)}';
  }

  /// Qué decir en lugar del número cuando no se puede prestar.
  String get disponibilidad {
    if (estadoInventario == EstadoInventario.sinClasificar) return 'Sin clasificar: no usar';
    if (conteoDesconocido) return 'Se presta hasta contarlo';
    if (!prestable) return 'No disponible';
    if (disponible <= 0) return 'Nada disponible';
    return '${cantidadEstimada ? '~' : ''}$disponible disponible${disponible == 1 ? '' : 's'}';
  }

  String? get ubicacion => ubicacionRuta ?? ubicacionTexto;

  /// Texto donde se busca: nombre, marca, código, serie, resguardo, observaciones.
  late final String textoBusqueda = normalizar(
    [nombre, marcaModelo, codigo, refFoto?.toString(), numSerie, numResguardo, subcategoria, observaciones]
        .whereType<String>()
        .join(' '),
  );
}
