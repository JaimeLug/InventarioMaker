import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/reportes.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../util/documento.dart';
import '../../util/documento_excel.dart';
import '../../util/documento_pdf.dart';
import '../../util/guardar_archivo.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

/// Pide acceso, registra el reporte (y su folio), lo arma en el dispositivo y lo guarda.
Future<void> generarReporte(
  BuildContext context,
  WidgetRef ref, {
  required TipoReporte tipo,
  required bool pdf,
  required Future<Documento> Function(Reportes reportes, String? folio) armar,
  Map<String, dynamic> parametros = const {},
  bool conFotos = false,
  Requisito requisito = Requisito.administracion,
  void Function(String? estado)? estado,
}) async {
  try {
    estado?.call('Juntando la información…');
    final listo = await conAcceso<(String, Uint8List)>(
      context,
      ref,
      descripcion: 'generar "${tipo.nombre}"',
      requisito: requisito,
      accion: () async {
        final repo = ref.read(repositorioProvider);
        final folio = await repo.registrarReporte(tipo.codigo, pdf ? 'PDF' : 'EXCEL', parametros);
        final doc = await armar(Reportes(repo), folio);
        estado?.call(pdf ? 'Armando el PDF…' : 'Armando el Excel…');
        final bytes = pdf
            ? await documentoAPdf(doc,
                conFotos: conFotos, urlFoto: repo.urlFoto, progreso: (h, t) => estado?.call('Bajando fotos: $h de $t…'))
            : documentoAExcel(doc);
        return (doc.archivo, bytes);
      },
    );
    if (listo == null) return;
    estado?.call('Guardando…');
    final guardado = await guardarArchivo(listo.$2, listo.$1, pdf: pdf);
    if (guardado && context.mounted) avisar(context, 'Listo: ${listo.$1}.${pdf ? 'pdf' : 'xlsx'}');
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  } finally {
    estado?.call(null);
  }
}

class ReportesPantalla extends ConsumerStatefulWidget {
  const ReportesPantalla({super.key});

  @override
  ConsumerState<ReportesPantalla> createState() => _ReportesPantallaState();
}

class _ReportesPantallaState extends ConsumerState<ReportesPantalla> {
  Periodo _periodo = cicloEscolar(DateTime.now());
  String? _estado;
  bool _conFotos = false;
  bool _soloInventario = false;

  Future<void> _generar(TipoReporte tipo, bool pdf) => generarReporte(
        context,
        ref,
        tipo: tipo,
        pdf: pdf,
        conFotos: _conFotos && pdf,
        parametros: {
          'desde': _periodo.desde.toIso8601String().substring(0, 10),
          'hasta': _periodo.hasta.toIso8601String().substring(0, 10),
          if (tipo == TipoReporte.inventario) 'solo_inventario': _soloInventario,
          if (pdf && tipo == TipoReporte.inventario) 'miniaturas': _conFotos,
        },
        armar: (r, folio) => tipo == TipoReporte.inventario && _soloInventario ? r.soloInventario() : r.tablas(tipo, _periodo, folio: folio),
        estado: (e) {
          if (mounted) setState(() => _estado = e);
        },
      );

