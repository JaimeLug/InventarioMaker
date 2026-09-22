import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/pendientes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';
import 'prestamo_pantalla.dart' show BuscarArticulo;

/// Desglose de un kit: se abre la caja y se captura lo que traía, contra su lista de contenido si la hay.
class DesglosePantalla extends ConsumerStatefulWidget {
  const DesglosePantalla({super.key, required this.articuloId});

  final String articuloId;

  @override
  ConsumerState<DesglosePantalla> createState() => _DesglosePantallaState();
}

class _DesglosePantallaState extends ConsumerState<DesglosePantalla> {
  Desglose? _d;
  bool _cargando = true;
  bool _trabajando = false;
  bool _cambios = false;
  int _unidades = 1;
  String? _plantillaId;
  List<PlantillaKit> _plantillas = const [];
  List<Map<String, dynamic>> _historial = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await conAcceso<(List<PlantillaKit>, List<Map<String, dynamic>>)>(context, ref,
          descripcion: 'desglosar un kit', requisito: Requisito.administracion, accion: () async {
        final repo = ref.read(repositorioProvider);
        return (await repo.plantillasKit(), await repo.desglosesDeArticulo(widget.articuloId));
      });
      if (r == null || !mounted) return;
      _plantillas = r.$1;
      _historial = r.$2;
      final borrador = _historial.where((h) => h['estado'] == 'BORRADOR').firstOrNull;
      if (borrador != null) {
        final d = await ref.read(repositorioProvider).detalleDesglose(borrador['id'] as String);
        if (mounted) setState(() => _d = d);
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _iniciar() async {
    setState(() => _trabajando = true);
    try {
      final d = await conAcceso<Desglose>(context, ref,
          descripcion: 'empezar el desglose',
          requisito: Requisito.administracion,
          accion: () => ref.read(repositorioProvider).iniciarDesglose(widget.articuloId, _unidades, _plantillaId));
      if (d != null && mounted) setState(() => _d = d);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<bool> _guardar({bool avisarListo = true}) async {
    final d = _d!;
    setState(() => _trabajando = true);
    try {
      final nuevo = await conAcceso<Desglose>(context, ref,
          descripcion: 'guardar el desglose', requisito: Requisito.administracion, accion: () => ref.read(repositorioProvider).guardarDesglose(d));
      if (nuevo == null || !mounted) return false;
      setState(() {
        _d = nuevo;
        _cambios = false;
      });
      if (avisarListo) avisar(context, 'Borrador guardado. Puedes seguir después.');
      return true;
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _terminar() async {
    final d = _d!;
    final todas = d.unidades >= d.existencia;
    final destino = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿Qué pasa con el kit?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'DESGLOSADO'),
            child: Text(todas
                ? 'Sale del inventario como "Desglosado": ahora cuentan sus piezas'
                : 'Se descuentan ${d.unidades} de ${d.existencia} unidades; el resto sigue en el kit'),
          ),
          if (todas)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'EMPAQUE'),
              child: const Text('Se queda registrado como empaque vacío (las cajas se conservan)'),
            ),
        ],
      ),
    );
    if (destino == null || !mounted) return;
    if (_cambios && !await _guardar(avisarListo: false)) return;
    if (!mounted) return;
    setState(() => _trabajando = true);
    try {
      final r = await conAcceso<({int creados, int sumados, int faltantes})>(context, ref,
          descripcion: 'terminar el desglose de ${d.articuloCodigo}',
          requisito: Requisito.administracionConfirmada,
          accion: () => ref.read(repositorioProvider).terminarDesglose(d.id, destino));
      if (r == null || !mounted) return;
      refrescarArticulo(ref, d.articuloId);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desglose terminado'),
          content: Text('${r.creados} artículo(s) nuevo(s), ${r.sumados} sumado(s) a existentes, '
              '${r.faltantes} renglón(es) con faltante contra la lista.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
        ),
      );
      if (mounted) context.pop();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _sumarA(LineaDesglose l) async {
    final d = _d!;
    final todos = await ref.read(articulosProvider.future);
    if (!mounted) return;
    final a = await showModalBottomSheet<Articulo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BuscarArticulo(opciones: todos.where((x) => x.activo && x.categoria.codigo == d.categoria && x.id != d.articuloId).toList()),
    );
    if (a != null) {
      setState(() {
        l.articuloDestinoId = a.id;
        l.articuloDestino = '${a.codigo} ${a.nombre}';
        _cambios = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final articulo = ref.watch(articuloProvider(widget.articuloId)).value;
    final d = _d;
    return PopScope(
      canPop: !_cambios,
      onPopInvokedWithResult: (salio, _) async {
        if (salio) return;
        final guardar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hay cambios sin guardar'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Salir sin guardar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar borrador')),
            ],
          ),
        );
        if (!mounted || guardar == null) return;
        if (guardar && !await _guardar(avisarListo: false)) return;
        setState(() => _cambios = false);
        if (mounted) this.context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Desglose ${articulo?.codigo ?? ''}'),
          actions: [
            if (d != null)
              IconButton(icon: const Icon(Ico.guardar), tooltip: 'Guardar borrador', onPressed: _trabajando ? null : () => _guardar()),
          ],
        ),
        bottomNavigationBar: d == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _trabajando ? null : _terminar,
                    icon: const Icon(Ico.todoListo),
                    label: const Text('Terminar desglose'),
                  ),
                ),
              ),
        body: Centrado(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : d == null
                  ? _inicio(context, articulo)
                  : _editor(context, d),
        ),
      ),
    );
  }

  Widget _inicio(BuildContext context, Articulo? a) {
    final tema = Theme.of(context);
    final aplicables = _plantillas.where((p) => a == null || !a.categoria.esRobotica() || p.categoria == a.categoria.codigo).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (a != null) ...[
        Text(a.nombre, style: tema.textTheme.headlineSmall),
        Text('${a.codigo} · ${a.categoria.nombre}${a.subcategoria == null ? '' : ' · ${a.subcategoria}'} · ${a.cantidadMostrada}'),
        if (a.observaciones != null) Text(a.observaciones!, style: tema.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      const Text('Abre la caja y captura lo que trae, renglón por renglón. Se guarda como borrador: no se crea nada hasta que toques "Terminar".'),
      const SizedBox(height: 16),
      if (a != null)
        Row(children: [
          const Expanded(child: Text('¿Cuántas unidades vas a abrir?')),
          SelectorCantidad(valor: _unidades, minimo: 1, maximo: a.existencia < 1 ? 1 : a.existencia, alCambiar: (v) => setState(() => _unidades = v)),
        ]),
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        value: _plantillaId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Lista de contenido (opcional)', helperText: 'Precarga lo que debería traer y marca el faltante'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Sin lista: capturar a mano')),
          for (final p in aplicables) DropdownMenuItem(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _plantillaId = v),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _trabajando ? null : _iniciar, child: const Text('Empezar')),
      if (_historial.where((h) => h['estado'] == 'TERMINADO').isNotEmpty) ...[
        const Divider(height: 32),
        Text('Desgloses anteriores', style: tema.textTheme.titleMedium),
        for (final h in _historial.where((h) => h['estado'] == 'TERMINADO'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${h['unidades']} unidad(es) · ${h['plantilla'] ?? 'sin lista'}'),
            subtitle: Text('${fecha(DateTime.parse(h['terminado_en'] as String))} · ${h['renglones']} renglones · ${h['faltantes']} con faltante'),
          ),
      ],
    ]);
  }

  Widget _editor(BuildContext context, Desglose d) {
    final tema = Theme.of(context);
    final faltantes = d.lineas.where((l) => l.faltante > 0).length;
    String? seccion;
    final hijos = <Widget>[];
    for (final l in d.lineas) {
      if (l.seccion != null && l.seccion != seccion) {
        seccion = l.seccion;
        hijos.add(Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text(seccion!, style: tema.textTheme.titleSmall)));
      }
      hijos.add(_RenglonDesglose(
        linea: l,
        alCambiar: () => setState(() => _cambios = true),
        alSumar: () => _sumarA(l),
        alQuitar: l.plantillaLineaId != null
            ? null
            : () => setState(() {
                  d.lineas.remove(l);
                  _cambios = true;
                }),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
      Text('${d.articuloCodigo} · ${d.articuloNombre}', style: tema.textTheme.titleMedium),
      Text([
        '${d.unidades} de ${d.existencia} unidad(es)',
        if (d.plantilla != null) 'Lista: ${d.plantilla}',
        '${d.lineas.length} renglones',
        if (faltantes > 0) '$faltantes con faltante',
      ].join(' · ')),
      const SizedBox(height: 8),
      // Con lista, lo esperado se calculó para estas unidades: para cambiarlas se cancela y se vuelve a empezar.
      if (d.plantilla == null) Row(children: [
        const Expanded(child: Text('Unidades abiertas')),
        SelectorCantidad(
          valor: d.unidades,
          minimo: 1,
          maximo: d.existencia < 1 ? 1 : d.existencia,
          alCambiar: (v) => setState(() {
            d.unidades = v;
            _cambios = true;
          }),
        ),
      ]),
      ...hijos,
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          final texto = await pedirTexto(context, titulo: 'Agregar renglón', etiqueta: 'Qué encontraste *', boton: 'Agregar');
          if (texto != null) {
            setState(() {
              d.lineas.add(LineaDesglose(descripcion: texto, encontrada: 1));
              _cambios = true;
            });
          }
        },
        icon: const Icon(Ico.nuevo),
        label: const Text('Agregar algo que no está en la lista'),
      ),
      TextButton(
        onPressed: _trabajando
            ? null
            : () async {
                try {
                  await ref.read(repositorioProvider).cancelarDesglose(d.id);
                  if (!mounted) return;
                  setState(() {
                    _d = null;
                    _cambios = false;
                  });
                } on Object catch (e) {
                  if (mounted) avisarError(this.context, e);
                }
              },
        child: const Text('Cancelar este desglose'),
      ),
    ]);
  }
}

