import '../modelos/articulo.dart';
import '../modelos/catalogos.dart';
import '../modelos/pendientes.dart';
import '../util/documento.dart';
import '../util/texto.dart';
import 'repositorio.dart';

/// Tipos que registra reporte_registrar (bitácora y folio).
enum TipoReporte {
  inventario('INVENTARIO', 'Inventario completo', 'Inventario'),
  prestamos('PRESTAMOS', 'Préstamos abiertos', 'Prestamos abiertos'),
  incidencias('INCIDENCIAS', 'Pérdidas y daños', 'Perdidas y danos'),
  bajas('BAJAS', 'Bajas', 'Bajas'),
  movimientos('MOVIMIENTOS', 'Movimientos', 'Movimientos'),
  faltantes('FALTANTES_KITS', 'Faltantes de kits', 'Faltantes de kits'),
  actaEntrega('ACTA_ENTREGA', 'Acta de entrega-recepción', 'Acta entrega-recepcion'),
  actaInventario('ACTA_INVENTARIO', 'Acta de inventario periódico', 'Acta inventario periodico');

  const TipoReporte(this.codigo, this.nombre, this.archivo);
  final String codigo;
  final String nombre;
  final String archivo;
}

typedef Periodo = ({DateTime desde, DateTime hasta});

String textoPeriodo(Periodo p) => '${fecha(p.desde)} al ${fecha(p.hasta)}';