  Future<void> _cambiarPeriodo() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      initialDateRange: DateTimeRange(start: _periodo.desde, end: _periodo.hasta),
      helpText: 'Periodo del reporte',
    );
    if (rango != null) setState(() => _periodo = (desde: rango.start, hasta: rango.end));
  }

  Future<void> _actaInventario() async {
    final lista = await conAcceso(context, ref,
        descripcion: 'elegir el inventario', requisito: Requisito.administracion, accion: () => ref.read(repositorioProvider).inventarios());
    if (lista == null || !mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿De qué inventario?'),
        children: [
          if (lista.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay inventarios periódicos.')),
          for (final i in lista)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i.id),
              child: ListTile(
                title: Text(i.nombre),
                subtitle: Text(i.abierto ? 'Abierto desde ${fecha(i.fechaInicio)}' : 'Cerrado el ${fecha(i.fechaCierre ?? i.fechaInicio)}'),
              ),
            ),
        ],
      ),
    );
    if (id != null && mounted) context.push('/acta-inventario/$id');
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider).value;
    final ciclo = cicloEscolar(DateTime.now());
    final esCiclo = _periodo.desde == ciclo.desde && _periodo.hasta == ciclo.hasta;
    final ocupado = _estado != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: const [BarraSesion()],
        bottom: ocupado ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: Centrado(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (ocupado) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_estado!, style: Theme.of(context).textTheme.bodyLarge)),
          Card(
            child: ListTile(
              leading: const Icon(Icons.date_range),
              title: Text(esCiclo ? 'Ciclo escolar ${ciclo.desde.year}-${ciclo.hasta.year}' : 'Periodo elegido'),
              subtitle: Text('${textoPeriodo(_periodo)}\nAplica a pérdidas y daños, bajas y movimientos.'),
              isThreeLine: true,
              trailing: Wrap(spacing: 4, children: [
                if (!esCiclo) IconButton(tooltip: 'Volver al ciclo actual', icon: const Icon(Icons.restart_alt), onPressed: () => setState(() => _periodo = ciclo)),
                IconButton(tooltip: 'Cambiar periodo', icon: const Icon(Icons.edit_calendar), onPressed: _cambiarPeriodo),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.bolt),
                title: const Text('Consulta rápida'),
                subtitle: const Text('Vencidos, consumibles bajo mínimo y lo que falta verificar'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/consulta-rapida'),
              ),
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('Revisiones de kits'),
                subtitle: const Text('Lo que se encontró de cada kit contra su lista de fábrica'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/revisiones-kit'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Descargar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          _Reporte(
            titulo: 'Inventario (Contraloría)',
            descripcion: _soloInventario
                ? 'Resumen y una pestaña por categoría, con código y ubicación.'
                : 'Resumen, una pestaña por categoría (con código y ubicación), préstamos abiertos, pérdidas y daños, bajas, movimientos y faltantes de kits.',
            ocupado: ocupado,
            generar: (pdf) => _generar(TipoReporte.inventario, pdf),
            opciones: [
              SwitchListTile(
                dense: true,
                title: const Text('Solo las pestañas del inventario'),
                value: _soloInventario,
                onChanged: (v) => setState(() => _soloInventario = v),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('PDF con miniaturas de las fotos'),
                subtitle: const Text('Tarda más y el archivo pesa más'),
                value: _conFotos,
                onChanged: (v) => setState(() => _conFotos = v),
              ),
            ],
          ),
          _Reporte(
              titulo: 'Préstamos abiertos',
              descripcion: 'Quién tiene qué y desde cuándo; primero los vencidos.',
              ocupado: ocupado,
              generar: (pdf) => _generar(TipoReporte.prestamos, pdf)),
          _Reporte(
              titulo: 'Pérdidas y daños',
              descripcion: 'Del periodo, más las que siguen en revisión.',
              ocupado: ocupado,
              generar: (pdf) => _generar(TipoReporte.incidencias, pdf)),
          _Reporte(
              titulo: 'Bajas', descripcion: 'Con número de resguardo y oficio.', ocupado: ocupado, generar: (pdf) => _generar(TipoReporte.bajas, pdf)),
          _Reporte(
              titulo: 'Movimientos',
              descripcion: 'Todo lo que entró, salió o se ajustó en el periodo.',
              ocupado: ocupado,
              generar: (pdf) => _generar(TipoReporte.movimientos, pdf)),
          _Reporte(
              titulo: 'Faltantes de kits',
              descripcion: 'Lo que traía cada kit según su lista y no se ha encontrado.',
              ocupado: ocupado,
              generar: (pdf) => _generar(TipoReporte.faltantes, pdf)),
          const SizedBox(height: 12),
          Text('Actas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Acta de inventario periódico'),
                subtitle: const Text('Con folio, resultado del conteo y firmas'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !ocupado,
                onTap: _actaInventario,
              ),
              ListTile(
                leading: const Icon(Icons.handshake_outlined),
                title: const Text('Acta de entrega-recepción'),
                subtitle: Text(sesion?.rol == Rol.subadmin ? 'Con folio, inventario completo en anexos y firmas' : 'La genera sub administración'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !ocupado && sesion?.rol == Rol.subadmin,
                onTap: () => context.push('/acta-entrega'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            'Los reportes se arman en este dispositivo y no se guardan en el servidor; solo queda anotado en la bitácora quién los generó. '
            'Nunca incluyen fotos de identificaciones ni datos de contacto.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}

class _Reporte extends StatelessWidget {
  const _Reporte({required this.titulo, required this.descripcion, required this.generar, required this.ocupado, this.opciones = const []});

  final String titulo;
  final String descripcion;
  final Future<void> Function(bool pdf) generar;
  final bool ocupado;
  final List<Widget> opciones;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(title: Text(titulo), subtitle: Text(descripcion)),
            ...opciones,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(icon: const Icon(Icons.table_view), label: const Text('Excel'), onPressed: ocupado ? null : () => generar(false)),
                OutlinedButton.icon(icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF'), onPressed: ocupado ? null : () => generar(true)),
              ]),
            ),
          ]),
        ),
      );
}

