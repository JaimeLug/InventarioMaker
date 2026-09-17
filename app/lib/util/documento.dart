/// Un reporte armado en el dispositivo: el mismo contenido sale en Excel o en PDF.
library;

class Encabezado {
  const Encabezado({
    required this.escuela,
    required this.programa,
    required this.laboratorio,
    required this.generadoPor,
    required this.fechaCorte,
    this.responsable,
    this.subadministracion,
    this.logoUrl,
  });

  final String escuela;
  final String programa;
  final String laboratorio;
  final String? responsable;
  final String? subadministracion;
  final String generadoPor;
  final DateTime fechaCorte;

  /// Lugar reservado para el logo oficial (se pone en Ajustes cuando llegue).
  final String? logoUrl;

  factory Encabezado.desdeMapa(Map<String, dynamic> m) => Encabezado(
        escuela: m['escuela'] as String? ?? 'Escuela Preparatoria Número 13',
        programa: m['programa'] as String? ?? 'Programa Renacimiento Maya',
        laboratorio: m['laboratorio'] as String? ?? 'Laboratorio Maker',
        responsable: m['responsable'] as String?,
        subadministracion: m['subadministracion'] as String?,
        generadoPor: m['generado_por'] as String? ?? '',
        fechaCorte: DateTime.tryParse('${m['fecha_corte']}') ?? DateTime.now(),
        logoUrl: (m['logo_url'] as String?)?.trim().isEmpty ?? true ? null : m['logo_url'] as String,
      );
}

class Columna {
  const Columna(this.titulo, this.ancho, {this.numero = false});

  final String titulo;

  /// Ancho en caracteres (Excel); en el PDF se usa como proporción.
  final double ancho;
  final bool numero;
}

class Tabla {
  Tabla({
    required this.hoja,
    required this.titulo,
    required this.columnas,
    required this.filas,
    this.nota,
    this.total,
    this.fotos,
  });

  /// Nombre de la pestaña del Excel (máximo 31 letras).
  final String hoja;
  final String titulo;
  final String? nota;
  final List<Columna> columnas;
  final List<List<Object?>> filas;
  final List<Object?>? total;

  /// Ruta de la foto de cada renglón (solo el PDF con miniaturas la usa).
  final List<String?>? fotos;
}

class Firmante {
  Firmante({required this.papel, this.nombre = '', this.cargo = ''});

  String papel;
  String nombre;
  String cargo;

  Map<String, String> aMapa() => {'papel': papel, 'nombre': nombre, 'cargo': cargo};

  static Firmante desdeMapa(Map<String, dynamic> m) =>
      Firmante(papel: m['papel'] as String? ?? '', nombre: m['nombre'] as String? ?? '', cargo: m['cargo'] as String? ?? '');
}

class Documento {
  Documento({
    required this.titulo,
    required this.archivo,
    required this.encabezado,
    this.tablas = const [],
    this.parrafos = const [],
    this.firmantes = const [],
    this.folio,
    this.periodo,
    this.horizontal = true,
  });

  final String titulo;

  /// Nombre del archivo sin extensión.
  final String archivo;
  final Encabezado encabezado;
  final List<Tabla> tablas;
  final List<String> parrafos;
  final List<Firmante> firmantes;
  final String? folio;
  final String? periodo;
  final bool horizontal;
}

/// Del 1 de agosto al 31 de julio: el ciclo escolar que contiene [dia].
({DateTime desde, DateTime hasta}) cicloEscolar(DateTime dia) {
  final inicio = dia.month >= 8 ? dia.year : dia.year - 1;
  return (desde: DateTime(inicio, 8, 1), hasta: DateTime(inicio + 1, 7, 31));
}

/// La letra estándar de PDF solo trae los símbolos latinos: se cambian los demás.
String latino(String t) => t
    .replaceAll('›', '>')
    .replaceAll('→', '->')
    .replaceAll('…', '...')
    .replaceAll('•', '·')
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

/// Nombre de archivo sin acentos ni símbolos: "Inventario 2026-09-17".
String nombreArchivo(String t) => t
    .replaceAll(RegExp('[áÁ]'), 'a')
    .replaceAll(RegExp('[éÉ]'), 'e')
    .replaceAll(RegExp('[íÍ]'), 'i')
    .replaceAll(RegExp('[óÓ]'), 'o')
    .replaceAll(RegExp('[úÚüÜ]'), 'u')
    .replaceAll(RegExp('[ñÑ]'), 'n')
    .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
