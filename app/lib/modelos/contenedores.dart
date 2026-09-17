import 'catalogos.dart';

const tiposContenedor = {
  'GABINETE': 'Gabinete',
  'CAJON': 'Cajón',
  'GAVETA': 'Gaveta',
  'CANASTA': 'Canasta',
  'CAJA': 'Caja',
  'BOLSA': 'Bolsa',
  'REPISA': 'Repisa',
  'OTRO': 'Otro',
};

/// Un renglón de v_contenedores (público: no trae nombres de personas).
class Contenedor {
  const Contenedor({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.activo,
    required this.ruta,
    required this.articulos,
    required this.subcontenedores,
    this.padreId,
    this.padreCodigo,
    this.categoriaExclusiva,
    this.foto,
    this.nota,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String tipo;
  final String? padreId;
  final String? padreCodigo;

  /// VEX o FTC; null = mixto.
  final Categoria? categoriaExclusiva;
  final String? foto;
  final String? nota;
  final bool activo;
  final String ruta;
  final int articulos;
  final int subcontenedores;

  factory Contenedor.desdeMapa(Map<String, dynamic> m) => Contenedor(
        id: m['id'] as String,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        tipo: m['tipo'] as String,
        padreId: m['padre_id'] as String?,
        padreCodigo: m['padre_codigo'] as String?,
        categoriaExclusiva: m['categoria_exclusiva'] == null ? null : Categoria.desde(m['categoria_exclusiva'] as String),
        foto: m['foto_url'] as String?,
        nota: m['nota'] as String?,
        activo: m['activo'] as bool,
        ruta: m['ruta'] as String? ?? m['nombre'] as String,
        articulos: m['articulos'] as int? ?? 0,
        subcontenedores: m['subcontenedores'] as int? ?? 0,
      );

  String get nombreTipo => tiposContenedor[tipo] ?? tipo;

  String get nombreCategoria => categoriaExclusiva == null ? 'Mixto' : 'Solo ${categoriaExclusiva!.nombre}';

  /// ¿Puede vivir aquí un artículo de esta categoría? (VEX y FTC solo en su contenedor exclusivo.)
  bool acepta(Categoria c) =>
      categoriaExclusiva == null ? !c.esRobotica() : categoriaExclusiva == c;
}

/// Ordena los contenedores como árbol: cada padre seguido de sus hijos, con su nivel de sangría.
List<(Contenedor, int)> comoArbol(List<Contenedor> todos) {
  final hijos = <String?, List<Contenedor>>{};
  final ids = {for (final c in todos) c.id};
  for (final c in todos) {
    // Si el padre no está en la lista (filtrado), se muestra en la raíz.
    hijos.putIfAbsent(ids.contains(c.padreId) ? c.padreId : null, () => []).add(c);
  }
  for (final l in hijos.values) {
    l.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }
  final salida = <(Contenedor, int)>[];
  void recorrer(String? padre, int nivel) {
    for (final c in hijos[padre] ?? const <Contenedor>[]) {
      salida.add((c, nivel));
      if (nivel < 20) recorrer(c.id, nivel + 1);
    }
  }

  recorrer(null, 0);
  return salida;
}

class PropuestaUbicacion {
  const PropuestaUbicacion({
    required this.id,
    required this.articuloId,
    required this.articuloCodigo,
    required this.articulo,
    required this.contenedorId,
    required this.contenedorCodigo,
    required this.propuesta,
    required this.propuestaPor,
    required this.propuestaEn,
    this.actual,
    this.nota,
  });

  final String id;
  final String articuloId;
  final String articuloCodigo;
  final String articulo;
  final String? actual;
  final String contenedorId;
  final String contenedorCodigo;
  final String propuesta;
  final String? nota;
  final String propuestaPor;
  final DateTime propuestaEn;

  factory PropuestaUbicacion.desdeMapa(Map<String, dynamic> m) => PropuestaUbicacion(
        id: m['id'] as String,
        articuloId: m['articulo_id'] as String,
        articuloCodigo: m['articulo_codigo'] as String,
        articulo: m['articulo'] as String,
        actual: m['actual'] as String?,
        contenedorId: m['contenedor_id'] as String,
        contenedorCodigo: m['contenedor_codigo'] as String,
        propuesta: m['propuesta'] as String,
        nota: m['nota'] as String?,
        propuestaPor: m['propuesta_por'] as String,
        propuestaEn: DateTime.parse(m['propuesta_en'] as String),
      );
}

/// Lo que trae un QR o lo que se escribió a mano: "A-0101", "C-0012" o la dirección ".../q/C-0012".
/// Devuelve el código en mayúsculas, o null si no es de este laboratorio.
String? codigoDeEscaneo(String leido) {
  final texto = leido.trim();
  final enDireccion = RegExp(r'/q/([AaCc]-\d{1,6})\b').firstMatch(texto);
  if (enDireccion != null) return enDireccion.group(1)!.toUpperCase();
  final suelto = RegExp(r'^([AaCc])\s*-?\s*(\d{1,6})$').firstMatch(texto);
  if (suelto != null) return '${suelto.group(1)!.toUpperCase()}-${suelto.group(2)!.padLeft(4, '0')}';
  return null;
}