// --- Consulta rápida ---------------------------------------------------------------

class ConsultaRapidaPantalla extends ConsumerWidget {
  const ConsultaRapidaPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consulta rápida'), actions: const [BarraSesion()]),
      body: Centrado(
        child: CargaConAcceso<ConsultaRapida>(
          descripcion: 'ver la consulta rápida',
          requisito: Requisito.administracion,
          cargar: (repo) async => ConsultaRapida.armar(await repo.articulos(), await repo.reportePrestamosAbiertos(), await repo.pendientesAbiertos()),
          construir: (context, c, _) {
            final tema = Theme.of(context);
            final totalSin = c.sinVerificar.values.fold<int>(0, (s, l) => s + l.length);
            final total = c.totales.values.fold<int>(0, (s, n) => s + n);
            return ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: ExpansionTile(
                  initiallyExpanded: c.vencidos.isNotEmpty,
                  leading: Icon(Icons.alarm, color: c.vencidos.isEmpty ? null : tema.colorScheme.error),
                  title: Text('Préstamos vencidos: ${c.vencidos.length}'),
                  children: [
                    if (c.vencidos.isEmpty) const ListTile(title: Text('Nada vencido.')),
                    for (final v in c.vencidos)
                      ListTile(
                        title: Text('${v['articulo']} · ${conUnidad(v['cantidad'] as int, '${v['unidad']}')}'),
                        subtitle: Text([
                          '${v['a_cargo'] ?? ''}${v['matricula'] == null ? '' : ' (${v['matricula']}${v['grupo'] == null ? '' : ', ${v['grupo']}'})'}',
                          if (v['vence_en'] != null) 'Venció el ${fecha(DateTime.parse('${v['vence_en']}'))} · ${v['dias_vencido']} día${v['dias_vencido'] == 1 ? '' : 's'}',
                        ].join('\n')),
                      ),
                    if (c.vencidos.isNotEmpty)
                      TextButton(onPressed: () => context.push('/prestamos-abiertos'), child: const Text('Ver préstamos abiertos')),
                  ],
                ),
              ),
              Card(
                child: ExpansionTile(
                  initiallyExpanded: c.bajoMinimo.isNotEmpty,
                  leading: Icon(Icons.inventory_outlined, color: c.bajoMinimo.isEmpty ? null : Avisos.pendiente),
                  title: Text('Consumibles en su mínimo o abajo: ${c.bajoMinimo.length}'),
                  children: [
                    if (c.bajoMinimo.isEmpty) const ListTile(title: Text('Ninguno (solo cuentan los que tienen mínimo definido).')),
                    for (final a in c.bajoMinimo)
                      ListTile(
                        title: Text(a.nombre),
                        subtitle: Text('Quedan ${conUnidad(a.existencia - a.prestado - a.fueraServicio, a.unidad)} · mínimo ${a.minimoReposicion}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/articulo/${a.id}'),
                      ),
                  ],
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: Text('Sin verificar: $totalSin de $total'),
                      subtitle: LinearProgressIndicator(value: total == 0 ? 0 : (total - totalSin) / total),
                    ),
                    for (final cat in Categoria.values)
                      if ((c.totales[cat] ?? 0) > 0)
                        ExpansionTile(
                          title: Text('${cat.nombre}: ${c.sinVerificar[cat]!.length} de ${c.totales[cat]} sin verificar'),
                          subtitle: LinearProgressIndicator(value: (c.totales[cat]! - c.sinVerificar[cat]!.length) / c.totales[cat]!),
                          children: [
                            for (final a in c.sinVerificar[cat]!)
                              ListTile(
                                dense: true,
                                title: Text(a.nombre),
                                subtitle: Text('${a.codigo} · ${a.estadoInventario.nombre}${a.ubicacionRuta == null ? '' : ' · ${a.ubicacionRuta}'}'),
                                onTap: () => context.push('/articulo/${a.id}'),
                              ),
                          ],
                        ),
                  ]),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text('Pendientes abiertos: ${c.pendientes}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pendientes'),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// --- Revisiones de kits --------------------------------------------------------------

class RevisionesKitPantalla extends ConsumerStatefulWidget {
  const RevisionesKitPantalla({super.key});

  @override
  ConsumerState<RevisionesKitPantalla> createState() => _RevisionesKitPantallaState();
}

class _RevisionesKitPantallaState extends ConsumerState<RevisionesKitPantalla> {
  var _llave = UniqueKey();

  Future<void> _nueva() async {
    final repo = ref.read(repositorioProvider);
    final plantillas = await conAcceso(context, ref,
        descripcion: 'revisar un kit', requisito: Requisito.administracion, accion: () => repo.plantillasKit());
    if (plantillas == null || !mounted) return;
    String? plantilla = plantillas.firstOrNull?.id;
    final kits = TextEditingController(text: '1');
    final nombre = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nueva revisión de kit'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: plantilla,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Lista de contenido'),
              items: [for (final p in plantillas) DropdownMenuItem(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => plantilla = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: kits,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '¿Cuántos kits se compraron?'),
            ),
            const SizedBox(height: 12),
            TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre (opcional)', helperText: 'Ejemplo: compra 2024')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: plantilla == null ? null : () => Navigator.pop(context, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await conAcceso(context, ref,
          descripcion: 'crear la revisión',
          requisito: Requisito.administracion,
          accion: () => repo.crearRevisionKit(plantilla!, int.tryParse(kits.text) ?? 1, nombre.text.trim().isEmpty ? null : nombre.text.trim()));
      if (r != null && mounted) {
        await context.push('/revision-kit/${r['id']}');
        setState(() => _llave = UniqueKey());
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Revisiones de kits'), actions: const [BarraSesion()]),
        floatingActionButton: FloatingActionButton.extended(onPressed: _nueva, icon: const Icon(Icons.add), label: const Text('Nueva revisión')),
        body: Centrado(
          child: CargaConAcceso<List<Map<String, dynamic>>>(
            key: _llave,
            descripcion: 'ver las revisiones de kits',
            requisito: Requisito.administracion,
            cargar: (repo) => repo.revisionesKit(),
            construir: (context, lista, recargar) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              const ListTile(
                title: Text('Se anota lo que se encontró de cada kit contra su lista de fábrica. No cambia las existencias: sirve para el reporte de faltantes.'),
              ),
              if (lista.isEmpty) const ListTile(title: Text('Todavía no hay revisiones.')),
              for (final r in lista)
                ListTile(
                  title: Text('${r['nombre']}'),
                  subtitle: Text([
                    '${r['plantilla']} · ${r['kits']} kit${r['kits'] == 1 ? '' : 's'}',
                    'Revisados ${r['revisados']} de ${r['renglones']} renglones · con faltante ${r['con_faltante']}',
                    if (r['actualizada_en'] != null) 'Última vez: ${fechaHora(DateTime.parse('${r['actualizada_en']}'))}${r['actualizada_por'] == null ? '' : ' por ${r['actualizada_por']}'}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await context.push('/revision-kit/${r['id']}');
                    await recargar();
                  },
                ),
            ]),
          ),
        ),
      );
}

