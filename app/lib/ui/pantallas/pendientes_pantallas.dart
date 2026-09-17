import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/pendientes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';
import 'contenedores_pantallas.dart' show elegirContenedor;
import 'prestamo_pantalla.dart' show BuscarArticulo;

enum _Agrupar { tipo, categoria, ubicacion }

/// Pendientes del levantamiento (F-15). Cualquiera los consulta; docentes aportan; administración resuelve.
class PendientesPantalla extends ConsumerStatefulWidget {
  const PendientesPantalla({super.key});

  @override
  ConsumerState<PendientesPantalla> createState() => _PendientesPantallaState();
}

class _PendientesPantallaState extends ConsumerState<PendientesPantalla> {
  _Agrupar _agrupar = _Agrupar.tipo;
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    final pendientes = ref.watch(pendientesAbiertosProvider);
    final articulos = {for (final a in ref.watch(articulosProvider).value ?? const <Articulo>[]) a.id: a};
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendientes'),
        actions: [
          IconButton(icon: const Icon(Icons.pin_outlined), tooltip: 'Conteos', onPressed: () => context.push('/conteos')),
          const BarraSesion(),
        ],
      ),
      body: Centrado(
        child: Cargando<List<PendienteAbierto>>(
          valor: pendientes,
          alReintentar: () => ref.invalidate(pendientesAbiertosProvider),
          datos: (lista) {
            final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty);
            final visibles = lista.where((p) {
              final a = articulos[p.articuloId];
              return a != null && palabras.every(normalizar('${a.textoBusqueda} ${p.descripcion}').contains);
            }).toList();
            String grupo(PendienteAbierto p) {
              final a = articulos[p.articuloId]!;
              return switch (_agrupar) {
                _Agrupar.tipo => nombresTarea[p.tipo] ?? p.tipo,
                _Agrupar.categoria => a.categoria.nombre,
                _Agrupar.ubicacion => a.ubicacion ?? 'Sin ubicación',
              };
            }

            final grupos = <String, List<PendienteAbierto>>{};
            for (final p in visibles) {
              grupos.putIfAbsent(grupo(p), () => []).add(p);
            }
            final nArticulos = lista.map((p) => p.articuloId).toSet().length;
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pendientesAbiertosProvider),
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('${lista.length} pendientes en $nArticulos artículos', style: tema.textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar artículo o pendiente'),
                    onChanged: (t) => setState(() => _texto = t),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SegmentedButton<_Agrupar>(
                    segments: const [
                      ButtonSegment(value: _Agrupar.tipo, label: Text('Por tipo')),
                      ButtonSegment(value: _Agrupar.categoria, label: Text('Categoría')),
                      ButtonSegment(value: _Agrupar.ubicacion, label: Text('Ubicación')),
                    ],
                    selected: {_agrupar},
                    onSelectionChanged: (s) => setState(() => _agrupar = s.first),
                  ),
                ),
                if (lista.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hay pendientes. ¡Listo!'))),
                for (final g in (grupos.keys.toList()..sort()))
                  ExpansionTile(
                    initiallyExpanded: grupos.length <= 3,
                    title: Text(g),
                    subtitle: Text('${grupos[g]!.length}'),
                    children: [
                      for (final p in grupos[g]!)
                        ListTile(
                          leading: Icon(Icons.flag_outlined, color: p.prioridadAlta ? Avisos.sinClasificar : Avisos.pendiente),
                          title: Text('${articulos[p.articuloId]!.codigo} · ${articulos[p.articuloId]!.nombre}'),
                          subtitle: Text([if (_agrupar != _Agrupar.tipo) nombresTarea[p.tipo] ?? p.tipo, p.descripcion].join('\n'),
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                          onTap: () => abrirPendiente(context, ref, p, articulos[p.articuloId]!),
                        ),
                    ],
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Abre la resolución de un pendiente según su tipo.
Future<void> abrirPendiente(BuildContext context, WidgetRef ref, PendienteAbierto p, Articulo a) async {
  if (p.tipo == 'ABRIR_REVISAR') {
    await context.push('/desglose/${a.id}');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HojaPendiente(pendiente: p, articulo: a),
  );
}

class _HojaPendiente extends ConsumerStatefulWidget {
  const _HojaPendiente({required this.pendiente, required this.articulo});

  final PendienteAbierto pendiente;
  final Articulo articulo;

  @override
  ConsumerState<_HojaPendiente> createState() => _HojaPendienteState();
}

class _HojaPendienteState extends ConsumerState<_HojaPendiente> {
  final _nota = TextEditingController();
  final _serie = TextEditingController();
  final _fotos = <FotoNueva>[];
  List<AportePendiente>? _aportes;
  bool _trabajando = false;
  String? _resultado;
  bool? _si;
  Categoria? _categoria;
  String? _contenedorId;
  String? _contenedorRuta;
  Etiquetado? _etiquetado;

  @override
  void initState() {
    super.initState();
    _serie.text = widget.articulo.numSerie ?? '';
    _cargarAportes();
  }

  @override
  void dispose() {
    _nota.dispose();
    _serie.dispose();
    super.dispose();
  }

  Future<void> _cargarAportes() async {
    final sesion = await ref.read(sesionProvider.future);
    if (sesion == null) return;
    try {
      final a = await ref.read(repositorioProvider).aportesDePendiente(widget.pendiente.id);
      if (mounted) setState(() => _aportes = a);
    } on Object {
      // Los aportes son informativos: si no cargan, se puede resolver igual.
    }
  }

  PendienteAbierto get p => widget.pendiente;
  Articulo get a => widget.articulo;
  String? get _textoNota => _nota.text.trim().isEmpty ? null : _nota.text.trim();

  Future<void> _hacer(String descripcion, Requisito requisito, Future<void> Function(Repositorio r) accion, String listo) async {
    setState(() => _trabajando = true);
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: descripcion, requisito: requisito, accion: () async {
        await accion(ref.read(repositorioProvider));
        return true;
      });
      if (hecho != true || !mounted) return;
      refrescarArticulo(ref, a.id);
      Navigator.pop(context);
      avisar(context, listo);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _aportar() async {
    if (_textoNota == null) return avisar(context, 'Escribe lo que encontraste.');
    await _hacer('agregar una nota al pendiente', Requisito.docente,
        (r) => r.aportarAPendiente(p.id, a.id, _textoNota!, _fotos.firstOrNull), 'Nota agregada. El responsable la verá al resolver.');
  }

  Future<void> _resolver() async {
    final datos = <String, dynamic>{if (_textoNota != null) 'nota': _textoNota};
    var requisito = Requisito.administracion;
    switch (p.tipo) {
      case 'VERIFICAR_DATO':
        break;
      case 'REGISTRAR_SERIE':
        if (_serie.text.trim().isEmpty) return avisar(context, 'Escribe el número de serie o la medida.');
        datos['num_serie'] = _serie.text.trim();
      case 'IDENTIFICAR_ETIQUETAR':
        if (_contenedorId == null && _etiquetado == null) return avisar(context, 'Elige dónde vive o cómo se etiqueta.');
        if (_contenedorId != null) datos['contenedor_id'] = _contenedorId;
        if (_etiquetado != null) datos['etiquetado'] = _etiquetado!.codigo;
      case 'FALTA_PIEZA':
        if (_resultado == null) return avisar(context, 'Elige qué pasó.');
        datos['resultado'] = _resultado;
      case 'CONFIRMAR_VACIO':
        if (_si == null) return avisar(context, 'Indica si está vacío.');
        datos['vacio'] = _si;
      case 'LOCALIZAR_CONTENIDO':
        if (_si == null) return avisar(context, 'Indica si apareció.');
        datos['encontrado'] = _si;
      case 'DEFINIR_VEX_FTC':
        if (_categoria == null) return avisar(context, 'Elige la categoría.');
        datos['categoria'] = _categoria!.codigo;
        requisito = Requisito.administracionConfirmada;
    }
    final foto = _fotos.firstOrNull;
    await _hacer('resolver "${nombresTarea[p.tipo]}" de ${a.codigo}', requisito, (r) async {
      if (p.tipo == 'REGISTRAR_SERIE' && foto != null) datos['foto'] = await r.subirFotoArticulo(a.id, foto);
      await r.resolverPendiente(p.id, datos);
    }, 'Pendiente resuelto.');
  }

  Future<void> _descartar() async {
    final motivo = await pedirTexto(context, titulo: 'Ya no aplica', etiqueta: 'Por qué *', minimo: 10, boton: 'Descartar');
    if (motivo == null || !mounted) return;
    await _hacer('descartar el pendiente', Requisito.administracion,
        (r) => r.resolverPendiente(p.id, {'accion': 'DESCARTAR', 'motivo': motivo}), 'Pendiente descartado.');
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sesion = ref.watch(sesionProvider).value;
    final administra = sesion?.administra ?? false;
    Widget opcion<T>(T valor, T? actual, String texto, ValueChanged<T> alElegir) =>
        RadioListTile<T>(value: valor, groupValue: actual, onChanged: (v) => alElegir(v as T), title: Text(texto), contentPadding: EdgeInsets.zero, dense: true);

    final formulario = switch (p.tipo) {
      'CONTAR' => <Widget>[
          const Text('Cuenta cuántos hay en el taller. El conteo queda por aplicar hasta que lo autorice el responsable o sub administración.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _trabajando
                ? null
                : () async {
                    Navigator.pop(context);
                    await contarArticulo(context, ref, a);
                  },
            icon: const Icon(Icons.pin_outlined),
            label: const Text('Contar ahora'),
          ),
        ],
      'REGISTRAR_SERIE' => <Widget>[
          TextField(controller: _serie, decoration: const InputDecoration(labelText: 'Número de serie o medida *')),
          const SizedBox(height: 8),
          const Text('Foto de la placa (opcional)'),
          const SizedBox(height: 4),
          SelectorFotos(fotos: _fotos, alCambiar: () => setState(() {}), maximo: 1),
        ],
      'IDENTIFICAR_ETIQUETAR' => <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_contenedorRuta ?? a.ubicacion ?? 'Sin ubicación'),
            trailing: TextButton(
              onPressed: () async {
                final c = await elegirContenedor(context, ref, para: a.categoria, excluir: a.contenedorId, titulo: '¿Dónde vive?');
                if (c != null) setState(() => [_contenedorId = c.id, _contenedorRuta = c.ruta]);
              },
              child: const Text('Elegir contenedor'),
            ),
          ),
          DropdownButtonFormField<Etiquetado>(
            value: _etiquetado,
            decoration: InputDecoration(labelText: 'Etiquetado (ahora: ${a.etiquetado.nombre})'),
            items: [for (final e in Etiquetado.values) DropdownMenuItem(value: e, child: Text('${e.nombre}: ${e.explicacion}'))],
            onChanged: (e) => setState(() => _etiquetado = e),
          ),
        ],
      'FALTA_PIEZA' => <Widget>[
          opcion('COMPLETO', _resultado, 'Se consiguió: está completo', (v) => setState(() => _resultado = v)),
          opcion('INCOMPLETO', _resultado, 'Queda incompleto (anota qué falta)', (v) => setState(() => _resultado = v)),
          opcion('REPORTADO', _resultado, 'Se levantó un reporte de pérdida', (v) => setState(() => _resultado = v)),
          TextButton(onPressed: () => context.push('/articulo/${a.id}/reportar'), child: const Text('Levantar reporte de pérdida')),
        ],
      'CONFIRMAR_VACIO' => <Widget>[
          opcion(true, _si, 'Está vacío (se crea el pendiente de localizar su contenido)', (v) => setState(() => _si = v)),
          opcion(false, _si, 'Tiene contenido (escribe qué)', (v) => setState(() => _si = v)),
        ],
      'LOCALIZAR_CONTENIDO' => <Widget>[
          opcion(true, _si, 'Apareció (escribe dónde)', (v) => setState(() => _si = v)),
          opcion(false, _si, 'No apareció: se da por faltante', (v) => setState(() => _si = v)),
        ],
      'DEFINIR_VEX_FTC' => <Widget>[
          DropdownButtonFormField<Categoria>(
            value: _categoria,
            decoration: const InputDecoration(labelText: 'Categoría *'),
            items: [for (final c in Categoria.values.where((c) => c != Categoria.sinClasificar)) DropdownMenuItem(value: c, child: Text(c.nombre))],
            onChanged: (c) => setState(() => _categoria = c),
          ),
          const Text('Si su contenedor actual no admite esa categoría, se queda sin ubicación.', style: TextStyle(fontSize: 12)),
        ],
      'VERIFICAR_DATO' => <Widget>[
          Text('Revisa el dato. Si hay que corregir algo, edita el artículo y luego marca como verificado.', style: tema.textTheme.bodyMedium),
          TextButton(onPressed: () => context.push('/articulo/${a.id}/editar'), child: const Text('Editar el artículo')),
        ],
      _ => <Widget>[],
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(nombresTarea[p.tipo] ?? p.tipo, style: tema.textTheme.titleLarge),
          Text('${a.codigo} · ${a.nombre}', style: tema.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(p.descripcion),
          if (a.observaciones != null) Text('Observaciones: ${a.observaciones}', style: tema.textTheme.bodySmall),
          TextButton(onPressed: () => context.push('/articulo/${a.id}'), child: const Text('Ver ficha')),
          if (_aportes != null && _aportes!.isNotEmpty) ...[
            const Divider(),
            for (final x in _aportes!) Text('💬 ${x.autor} (${fecha(x.en)}): ${x.nota}', style: tema.textTheme.bodySmall),
          ],
          const Divider(height: 24),
          if (sesion == null)
            const Text('Entra con tu cuenta para aportar o resolver.')
          else ...[
            if (administra || p.tipo == 'CONTAR') ...formulario,
            if (p.tipo != 'CONTAR') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _nota,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: administra ? 'Nota' : 'Lo que encontraste *'),
              ),
              if (!administra) ...[
                const SizedBox(height: 8),
                const Text('Foto (opcional)'),
                SelectorFotos(fotos: _fotos, alCambiar: () => setState(() {}), maximo: 1),
              ],
              const SizedBox(height: 12),
              if (administra)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(onPressed: _trabajando ? null : _resolver, child: Text(p.tipo == 'VERIFICAR_DATO' ? 'Marcar como verificado' : 'Resolver')),
                  OutlinedButton(onPressed: _trabajando ? null : _aportar, child: const Text('Solo agregar nota')),
                  TextButton(onPressed: _trabajando ? null : _descartar, child: const Text('Ya no aplica')),
                ])
              else
                FilledButton(onPressed: _trabajando ? null : _aportar, child: const Text('Enviar nota al responsable')),
            ],
          ],
        ]),
      ),
    );
  }
}