class _RenglonDesglose extends StatefulWidget {
  const _RenglonDesglose({required this.linea, required this.alCambiar, required this.alSumar, this.alQuitar});

  final LineaDesglose linea;
  final VoidCallback alCambiar;
  final VoidCallback alSumar;
  final VoidCallback? alQuitar;

  @override
  State<_RenglonDesglose> createState() => _RenglonDesgloseState();
}

class _RenglonDesgloseState extends State<_RenglonDesglose> {
  late final _cantidad = TextEditingController(text: widget.linea.encontrada?.toString() ?? '');

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.linea;
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.descripcion, style: tema.textTheme.titleSmall),
                Text([
                  if (l.sku != null) l.sku!,
                  l.esperada == null ? 'cantidad esperada: varios' : 'esperados: ${l.esperada} ${plural(l.unidad)}',
                ].join(' · '), style: tema.textTheme.bodySmall),
              ]),
            ),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _cantidad,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'Hay', isDense: true),
                onChanged: (t) {
                  l.encontrada = int.tryParse(t);
                  widget.alCambiar();
                  setState(() {});
                },
              ),
            ),
            if (widget.alQuitar != null) IconButton(icon: const Icon(Ico.cerrar), tooltip: 'Quitar', onPressed: widget.alQuitar),
          ]),
          if (l.faltante > 0) Text('Faltan ${l.faltante}', style: TextStyle(color: tema.colorScheme.error, fontWeight: FontWeight.w600)),
          if ((l.encontrada ?? 0) > 0)
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ActionChip(
                avatar: Icon(l.articuloDestinoId == null ? Ico.articuloNuevo : Ico.enlazar, size: 18),
                label: Text(l.articuloDestino == null ? 'Artículo nuevo' : 'Sumar a ${l.articuloDestino}'),
                onPressed: widget.alSumar,
              ),
              if (l.articuloDestinoId != null)
                TextButton(
                  onPressed: () {
                    l.articuloDestinoId = null;
                    l.articuloDestino = null;
                    widget.alCambiar();
                    setState(() {});
                  },
                  child: const Text('Mejor nuevo'),
                ),
              if (l.articuloDestinoId == null)
                FilterChip(
                  label: const Text('Consumible'),
                  selected: l.esConsumible,
                  onSelected: (v) {
                    l.esConsumible = v;
                    widget.alCambiar();
                    setState(() {});
                  },
                ),
            ]),
        ]),
      ),
    );
  }
}