class RevisionKitPantalla extends StatelessWidget {
  const RevisionKitPantalla({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Revisión de kit'), actions: const [BarraSesion()]),
        body: Centrado(
          child: CargaConAcceso<Map<String, dynamic>>(
            descripcion: 'revisar el kit',
            requisito: Requisito.administracion,
            cargar: (repo) => repo.detalleRevisionKit(id),
            construir: (context, datos, _) => _EditorRevision(datos: datos),
          ),
        ),
      );
}

class _LineaEditable {
  _LineaEditable(this.datos)
      : encontrada = TextEditingController(text: datos['encontrada']?.toString() ?? ''),
        noAplica = datos['no_aplica'] as bool? ?? false,
        nota = datos['nota'] as String? ?? '';

  final Map<String, dynamic> datos;
  final TextEditingController encontrada;
  bool noAplica;
  String nota;
}

class _EditorRevision extends ConsumerStatefulWidget {
  const _EditorRevision({required this.datos});

  final Map<String, dynamic> datos;

  @override
  ConsumerState<_EditorRevision> createState() => _EditorRevisionState();
}

class _EditorRevisionState extends ConsumerState<_EditorRevision> {
  late final TextEditingController _kits = TextEditingController(text: '${widget.datos['kits']}');
  late final TextEditingController _nota = TextEditingController(text: widget.datos['nota'] as String? ?? '');
  late final List<_LineaEditable> _lineas = [
    for (final l in (widget.datos['lineas'] as List)) _LineaEditable(Map<String, dynamic>.from(l as Map)),
  ];
  bool _guardando = false;