/// Captura un conteo (cualquier cuenta). Queda por aplicar en "Conteos".
Future<void> contarArticulo(BuildContext context, WidgetRef ref, Articulo a) async {
  final cantidad = TextEditingController();
  final nota = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Contar ${a.codigo}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.nombre),
        const SizedBox(height: 4),
        Text('Cuenta solo lo que está en el taller${a.prestado > 0 ? ' (hay ${a.prestado} prestados que no se cuentan)' : ''}.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(
          controller: cantidad,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Cuántos hay (${plural(a.unidad)})'),
        ),
        const SizedBox(height: 12),
        TextField(controller: nota, decoration: const InputDecoration(labelText: 'Nota (si no cuadra, explica)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar conteo')),
      ],
    ),
  );
  final n = int.tryParse(cantidad.text.trim());
  final textoNota = nota.text.trim();
  cantidad.dispose();
  nota.dispose();
  if (ok != true || n == null || !context.mounted) return;
  try {
    final r = await conAcceso<({int sistema, int diferencia})>(context, ref,
        descripcion: 'contar "${a.nombre}"',
        requisito: Requisito.docente,
        accion: () => ref.read(repositorioProvider).proponerConteo(a.id, n, textoNota.isEmpty ? null : textoNota));
    if (r == null || !context.mounted) return;
    avisar(context,
        r.diferencia == 0 ? 'Conteo guardado: coincide con el sistema.' : 'Conteo guardado: ${r.diferencia > 0 ? 'sobran' : 'faltan'} ${r.diferencia.abs()}. Queda por aplicar.');
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}

