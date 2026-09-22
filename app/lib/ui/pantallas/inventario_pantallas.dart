import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/contenedores.dart';
import '../../modelos/pendientes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';

/// Inventarios periódicos (F-16): abrir, contar, revisar diferencias y cerrar.
class InventariosPantalla extends ConsumerWidget {
  const InventariosPantalla({super.key});

  Future<void> _abrir(BuildContext context, WidgetRef ref, Future<void> Function() recargar) async {
    final r = await showModalBottomSheet<(String, Map<String, dynamic>)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _HojaAbrir(),
    );
    if (r == null || !context.mounted) return;
    try {
      final id = await conAcceso<String>(context, ref,
          descripcion: 'abrir un inventario', requisito: Requisito.administracion, accion: () => ref.read(repositorioProvider).abrirInventario(r.$1, r.$2));
      if (id == null || !context.mounted) return;
      await context.push('/inventario/$id');
      await recargar();
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final administra = ref.watch(sesionProvider).value?.administra ?? false;
    return TmArmazon(
      ruta: '/inventarios',
      titulo: 'Inventarios periódicos',
      child: Centrado(
        child: CargaConAcceso<List<InventarioResumen>>(
          descripcion: 'ver los inventarios',
          requisito: Requisito.docente,
          cargar: (repo) => repo.inventarios(),
          construir: (context, lista, recargar) => ListView(padding: const EdgeInsets.all(12), children: [
            if (administra && !lista.any((i) => i.abierto))
              TmBoton('Abrir un inventario', tipo: TipoBoton.primario, icono: Ico.contar, expandido: true, onTap: () => _abrir(context, ref, recargar)),
            if (lista.isEmpty)
              TmVacio(
                icono: Ico.contar,
                titulo: 'Todavía no se ha hecho ningún inventario',
                texto: administra
                    ? 'Un inventario periódico sirve para contar todo (o una parte) y dejar acta de lo que salió.'
                    : 'Cuando el responsable abra uno, aquí podrás contar lo que te toque.',
              ),
            for (final i in lista)
              Card(
                child: ListTile(
                  leading: Icon(i.abierto ? Ico.enCurso : Ico.ok),
                  title: Text(i.nombre),
                  subtitle: Text([
                    i.abierto ? 'Abierto desde ${fecha(i.fechaInicio)}' : 'Cerrado el ${fecha(i.fechaCierre!)} por ${i.cerro}',
                    'Contados ${i.contados} de ${i.articulos}',
                  ].join(' · ')),
                  trailing: const Icon(Ico.avanzar),
                  onTap: () async {
                    await context.push('/inventario/${i.id}');
                    await recargar();
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _HojaAbrir extends ConsumerStatefulWidget {
  const _HojaAbrir();

  @override
  ConsumerState<_HojaAbrir> createState() => _HojaAbrirState();
}

class _HojaAbrirState extends ConsumerState<_HojaAbrir> {
  final _nombre = TextEditingController(text: 'Inventario ${fecha(DateTime.now())}');
  String _tipo = 'todo';
  final _categorias = <Categoria>{};
  final _contenedores = <String>{};

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contenedores = (ref.watch(contenedoresProvider).value ?? const <Contenedor>[]).where((c) => c.activo).toList();
    final listo = _tipo == 'todo' || (_tipo == 'categorias' && _categorias.isNotEmpty) || (_tipo == 'contenedores' && _contenedores.isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Abrir inventario', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 12),
          const Text('Qué se cuenta'),
          for (final (valor, texto) in const [('todo', 'Todo el inventario'), ('categorias', 'Ciertas categorías'), ('contenedores', 'Ciertos contenedores')])
            RadioListTile<String>(
              value: valor,
              groupValue: _tipo,
              onChanged: (v) => setState(() => _tipo = v!),
              title: Text(texto),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          if (_tipo == 'categorias')
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in Categoria.values.where((c) => c != Categoria.sinClasificar))
                FilterChip(
                  label: Text(c.nombre),
                  selected: _categorias.contains(c),
                  onSelected: (v) => setState(() => v ? _categorias.add(c) : _categorias.remove(c)),
                ),
            ]),
          if (_tipo == 'contenedores')
            for (final (c, nivel) in comoArbol(contenedores))
              CheckboxListTile(
                value: _contenedores.contains(c.id),
                onChanged: (v) => setState(() => v == true ? _contenedores.add(c.id) : _contenedores.remove(c.id)),
                title: Text(c.nombre),
                subtitle: Text('${c.codigo} · incluye lo que tenga adentro'),
                contentPadding: EdgeInsets.only(left: nivel * 16.0),
                dense: true,
              ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !listo
                ? null
                : () => Navigator.pop(context, (
                      _nombre.text.trim(),
                      switch (_tipo) {
                        'categorias' => {'categorias': [for (final c in _categorias) c.codigo]},
                        'contenedores' => {'contenedores': _contenedores.toList()},
                        _ => {'todo': true},
                      }
                    )),
            child: const Text('Abrir'),
          ),
        ]),
      ),
    );
  }
}

/// Un inventario: contar (por contenedor o por lista), hallazgos y, para administración, diferencias y cierre.
class InventarioPeriodicoPantalla extends ConsumerWidget {
  const InventarioPeriodicoPantalla({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final administra = ref.watch(sesionProvider).value?.administra ?? false;
    return DefaultTabController(
      length: administra ? 3 : 2,
      child: TmArmazon(
               ruta: '/inventarios',
               titulo: 'Inventario',
               conRegresar: true,
               bajoTitulo: TabBar(tabs: [
            const Tab(text: 'Contar'),
            const Tab(text: 'Hallazgos'),
            if (administra) const Tab(text: 'Diferencias'),
          ]),
               child: TabBarView(children: [
          Centrado(
            child: CargaConAcceso<(List<ArticuloDeInventario>, List<InventarioResumen>)>(
              descripcion: 'contar en el inventario',
              requisito: Requisito.docente,
              cargar: (repo) async => (await repo.articulosDeInventario(id), await repo.inventarios()),
              construir: (context, datos, recargar) => _Contar(
                  inventarioId: id, articulos: datos.$1, abierto: datos.$2.where((i) => i.id == id).firstOrNull?.abierto ?? false, recargar: recargar),
            ),
          ),
          Centrado(
            child: CargaConAcceso<List<Hallazgo>>(
              descripcion: 'ver los hallazgos',
              requisito: Requisito.docente,
              cargar: (repo) => repo.hallazgosDeInventario(id),
              construir: (context, lista, recargar) => _Hallazgos(inventarioId: id, lista: lista, recargar: recargar),
            ),
          ),
          if (administra)
            Centrado(
              child: CargaConAcceso<List<DiferenciaInventario>>(
                descripcion: 'revisar diferencias',
                requisito: Requisito.administracion,
                cargar: (repo) => repo.diferenciasDeInventario(id),
                construir: (context, lista, recargar) => _Diferencias(inventarioId: id, lista: lista, recargar: recargar),
              ),
            ),
        ]),
             ),
    );
  }
}

class _Contar extends ConsumerStatefulWidget {
  const _Contar({required this.inventarioId, required this.articulos, required this.abierto, required this.recargar});

  final String inventarioId;
  final List<ArticuloDeInventario> articulos;
  final bool abierto;
  final Future<void> Function() recargar;

  @override
  ConsumerState<_Contar> createState() => _ContarState();
}

class _ContarState extends ConsumerState<_Contar> {
  String _texto = '';
  String? _contenedor;
  bool _soloSinContar = false;

  Future<void> _contar(ArticuloDeInventario a) async {
    final cantidad = TextEditingController(text: a.miConteo?.toString() ?? '');
    final valor = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(a.nombre),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${a.codigo}${a.ruta == null ? '' : ' · ${a.ruta}'}'),
          const SizedBox(height: 8),
          Text('Deberían estar en el taller: ${a.enTaller} ${a.enTaller == 1 ? a.unidad : plural(a.unidad)}'),
          const SizedBox(height: 12),
          TextField(
            controller: cantidad,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Cuántos contaste'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          OutlinedButton(onPressed: () => Navigator.pop(context, a.enTaller), child: const Text('Coincide')),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(cantidad.text.trim())), child: const Text('Guardar')),
        ],
      ),
    );
    cantidad.dispose();
    if (valor == null || !mounted) return;
    try {
      await conAcceso<bool>(context, ref, descripcion: 'contar "${a.nombre}"', requisito: Requisito.docente, accion: () async {
        await ref.read(repositorioProvider).contarEnInventario(widget.inventarioId, a.articuloId, valor, contenedorId: a.contenedorId);
        return true;
      });
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _escanearContenedor() async {
    final codigo = await context.push<String>('/escanear?devolver=1');
    if (codigo != null && mounted) setState(() => _contenedor = codigo.startsWith('C-') ? codigo : null);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty);
    final visibles = widget.articulos.where((a) {
      if (_contenedor != null && a.contenedorCodigo != _contenedor) return false;
      if (_soloSinContar && a.conteos > 0) return false;
      return palabras.every(normalizar('${a.codigo} ${a.nombre} ${a.ruta ?? ''} ${a.subcategoria ?? ''}').contains);
    }).toList();
    final contados = widget.articulos.where((a) => a.conteos > 0).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      LinearProgressIndicator(value: widget.articulos.isEmpty ? 0 : contados / widget.articulos.length),
      const SizedBox(height: 4),
      Text('Contados $contados de ${widget.articulos.length}${widget.abierto ? '' : ' · inventario cerrado'}', style: tema.textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Ico.buscar), hintText: 'Buscar', isDense: true),
            onChanged: (t) => setState(() => _texto = t),
          ),
        ),
        IconButton.filledTonal(icon: const Icon(Ico.escanear), tooltip: 'Escanear contenedor', onPressed: _escanearContenedor),
      ]),
      Wrap(spacing: 8, children: [
        FilterChip(label: const Text('Sin contar'), selected: _soloSinContar, onSelected: (v) => setState(() => _soloSinContar = v)),
        if (_contenedor != null) InputChip(label: Text('Contenedor $_contenedor'), onDeleted: () => setState(() => _contenedor = null)),
      ]),
      for (final a in visibles)
        ListTile(
          enabled: widget.abierto && !a.decidido,
          leading: Icon(a.conteos > 0 ? Ico.ok : Ico.sinMarcar, color: a.conteos > 0 ? tema.colorScheme.primary : null),
          title: Text(a.nombre),
          subtitle: Text([
            a.codigo,
            a.ruta ?? 'sin ubicación',
            if (a.miConteo != null) 'tu conteo: ${a.miConteo}',
            if (a.conteos > (a.miConteo == null ? 0 : 1)) 'también lo contó alguien más',
            if (a.decidido) 'ya revisado',
          ].join(' · ')),
          onTap: () => _contar(a),
        ),
    ]);
  }
}