  @override
  void dispose() {
    _kits.dispose();
    _nota.dispose();
    for (final l in _lineas) {
      l.encontrada.dispose();
    }
    super.dispose();
  }

  int get _numKits => int.tryParse(_kits.text) ?? 1;

  String _estado(_LineaEditable l) {
    if (l.noAplica) return 'No aplica';
    final n = int.tryParse(l.encontrada.text);
    final porKit = l.datos['por_kit'] as int?;
    if (n == null) return 'Sin revisar';
    if (porKit == null) return 'Revisado';
    final esperada = porKit * _numKits;
    if (n >= esperada) return 'Completo';
    return 'Faltan ${esperada - n}';
  }

  Future<void> _editarNota(_LineaEditable l) async {
    final c = TextEditingController(text: l.nota);
    final texto = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${l.datos['descripcion']}'),
        content: TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(labelText: 'Nota')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Listo')),
        ],
      ),
    );
    c.dispose();
    if (texto != null) setState(() => l.nota = texto);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final lineas = [
        for (final l in _lineas)
          {
            'plantilla_linea_id': l.datos['plantilla_linea_id'],
            'encontrada': l.noAplica ? null : int.tryParse(l.encontrada.text),
            'no_aplica': l.noAplica,
            'nota': l.nota,
          },
      ];
      final ok = await conAcceso(context, ref,
          descripcion: 'guardar la revisión',
          requisito: Requisito.administracion,
          accion: () => ref.read(repositorioProvider).guardarRevisionKit('${widget.datos['id']}', _numKits, lineas, _nota.text));
      if (ok != null && mounted) avisar(context, 'Revisión guardada.');
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final plantilla = Map<String, dynamic>.from(widget.datos['plantilla'] as Map);
    String? seccion;
    final hijos = <Widget>[];
    for (final l in _lineas) {
      if (l.datos['seccion'] != seccion) {
        seccion = l.datos['seccion'] as String?;
        if (seccion != null) {
          hijos.add(Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(seccion, style: tema.textTheme.titleSmall)));
        }
      }
      final porKit = l.datos['por_kit'] as int?;
      final estado = _estado(l);
      hijos.add(ListTile(
        title: Text('${l.datos['descripcion']}'),
        subtitle: Text([
          [if (l.datos['sku'] != null) '${l.datos['sku']}', porKit == null ? 'Cantidad: varios' : 'Esperadas: ${porKit * _numKits} ($porKit por kit)'].join(' · '),
          estado,
          if (l.nota.isNotEmpty) 'Nota: ${l.nota}' else if (l.datos['nota_plantilla'] != null) '${l.datos['nota_plantilla']}',
        ].join('\n')),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 64,
            child: TextField(
              controller: l.encontrada,
              enabled: !l.noAplica,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Hay', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'nota') {
                _editarNota(l);
              } else {
                setState(() => l.noAplica = !l.noAplica);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'aplica', child: Text(l.noAplica ? 'Sí aplica' : 'No aplica (no venía o se sustituyó)')),
              const PopupMenuItem(value: 'nota', child: Text('Nota')),
            ],
          ),
        ]),
      ));
    }
    return Stack(children: [
      ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        ListTile(
          title: Text('${widget.datos['nombre']}', style: tema.textTheme.titleMedium),
          subtitle: Text('${plantilla['nombre']}${plantilla['sku'] == null ? '' : ' · ${plantilla['sku']}'}\nNo cambia las existencias: sirve para el reporte de faltantes.'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _kits,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Kits comprados'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _nota, decoration: const InputDecoration(labelText: 'Nota general'))),
          ]),
        ),
        ...hijos,
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
          label: const Text('Guardar'),
        ),
      ),
    ]);
  }
}