DateTime? _f(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

String _categoria(Object? codigo) {
  try {
    return Categoria.desde('$codigo').nombre;
  } on Object {
    return '${codigo ?? ''}';
  }
}

String _cantidad(Object? n, Object? unidad) => n == null ? '' : conUnidad(n as int, '${unidad ?? 'pieza'}');

const _origenes = {
  'APP': 'App',
  'IMPORTACION': 'Importación',
  'SOLICITUD': 'Solicitud',
  'INVENTARIO': 'Inventario periódico',
  'SIN_CONEXION': 'Sin conexión',
};

const decisionesInventario = {'AJUSTE': 'Ajustar existencia', 'INCIDENCIA': 'Reporte de pérdida', 'RECONTAR': 'Recontar'};

// --- Tablas (sin red: se pueden probar) ------------------------------------------

/// Las pestañas por categoría con las columnas del Excel de Contraloría, más Código al inicio.
List<Tabla> tablasInventario(List<Articulo> articulos, Map<String, List<String>> pendientes) {
  const columnas = [
    Columna('Código', 9),
    Columna('N.º', 5.3, numero: true),
    Columna('Artículo', 35),
    Columna('Marca / Modelo', 22.8),
    Columna('Cantidad contada', 18),
    Columna('Estado', 16),
    Columna('Subcategoría', 17.5),
    Columna('Ubicación', 24),
    Columna('Observaciones', 40),
    Columna('Pendiente / Por revisar', 28),
    Columna('Verificado en sitio', 11),
  ];
  final tablas = <Tabla>[];
  final resumen = <List<Object?>>[];
  var totalRenglones = 0, totalPendientes = 0;
  for (final c in Categoria.values) {
    final lista = articulos.where((a) => a.categoria == c).toList();
    final filas = <List<Object?>>[];
    for (final (i, a) in lista.indexed) {
      final extras = [
        if (a.prestado > 0) '${a.prestado} prestad${a.prestado == 1 ? 'o' : 'os'}',
        if (a.fueraServicio > 0) '${a.fueraServicio} fuera de servicio',
      ];
      final cantidad = a.conteoDesconocido
          ? 'Sin contar'
          : '${a.cantidadEstimada ? '~' : ''}${conUnidad(a.existencia, a.unidad)}${extras.isEmpty ? '' : ' (${extras.join(', ')})'}';
      final obs = [
        if (a.observaciones != null && a.observaciones!.trim().isNotEmpty) a.observaciones!.trim(),
        if (a.numResguardo != null) 'Resguardo ${a.numResguardo}',
        if (a.numSerie != null) 'Serie ${a.numSerie}',
        if (a.noSePresta) 'No se presta: ${a.noSePrestaMotivo ?? ''}',
      ].join('. ');
      final suyos = pendientes[a.id] ?? const [];
      filas.add([
        a.codigo,
        i + 1,
        a.nombre,
        a.marcaModelo,
        cantidad,
        a.estadoFisicoTexto ?? a.estadoFisico?.nombre,
        a.subcategoria,
        a.ubicacionRuta ?? a.ubicacionTexto,
        obs.isEmpty ? null : obs,
        suyos.isEmpty ? null : suyos.toSet().join('; '),
        a.estadoInventario == EstadoInventario.verificado ? 'Sí' : 'No',
      ]);
    }
    final conPendiente = lista.where((a) => (pendientes[a.id] ?? const []).isNotEmpty).length;
    resumen.add([resumen.length + 1, c.nombre, lista.length, conPendiente]);
    totalRenglones += lista.length;
    totalPendientes += conPendiente;
    tablas.add(Tabla(
      hoja: c.nombre,
      titulo: 'Inventario — ${c.nombre}',
      nota: 'Las cantidades con ~ son estimadas y deben confirmarse con conteo físico.',
      columnas: columnas,
      filas: filas,
      fotos: [for (final a in lista) a.fotoPrincipal],
    ));
  }
  return [
    Tabla(
      hoja: 'Resumen',
      titulo: 'Inventario físico — renglones por pestaña',
      nota: 'VEX y FTC van en pestañas separadas: el reglamento no permite mezclar piezas de otro concurso.',
      columnas: const [Columna('#', 5, numero: true), Columna('Pestaña', 26), Columna('Renglones', 12, numero: true), Columna('Con algo pendiente por revisar/contar', 22, numero: true)],
      filas: resumen,
      total: [null, 'TOTAL', totalRenglones, totalPendientes],
    ),
    ...tablas,
  ];
}

Tabla tablaPrestamos(List<Map<String, dynamic>> filas) => Tabla(
      hoja: 'Préstamos abiertos',
      titulo: 'Préstamos abiertos',
      nota: 'Primero los vencidos. De alumnos solo se muestra nombre, matrícula y grupo.',
      columnas: const [
        Columna('Código', 9), Columna('Artículo', 30), Columna('Categoría', 14), Columna('Cantidad', 12), Columna('A cargo', 26),
        Columna('Tipo', 10), Columna('Matrícula', 12), Columna('Grupo', 9), Columna('Desde', 17), Columna('Vence', 17),
        Columna('Días vencido', 8, numero: true), Columna('Autorizó', 22), Columna('Solicitud', 10),
      ],
      filas: [
        for (final m in filas)
          [
            m['codigo'], m['articulo'], _categoria(m['categoria']), _cantidad(m['cantidad'], m['unidad']), m['a_cargo'], m['tipo_persona'],
            m['matricula'], m['grupo'], _f(m['desde']), _f(m['vence_en']), m['dias_vencido'], m['autorizo'], m['folio'],
          ],
      ],
    );

Tabla tablaIncidencias(List<Map<String, dynamic>> filas, {bool soloEnRevision = false}) => Tabla(
      hoja: 'Pérdidas y daños',
      titulo: soloEnRevision ? 'Pérdidas y daños en revisión' : 'Pérdidas y daños',
      nota: soloEnRevision ? null : 'Las que siguen en revisión aparecen aunque sean de otro periodo.',
      columnas: const [
        Columna('Fecha', 17), Columna('Código', 9), Columna('Artículo', 28), Columna('Tipo', 9), Columna('Cantidad', 11), Columna('Estado', 12),
        Columna('¿Sigue en el taller?', 10), Columna('A cargo', 24), Columna('Matrícula', 12), Columna('Grupo', 8), Columna('Reportó', 20),
        Columna('Resolvió', 20), Columna('Resuelta', 17), Columna('Nota', 30), Columna('Motivo de la resolución', 26),
      ],
      filas: [
        for (final m in filas)
          if (!soloEnRevision || m['estado'] == 'En revisión')
            [
              _f(m['reportada_en']), m['codigo'], m['articulo'], m['tipo'], _cantidad(m['cantidad'], m['unidad']), m['estado'],
              m['en_taller'] as bool? ?? false, m['a_cargo'], m['matricula'], m['grupo'], m['reporto'], m['resolvio'], _f(m['resuelta_en']),
              m['nota'], m['motivo_resolucion'],
            ],
      ],
    );

Tabla tablaBajas(List<Map<String, dynamic>> filas) => Tabla(
      hoja: 'Bajas',
      titulo: 'Bajas',
      columnas: const [
        Columna('Fecha', 17), Columna('Código', 9), Columna('Artículo', 30), Columna('Categoría', 14), Columna('Cantidad', 11), Columna('Motivo', 30),
        Columna('N.º de resguardo', 14), Columna('Oficio', 16), Columna('Situación', 18), Columna('Autorizó', 22),
      ],
      filas: [
        for (final m in filas)
          [
            _f(m['fecha']), m['codigo'], m['articulo'], _categoria(m['categoria']), _cantidad(m['cantidad'], m['unidad']), m['motivo'],
            m['num_resguardo'], m['oficio'],
            m['en_tramite'] == true ? 'Oficio en trámite' : (m['total'] == true ? 'Baja total' : 'Baja parcial'),
            m['autorizo'],
          ],
      ],
    );

Tabla tablaMovimientos(List<Map<String, dynamic>> filas) => Tabla(
      hoja: 'Movimientos',
      titulo: 'Movimientos',
      columnas: const [
        Columna('Fecha', 17), Columna('Código', 9), Columna('Artículo', 30), Columna('Tipo', 16), Columna('Cantidad', 11), Columna('A cargo', 24),
        Columna('Matrícula', 12), Columna('Autorizó', 20), Columna('Registró', 20), Columna('Origen', 14), Columna('Nota', 34),
      ],
      filas: [
        for (final m in filas)
          [
            _f(m['fecha']), m['codigo'], m['articulo'], nombresMovimiento[m['tipo']] ?? m['tipo'], _cantidad(m['cantidad'], m['unidad']),
            m['a_cargo'], m['matricula'], m['autorizo'], m['registro'], _origenes[m['origen']] ?? m['origen'], m['nota'],
          ],
      ],
    );

Tabla tablaFaltantes(List<Map<String, dynamic>> filas, {bool soloFaltantes = false}) {
  final lista = [for (final m in filas) if (!soloFaltantes || '${m['estado']}'.startsWith('Faltante')) m];
  return Tabla(
    hoja: 'Faltantes de kits',
    titulo: 'Faltantes de kits',
    nota: 'Lo que traía cada kit según su lista contra lo que se encontró. Lo faltante no es parte de las existencias.',
    columnas: const [
      Columna('Kit', 26), Columna('Revisión', 30), Columna('Fecha', 17), Columna('Sección', 16), Columna('SKU', 14), Columna('Descripción', 34),
      Columna('Esperada', 9, numero: true), Columna('Encontrada', 10, numero: true), Columna('Faltante', 9, numero: true), Columna('Estado', 15),
      Columna('Nota', 30),
    ],
    filas: [
      for (final m in lista)
        [
          m['kit'], m['referencia'], _f(m['fecha']), m['seccion'], m['sku'], m['descripcion'], m['esperada'], m['encontrada'], m['faltante'],
          m['estado'], m['nota'],
        ],
    ],
    total: [
      'TOTAL', null, null, null, null, null, null, null,
      lista.fold<int>(0, (s, m) => s + (m['faltante'] as int? ?? 0)), null, null,
    ],
  );
}

// --- Documentos (con red) ------------------------------------------------------

class Reportes {
  Reportes(this.repo);

  final Repositorio repo;

  Future<Encabezado> encabezado() async => Encabezado.desdeMapa(await repo.encabezadoReporte());

  Future<List<Tabla>> _inventario() async {
    final articulos = await repo.articulos();
    final pendientes = <String, List<String>>{};
    for (final p in await repo.pendientesAbiertos()) {
      (pendientes[p.articuloId] ??= []).add(nombresTarea[p.tipo] ?? p.tipo);
    }
    return tablasInventario(articulos, pendientes);
  }

  String _archivo(TipoReporte t, Encabezado e) {
    final d = e.fechaCorte.toLocal();
    return nombreArchivo('${t.archivo} ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  /// Arma el documento de un reporte con tablas. [periodo] aplica a pérdidas, bajas y movimientos.
  Future<Documento> tablas(TipoReporte tipo, Periodo periodo, {String? folio}) async {
    final e = await encabezado();
    final lista = switch (tipo) {
      TipoReporte.inventario => [
          ...await _inventario(),
          tablaPrestamos(await repo.reportePrestamosAbiertos()),
          tablaIncidencias(await repo.reporteIncidencias(periodo.desde, periodo.hasta)),
          tablaBajas(await repo.reporteBajas(periodo.desde, periodo.hasta)),
          tablaMovimientos(await repo.reporteMovimientos(periodo.desde, periodo.hasta)),
          tablaFaltantes(await repo.reporteFaltantesKits()),
        ],
      TipoReporte.prestamos => [tablaPrestamos(await repo.reportePrestamosAbiertos())],
      TipoReporte.incidencias => [tablaIncidencias(await repo.reporteIncidencias(periodo.desde, periodo.hasta))],
      TipoReporte.bajas => [tablaBajas(await repo.reporteBajas(periodo.desde, periodo.hasta))],
      TipoReporte.movimientos => [tablaMovimientos(await repo.reporteMovimientos(periodo.desde, periodo.hasta))],
      TipoReporte.faltantes => [tablaFaltantes(await repo.reporteFaltantesKits())],
      _ => throw ArgumentError('Las actas se arman aparte.'),
    };
    final conPeriodo = tipo == TipoReporte.inventario || tipo == TipoReporte.incidencias || tipo == TipoReporte.bajas || tipo == TipoReporte.movimientos;
    return Documento(
      titulo: tipo == TipoReporte.inventario ? 'Inventario físico' : tipo.nombre,
      archivo: _archivo(tipo, e),
      encabezado: e,
      tablas: lista,
      periodo: conPeriodo ? textoPeriodo(periodo) : null,
      folio: folio,
    );
  }

  /// Solo las pestañas de inventario (el PDF para Contraloría no necesita los movimientos).
  Future<Documento> soloInventario() async {
    final e = await encabezado();
    return Documento(titulo: 'Inventario físico', archivo: _archivo(TipoReporte.inventario, e), encabezado: e, tablas: await _inventario());
  }

  static List<Firmante> firmantesInventario(Encabezado e) => [
        Firmante(papel: 'Elaboró', nombre: e.responsable ?? '', cargo: 'Responsable del ${e.laboratorio}'),
        Firmante(papel: 'Revisó', nombre: e.subadministracion ?? '', cargo: 'Sub Administración'),
      ];

  static List<Firmante> firmantesEntrega(Encabezado e) => [
        Firmante(papel: 'Entrega', nombre: e.responsable ?? '', cargo: 'Responsable del ${e.laboratorio}'),
        Firmante(papel: 'Recibe', cargo: 'Responsable del ${e.laboratorio}'),
        Firmante(papel: 'Por Sub Administración', nombre: e.subadministracion ?? '', cargo: 'Sub Administración'),
        Firmante(papel: 'Testigo'),
      ];

  Future<Documento> actaInventario(String inventarioId, List<Firmante> firmantes, String? folio) async {
    final e = await encabezado();
    final datos = await repo.reporteInventarioPeriodico(inventarioId);
    final diferencias = await repo.diferenciasDeInventario(inventarioId);
    final hallazgos = await repo.hallazgosDeInventario(inventarioId);
    final inicio = _f(datos['fecha_inicio']);
    final cierre = _f(datos['fecha_cierre']);
    final contados = diferencias.where((d) => d.contados > 0).toList();
    final conDiferencia = contados.where((d) => (d.diferencia ?? 0) != 0).length;
    final contadores = [
      for (final c in (datos['contadores'] as List? ?? const []))
        '${(c as Map)['nombre']} (${c['renglones']} renglón${c['renglones'] == 1 ? '' : 'es'})',
    ];
    final incidencias = [for (final i in (datos['incidencias'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
    return Documento(
      titulo: 'Acta de inventario periódico',
      archivo: nombreArchivo('Acta inventario ${folio ?? ''} ${datos['nombre']}'),
      encabezado: e,
      folio: folio,
      horizontal: false,
      firmantes: firmantes,
      parrafos: [
        'En las instalaciones del ${e.laboratorio} de la ${e.escuela} (${e.programa}) se llevó a cabo el inventario periódico '
            '"${datos['nombre']}", con alcance: ${datos['alcance_texto']}. Se abrió el ${inicio == null ? '' : fechaHora(inicio)} por '
            '${datos['abrio'] ?? ''}${cierre == null ? ' y a la fecha de este documento sigue abierto.' : ' y se cerró el ${fechaHora(cierre)} por ${datos['cerro'] ?? ''}.'}',
        'Se contaron ${contados.length} de ${diferencias.length} artículos del alcance; $conDiferencia presentaron diferencia entre lo registrado y lo contado, '
            'resuelta como se indica abajo. ${hallazgos.isEmpty ? 'No se registraron hallazgos.' : 'Se registraron ${hallazgos.length} hallazgos.'}',
        if (contadores.isNotEmpty) 'Participaron en el conteo: ${contadores.join(', ')}.',
      ],
      tablas: [
        Tabla(
          hoja: 'Resultado',
          titulo: 'Resultado por artículo',
          columnas: const [
            Columna('Código', 9), Columna('Artículo', 30), Columna('Ubicación', 20), Columna('Registrado', 9, numero: true),
            Columna('Contado', 9, numero: true), Columna('Diferencia', 9, numero: true), Columna('Decisión', 16), Columna('Nota', 24),
          ],
          filas: [
            for (final d in diferencias)
              [
                d.codigo, d.nombre, d.ruta, d.sistema, d.contados == 0 ? null : d.fisico, d.contados == 0 ? null : d.diferencia,
                d.contados == 0 ? 'Sin contar' : (d.diferencia == 0 ? 'Coincide' : decisionesInventario[d.decision] ?? d.decision), d.nota,
              ],
          ],
        ),
        Tabla(
          hoja: 'Reportes de pérdida',
          titulo: 'Reportes de pérdida levantados en el inventario',
          columnas: const [Columna('Código', 9), Columna('Artículo', 30), Columna('Cantidad', 9, numero: true), Columna('Estado', 14), Columna('Nota', 30)],
          filas: [for (final i in incidencias) [i['codigo'], i['articulo'], i['cantidad'], _estadoIncidencia(i['estado']), i['nota']]],
        ),
        Tabla(
          hoja: 'Hallazgos',
          titulo: 'Hallazgos',
          columnas: const [
            Columna('Descripción', 34), Columna('Cantidad', 9, numero: true), Columna('Contenedor', 18), Columna('Artículo', 22),
            Columna('Reportó', 18), Columna('Decisión', 14), Columna('Nota', 22),
          ],
          filas: [for (final h in hallazgos) [h.descripcion, h.cantidad, h.contenedor, h.articulo, h.reportadoPor, h.decision, h.nota]],
        ),
      ],
    );
  }

  Future<Documento> actaEntrega({
    required String motivo,
    required String lugar,
    required String? observaciones,
    required List<Firmante> firmantes,
    required String? folio,
    required Periodo periodo,
  }) async {
    final e = await encabezado();
    final inventario = await _inventario();
    final prestamos = await repo.reportePrestamosAbiertos();
    final incidencias = await repo.reporteIncidencias(periodo.desde, periodo.hasta);
    final faltantes = await repo.reporteFaltantesKits();
    final entrega = firmantes.where((f) => f.papel.toLowerCase().startsWith('entrega')).firstOrNull;
    final recibe = firmantes.where((f) => f.papel.toLowerCase().startsWith('recibe')).firstOrNull;
    final renglones = inventario.skip(1).fold<int>(0, (s, t) => s + t.filas.length);
    final vencidos = prestamos.where((p) => p['vencido'] == true).length;
    final enRevision = incidencias.where((i) => i['estado'] == 'En revisión').length;
    final conFaltante = faltantes.where((f) => '${f['estado']}'.startsWith('Faltante')).length;
    return Documento(
      titulo: 'Acta de entrega-recepción',
      archivo: nombreArchivo('Acta entrega-recepcion ${folio ?? ''}'),
      encabezado: e,
      folio: folio,
      horizontal: true,
      firmantes: firmantes,
      parrafos: [
        'En $lugar, siendo el ${fechaHora(e.fechaCorte)}, en las instalaciones del ${e.laboratorio} de la ${e.escuela} '
            '(${e.programa}), se levanta la presente acta de entrega-recepción con folio ${folio ?? ''}, con motivo de: $motivo.',
        '${_quien(entrega, 'Quien entrega')} hace entrega a ${_quien(recibe, 'quien recibe')} de los bienes, equipo, herramienta y material del laboratorio '
            'que se detallan en los anexos de esta acta, con las existencias registradas al corte indicado.',
        'Al corte: $renglones renglones de inventario en ${Categoria.values.length} categorías; ${prestamos.length} préstamos abiertos '
            '($vencidos vencidos); $enRevision reportes de pérdida o daño en revisión; $conFaltante renglones de kits con faltante '
            '(material que se compró y no se ha localizado; no forma parte de las existencias).',
        if (observaciones != null && observaciones.trim().isNotEmpty) 'Observaciones: ${observaciones.trim()}',
        'Quien recibe manifiesta que revisó los anexos y que cualquier diferencia que encuentre en el conteo físico la reportará por escrito. '
            'Leída la presente, la firman de conformidad quienes en ella intervienen.',
      ],
      tablas: [
        ...inventario,
        tablaPrestamos(prestamos),
        tablaIncidencias(incidencias, soloEnRevision: true),
        tablaFaltantes(faltantes, soloFaltantes: true),
      ],
    );
  }

  static String _quien(Firmante? f, String siNo) =>
      f == null || f.nombre.trim().isEmpty ? siNo : '${f.nombre.trim()}${f.cargo.trim().isEmpty ? '' : ', ${f.cargo.trim()},'}';

  static String _estadoIncidencia(Object? e) => switch (e) {
        'PENDIENTE' => 'En revisión',
        'CONFIRMADA' => 'Confirmada',
        'DESCARTADA' => 'Descartada',
        _ => '${e ?? ''}',
      };
}

/// Consulta rápida: lo que conviene atender hoy, sin descargar nada.
class ConsultaRapida {
  const ConsultaRapida({required this.vencidos, required this.bajoMinimo, required this.sinVerificar, required this.totales, required this.pendientes});

  final List<Map<String, dynamic>> vencidos;
  final List<Articulo> bajoMinimo;

  /// Por categoría: artículos que no están verificados.
  final Map<Categoria, List<Articulo>> sinVerificar;
  final Map<Categoria, int> totales;
  final int pendientes;

  static ConsultaRapida armar(List<Articulo> articulos, List<Map<String, dynamic>> prestamos, List<PendienteAbierto> pendientes) =>
      ConsultaRapida(
        vencidos: [for (final p in prestamos) if (p['vencido'] == true) p],
        bajoMinimo: [
          for (final a in articulos)
            if (a.esConsumible && a.minimoReposicion != null && a.existencia - a.prestado - a.fueraServicio <= a.minimoReposicion!) a,
        ],
        sinVerificar: {
          for (final c in Categoria.values) c: [for (final a in articulos) if (a.categoria == c && a.estadoInventario != EstadoInventario.verificado) a],
        },
        totales: {for (final c in Categoria.values) c: articulos.where((a) => a.categoria == c).length},
        pendientes: pendientes.length,
      );
}