class _Hallazgos extends ConsumerWidget {
  const _Hallazgos({required this.inventarioId, required this.lista, required this.recargar});

  final String inventarioId;
  final List<Hallazgo> lista;
  final Future<void> Function() recargar;

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final descripcion = TextEditingController();
    final fotos = <FotoNueva>[];
    Contenedor? contenedor;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Algo que no debería estar aquí'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: descripcion,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Qué es y cuántos *', hintText: 'Ej. 3 brocas sin registrar'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Contenedor?>(
                value: contenedor,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Dónde estaba'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin especificar')),
                  for (final c in (ref.read(contenedoresProvider).value ?? const <Contenedor>[]).where((c) => c.activo))
                    DropdownMenuItem(value: c, child: Text(c.ruta, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (c) => setState(() => contenedor = c),
              ),
              const SizedBox(height: 8),
              SelectorFotos(fotos: fotos, alCambiar: () => setState(() {}), maximo: 1),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar')),
          ],
        ),
      ),
    );
    final texto = descripcion.text.trim();
    descripcion.dispose();
    if (ok != true || texto.isEmpty || !context.mounted) return;
    try {
      await conAcceso<bool>(context, ref, descripcion: 'registrar un hallazgo', requisito: Requisito.docente, accion: () async {
        await ref.read(repositorioProvider).registrarHallazgo(inventarioId, texto, contenedorId: contenedor?.id, foto: fotos.firstOrNull);
        return true;
      });
      await recargar();
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  Future<void> _resolver(BuildContext context, WidgetRef ref, Hallazgo h, String decision) async {
    final nota = decision == 'IGNORADO' ? await pedirTexto(context, titulo: 'Sin acción', etiqueta: 'Por qué', boton: 'Guardar') : null;
    if (decision == 'IGNORADO' && nota == null) return;
    if (!context.mounted) return;
    try {
      await conAcceso<bool>(context, ref, descripcion: 'resolver el hallazgo', requisito: Requisito.administracion, accion: () async {
        await ref.read(repositorioProvider).resolverHallazgo(h.id, decision, nota);
        return true;
      });
      if (decision == 'ALTA' && context.mounted) await context.push('/articulo/nuevo');
      await recargar();
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final administra = ref.watch(sesionProvider).value?.administra ?? false;
    final repo = ref.read(repositorioProvider);
    return ListView(padding: const EdgeInsets.all(12), children: [
      FilledButton.tonalIcon(onPressed: () => _nuevo(context, ref), icon: const Icon(Ico.nuevo), label: const Text('Registrar hallazgo')),
      if (lista.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Sin hallazgos.')),
      for (final h in lista)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (h.foto != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(repo.urlFoto(h.foto!), width: 64, height: 64, fit: BoxFit.cover),
                  ),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.descripcion),
                  Text([h.contenedor ?? 'sin lugar', h.reportadoPor, fechaHora(h.reportadoEn)].join(' · '), style: Theme.of(context).textTheme.bodySmall),
                  if (h.decision != null)
                    Text(switch (h.decision) { 'ALTA' => 'Se dio de alta', 'MOVIDO' => 'Se movió', _ => 'Sin acción${h.nota == null ? '' : ': ${h.nota}'}' },
                        style: Theme.of(context).textTheme.bodySmall)
                  else if (administra)
                    Wrap(spacing: 8, children: [
                      TextButton(onPressed: () => _resolver(context, ref, h, 'ALTA'), child: const Text('Dar de alta')),
                      TextButton(onPressed: () => _resolver(context, ref, h, 'IGNORADO'), child: const Text('Sin acción')),
                    ]),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _Diferencias extends ConsumerStatefulWidget {
  const _Diferencias({required this.inventarioId, required this.lista, required this.recargar});

  final String inventarioId;
  final List<DiferenciaInventario> lista;
  final Future<void> Function() recargar;

  @override
  ConsumerState<_Diferencias> createState() => _DiferenciasState();
}

class _DiferenciasState extends ConsumerState<_Diferencias> {
  bool _soloPendientes = true;

  Future<void> _decidir(DiferenciaInventario x, String decision) async {
    String? nota;
    if (decision != 'RECONTAR' && (x.diferencia ?? 0) != 0) {
      nota = await pedirTexto(context,
          titulo: decision == 'AJUSTE' ? 'Aceptar la diferencia' : 'Reporte de pérdida',
          etiqueta: decision == 'AJUSTE' ? 'Por qué hay diferencia *' : 'Describe el faltante *',
          minimo: decision == 'AJUSTE' ? 1 : 15,
          boton: 'Guardar');
      if (nota == null) return;
    }
    if (!mounted) return;
    try {
      await conAcceso<bool>(context, ref, descripcion: 'decidir sobre "${x.nombre}"', requisito: Requisito.administracion, accion: () async {
        await ref.read(repositorioProvider).decidirEnInventario(widget.inventarioId, x.articuloId, decision, nota);
        return true;
      });
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _cerrar() async {
    try {
      final r = await conAcceso<Map<String, dynamic>>(context, ref,
          descripcion: 'cerrar el inventario',
          requisito: Requisito.administracionConfirmada,
          accion: () => ref.read(repositorioProvider).cerrarInventario(widget.inventarioId));
      if (r == null || !mounted) return;
      ref.invalidate(articulosProvider);
      ref.invalidate(pendientesAbiertosProvider);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Inventario cerrado'),
          content: Text('Contados: ${r['contados']} · Ajustes: ${r['ajustes']} · Reportes de pérdida: ${r['reportes']} · '
              'No contados: ${r['no_contados']}\n\nEl acta en PDF y el Excel se generan en la Fase 5.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
        ),
      );
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final lista = widget.lista;
    final visibles = _soloPendientes ? lista.where((x) => x.contados > 0 && (x.diferencia != 0 || x.conflicto)).toList() : lista;
    final pendientes = lista.where((x) => x.pendiente).length;
    final noContados = lista.where((x) => x.contados == 0).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('$pendientes por decidir · $noContados sin contar (quedarán como "no contados", no como cero)', style: tema.textTheme.titleSmall),
      SwitchListTile(
        value: _soloPendientes,
        onChanged: (v) => setState(() => _soloPendientes = v),
        title: const Text('Solo diferencias'),
        dense: true,
      ),
      for (final x in visibles)
        Card(
          color: x.conflicto ? tema.colorScheme.errorContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x.codigo} · ${x.nombre}', style: tema.textTheme.titleSmall),
              Text(x.ruta ?? 'sin ubicación', style: tema.textTheme.bodySmall),
              if (x.contados == 0)
                const Text('Sin contar')
              else ...[
                Text(x.conflicto
                    ? 'Los conteos no coinciden: ${x.contadores}'
                    : 'Sistema ${x.sistema} · contado ${x.fisico} · diferencia ${(x.diferencia ?? 0) > 0 ? '+' : ''}${x.diferencia}  (${x.contadores})'),
                if (x.decision != null) Text('Decisión: ${x.decision == 'AJUSTE' ? 'ajuste' : 'reporte de pérdida'}${x.nota == null ? '' : ' · ${x.nota}'}'),
                Wrap(spacing: 8, children: [
                  if (!x.conflicto && x.decision == null) ...[
                    FilledButton.tonal(onPressed: () => _decidir(x, 'AJUSTE'), child: const Text('Aceptar')),
                    if ((x.diferencia ?? 0) < 0) OutlinedButton(onPressed: () => _decidir(x, 'INCIDENCIA'), child: const Text('Reporte de pérdida')),
                  ],
                  TextButton(onPressed: () => _decidir(x, 'RECONTAR'), child: const Text('Recontar')),
                ]),
              ],
            ]),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: pendientes > 0 ? null : _cerrar,
        icon: const Icon(Ico.noSePresta),
        label: Text(pendientes > 0 ? 'Faltan $pendientes decisiones para cerrar' : 'Cerrar inventario'),
      ),
    ]);
  }
}