// --- Actas ---------------------------------------------------------------------------

/// Quién firma: normalmente la sub administradora, pero pueden ser varias personas.
class EditorFirmantes extends StatefulWidget {
  const EditorFirmantes({super.key, required this.firmantes});

  final List<Firmante> firmantes;

  @override
  State<EditorFirmantes> createState() => _EditorFirmantesState();
}

class _EditorFirmantesState extends State<EditorFirmantes> {
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final f in widget.firmantes)
          Card(
            key: ObjectKey(f),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: f.papel,
                      decoration: const InputDecoration(labelText: 'Firma como', helperText: 'Entrega, Recibe, Vo. Bo., Testigo…'),
                      onChanged: (v) => f.papel = v,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => widget.firmantes.remove(f)),
                  ),
                ]),
                const SizedBox(height: 8),
                TextFormField(initialValue: f.nombre, decoration: const InputDecoration(labelText: 'Nombre'), onChanged: (v) => f.nombre = v),
                const SizedBox(height: 8),
                TextFormField(initialValue: f.cargo, decoration: const InputDecoration(labelText: 'Cargo'), onChanged: (v) => f.cargo = v),
              ]),
            ),
          ),
        TextButton.icon(
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Agregar quien firma'),
          onPressed: () => setState(() => widget.firmantes.add(Firmante(papel: 'Firma'))),
        ),
      ]);
}

class ActaInventarioPantalla extends StatelessWidget {
  const ActaInventarioPantalla({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Acta de inventario periódico'), actions: const [BarraSesion()]),
        body: Centrado(
          child: CargaConAcceso<(Encabezado, Map<String, dynamic>)>(
            descripcion: 'preparar el acta',
            requisito: Requisito.administracion,
            cargar: (repo) async => (await Reportes(repo).encabezado(), await repo.reporteInventarioPeriodico(id)),
            construir: (context, datos, _) => _FormActa(
              tipo: TipoReporte.actaInventario,
              firmantes: Reportes.firmantesInventario(datos.$1),
              requisito: Requisito.administracion,
              encima: [
                ListTile(
                  title: Text('${datos.$2['nombre']}'),
                  subtitle: Text('${datos.$2['alcance_texto']}\n${datos.$2['estado'] == 'CERRADO' ? 'Cerrado' : 'Sigue abierto: el acta dirá que no se ha cerrado.'}'),
                ),
              ],
              armar: (r, folio, firmantes) => r.actaInventario(id, firmantes, folio),
              parametros: {'inventario': id},
            ),
          ),
        ),
      );
}

class ActaEntregaPantalla extends ConsumerStatefulWidget {
  const ActaEntregaPantalla({super.key});