/// Conteos por aplicar: docentes ven los suyos; administración aplica en lote con una sola contraseña.
class ConteosPantalla extends ConsumerWidget {
  const ConteosPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conteos'), actions: const [BarraSesion()]),
      body: Centrado(
        child: CargaConAcceso<List<ConteoPorAplicar>>(
          descripcion: 'ver los conteos',
          requisito: Requisito.docente,
          cargar: (repo) => repo.conteosPorAplicar(),
          construir: (context, lista, recargar) => _Conteos(lista: lista, recargar: recargar),
        ),
      ),
    );
  }
}

class _Conteos extends ConsumerStatefulWidget {
  const _Conteos({required this.lista, required this.recargar});

  final List<ConteoPorAplicar> lista;
  final Future<void> Function() recargar;

  @override
  ConsumerState<_Conteos> createState() => _ConteosState();
}

class _ConteosState extends ConsumerState<_Conteos> {
  final _elegidos = <String>{};
  final _notas = <String, TextEditingController>{};
  bool _trabajando = false;

  @override
  void dispose() {
    for (final c in _notas.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _contarOtro() async {
    final todos = await ref.read(articulosProvider.future);
    if (!mounted) return;
    final a = await showModalBottomSheet<Articulo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BuscarArticulo(opciones: todos.where((x) => x.activo).toList()),
    );
    if (a == null || !mounted) return;
    await contarArticulo(context, ref, a);
    await widget.recargar();
  }

  Future<void> _aplicar(List<ConteoPorAplicar> cuales) async {
    setState(() => _trabajando = true);
    try {
      final notas = {for (final c in cuales) if ((_notas[c.id]?.text.trim() ?? '').isNotEmpty) c.id: _notas[c.id]!.text.trim()};
      final r = await conAcceso<({int aplicados, int ajustes})>(context, ref,
          descripcion: 'aplicar ${cuales.length} conteo${cuales.length == 1 ? '' : 's'}',
          requisito: Requisito.administracionConfirmada,
          accion: () => ref.read(repositorioProvider).aplicarConteos([for (final c in cuales) c.id], notas));
      if (r == null || !mounted) return;
      for (final c in cuales) {
        refrescarArticulo(ref, c.articuloId);
      }
      avisar(context, 'Aplicados ${r.aplicados}: ${r.ajustes} con ajuste de cantidad.');
      _elegidos.clear();
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _descartar(List<ConteoPorAplicar> cuales) async {
    final motivo = await pedirTexto(context, titulo: 'Descartar conteos', etiqueta: 'Por qué *', boton: 'Descartar');
    if (motivo == null || !mounted) return;
    try {
      await conAcceso<bool>(context, ref, descripcion: 'descartar conteos', requisito: Requisito.administracion, accion: () async {
        await ref.read(repositorioProvider).descartarConteos([for (final c in cuales) c.id], motivo);
        return true;
      });
      _elegidos.clear();
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final administra = ref.watch(sesionProvider).value?.administra ?? false;
    final elegidos = widget.lista.where((c) => _elegidos.contains(c.id)).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: _contarOtro, icon: const Icon(Icons.add), label: const Text('Contar un artículo')),
        OutlinedButton.icon(onPressed: () => context.push('/pendientes'), icon: const Icon(Icons.flag_outlined), label: const Text('Pendientes de contar')),
      ]),
      const SizedBox(height: 12),
      if (widget.lista.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(administra ? 'No hay conteos por aplicar.' : 'No tienes conteos esperando autorización.'),
        ),
      if (administra && widget.lista.isNotEmpty)
        CheckboxListTile(
          value: _elegidos.length == widget.lista.length,
          onChanged: (v) => setState(() => v == true ? _elegidos.addAll(widget.lista.map((c) => c.id)) : _elegidos.clear()),
          title: Text('Elegir todos (${widget.lista.length})'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      for (final c in widget.lista)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (administra)
                  Checkbox(value: _elegidos.contains(c.id), onChanged: (v) => setState(() => v == true ? _elegidos.add(c.id) : _elegidos.remove(c.id))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.codigo} · ${c.nombre}', style: tema.textTheme.titleSmall),
                    Text('Contó ${c.contadoPor} · ${fechaHora(c.contadoEn)}${c.estimada ? ' · era estimado' : ''}', style: tema.textTheme.bodySmall),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${c.enTaller} ${c.enTaller == 1 ? c.unidad : plural(c.unidad)}', style: tema.textTheme.titleMedium),
                  Text(
                    c.diferencia == 0 ? 'coincide' : '${c.diferencia > 0 ? '+' : ''}${c.diferencia} (sistema: ${c.sistema})',
                    style: TextStyle(color: c.diferencia == 0 ? tema.colorScheme.primary : tema.colorScheme.error),
                  ),
                ]),
              ]),
              if (c.nota != null) Padding(padding: const EdgeInsets.only(left: 48), child: Text(c.nota!)),
              if (administra && c.diferencia != 0 && c.nota == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 4, 0, 0),
                  child: TextField(
                    controller: _notas.putIfAbsent(c.id, TextEditingController.new),
                    decoration: const InputDecoration(labelText: 'Explica la diferencia *', isDense: true),
                  ),
                ),
            ]),
          ),
        ),
      if (administra && elegidos.isNotEmpty) ...[
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _trabajando ? null : () => _aplicar(elegidos),
          icon: const Icon(Icons.done_all),
          label: Text('Aplicar ${elegidos.length} (una sola contraseña)'),
        ),
        TextButton(onPressed: _trabajando ? null : () => _descartar(elegidos), child: const Text('Descartar los elegidos')),
      ],
    ]);
  }
}