  @override
  ConsumerState<ActaEntregaPantalla> createState() => _ActaEntregaPantallaState();
}

class _ActaEntregaPantallaState extends ConsumerState<ActaEntregaPantalla> {
  final _motivo = TextEditingController(text: 'cambio de responsable del laboratorio');
  final _lugar = TextEditingController(text: 'Mérida, Yucatán');
  final _observaciones = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    _lugar.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Acta de entrega-recepción'), actions: const [BarraSesion()]),
        body: Centrado(
          child: CargaConAcceso<Encabezado>(
            descripcion: 'preparar el acta',
            requisito: Requisito.subadministracion,
            cargar: (repo) => Reportes(repo).encabezado(),
            construir: (context, e, _) => _FormActa(
              tipo: TipoReporte.actaEntrega,
              firmantes: Reportes.firmantesEntrega(e),
              requisito: Requisito.subadministracion,
              encima: [
                const ListTile(
                  subtitle: Text('Lleva folio, el inventario completo, préstamos abiertos, pérdidas y daños en revisión y faltantes de kits como anexos.'),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    TextField(controller: _motivo, decoration: const InputDecoration(labelText: 'Motivo', helperText: 'Ejemplo: fin de ciclo escolar')),
                    const SizedBox(height: 12),
                    TextField(controller: _lugar, decoration: const InputDecoration(labelText: 'Lugar')),
                    const SizedBox(height: 12),
                    TextField(controller: _observaciones, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones (opcional)')),
                  ]),
                ),
              ],
              armar: (r, folio, firmantes) => r.actaEntrega(
                motivo: _motivo.text.trim().isEmpty ? 'entrega-recepción del laboratorio' : _motivo.text.trim(),
                lugar: _lugar.text.trim().isEmpty ? 'Mérida, Yucatán' : _lugar.text.trim(),
                observaciones: _observaciones.text,
                firmantes: firmantes,
                folio: folio,
                periodo: cicloEscolar(DateTime.now()),
              ),
              parametros: const {},
            ),
          ),
        ),
      );
}

class _FormActa extends ConsumerStatefulWidget {
  const _FormActa({
    required this.tipo,
    required this.firmantes,
    required this.requisito,
    required this.encima,
    required this.armar,
    required this.parametros,
  });

  final TipoReporte tipo;
  final List<Firmante> firmantes;
  final Requisito requisito;
  final List<Widget> encima;
  final Future<Documento> Function(Reportes r, String? folio, List<Firmante> firmantes) armar;
  final Map<String, dynamic> parametros;

  @override
  ConsumerState<_FormActa> createState() => _FormActaState();
}

class _FormActaState extends ConsumerState<_FormActa> {
  late final List<Firmante> _firmantes = widget.firmantes;
  String? _estado;

  Future<void> _generar(bool pdf) {
    final firmantes = [for (final f in _firmantes) if (f.papel.trim().isNotEmpty || f.nombre.trim().isNotEmpty) f];
    return generarReporte(
      context,
      ref,
      tipo: widget.tipo,
      pdf: pdf,
      requisito: widget.requisito,
      parametros: {...widget.parametros, 'firmantes': [for (final f in firmantes) f.aMapa()]},
      armar: (r, folio) => widget.armar(r, folio, firmantes),
      estado: (e) {
        if (mounted) setState(() => _estado = e);
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (_estado != null) ...[const LinearProgressIndicator(), Padding(padding: const EdgeInsets.all(12), child: Text(_estado!))],
        ...widget.encima,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Firmas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            EditorFirmantes(firmantes: _firmantes),
            const SizedBox(height: 16),
            Text('Cada vez que se genera toma el siguiente folio.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Generar PDF'), onPressed: _estado != null ? null : () => _generar(true)),
              OutlinedButton.icon(icon: const Icon(Icons.table_view), label: const Text('Excel'), onPressed: _estado != null ? null : () => _generar(false)),
            ]),
          ]),
        ),
      ]);
}
