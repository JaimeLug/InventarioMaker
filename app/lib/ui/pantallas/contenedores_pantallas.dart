import '../diseno/iconos.dart';
import '../componentes/componentes.dart';
import '../armazon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/contenedores.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

void _refrescar(WidgetRef ref) {
  ref.invalidate(contenedoresProvider);
  ref.invalidate(articulosProvider);
  ref.invalidate(porRevisarProvider);
}

/// Árbol de contenedores (F-12). Cualquiera lo consulta; solo administración da de alta.
class ContenedoresPantalla extends ConsumerStatefulWidget {
  const ContenedoresPantalla({super.key});

  @override
  ConsumerState<ContenedoresPantalla> createState() => _ContenedoresPantallaState();
}

class _ContenedoresPantallaState extends ConsumerState<ContenedoresPantalla> {
  final _buscador = TextEditingController();
  String _texto = '';
  bool _desactivados = false;

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contenedores = ref.watch(contenedoresProvider);
    final administra = ref.watch(sesionProvider).value?.administra ?? false;
    final articulos = ref.watch(articulosProvider).value ?? const <Articulo>[];
    final sinUbicar = articulos.where((a) => a.contenedorId == null).length;
    return TmArmazon(
      ruta: '/contenedores',
      titulo: 'Contenedores',
      fab: administra
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/contenedores/nuevo'),
              icon: const Icon(Ico.nuevo),
              label: const Text('Nuevo contenedor'),
            )
          : null,
      child: Centrado(
        child: Cargando<List<Contenedor>>(
          valor: contenedores,
          alReintentar: () => ref.invalidate(contenedoresProvider),
          datos: (todos) {
            final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty).toList();
            final visibles = todos
                .where((c) => _desactivados || c.activo)
                .where((c) => palabras.every(normalizar('${c.codigo} ${c.ruta} ${c.nota ?? ''}').contains))
                .toList();
            final arbol = comoArbol(visibles);
            return RefreshIndicator(
              onRefresh: () async => _refrescar(ref),
              child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TmBuscador(
                    controlador: _buscador,
                    pista: 'Buscar por nombre o código',
                    onCambio: (t) => setState(() => _texto = t),
                  ),
                ),
                if (sinUbicar > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TmAlerta(
                      titulo: '$sinUbicar artículo${sinUbicar == 1 ? '' : 's'} sin ubicación',
                      texto: administra ? 'Abre un contenedor y toca "Agregar artículos".' : 'Todavía no se acomodan en un contenedor.',
                      tono: Tono.aviso,
                      icono: Ico.ubicacion,
                    ),
                  ),
                SwitchListTile(
                  value: _desactivados,
                  onChanged: (v) => setState(() => _desactivados = v),
                  title: const Text('Mostrar desactivados'),
                  dense: true,
                ),
                if (todos.isEmpty)
                  TmVacio(
                    icono: Ico.contenedores,
                    titulo: 'Todavía no hay contenedores',
                    texto: administra
                        ? 'Empieza por los gabinetes y después sus cajones: así cada artículo tiene dónde vivir.'
                        : 'Cuando el responsable los registre, aparecen aquí.',
                    acciones: [
                      if (administra) TmBoton('Nuevo contenedor', tipo: TipoBoton.secundario, icono: Ico.nuevo, onTap: () => context.push('/contenedores/nuevo')),
                    ],
                  ),
                for (final (c, nivel) in arbol)
                  ListTile(
                    contentPadding: EdgeInsets.only(left: 16.0 + nivel * 24, right: 16),
                    leading: Icon(nivel == 0 ? Ico.caja : Ico.subnivel,
                        color: c.activo ? null : Theme.of(context).colorScheme.outline),
                    title: Text(c.nombre, style: c.activo ? null : TextStyle(color: Theme.of(context).colorScheme.outline)),
                    subtitle: Text([
                      c.codigo,
                      c.nombreTipo,
                      if (c.categoriaExclusiva != null) c.nombreCategoria,
                      '${c.articulos} artículo${c.articulos == 1 ? '' : 's'}',
                      if (!c.activo) 'desactivado',
                    ].join(' · ')),
                    trailing: const Icon(Ico.avanzar),
                    onTap: () => context.push('/contenedor/${c.codigo}'),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Lo que hay en un contenedor (F-03): se llega escaneando su QR.
class ContenedorPantalla extends ConsumerStatefulWidget {
  const ContenedorPantalla({super.key, required this.codigo});

  final String codigo;

  @override
  ConsumerState<ContenedorPantalla> createState() => _ContenedorPantallaState();
}

class _ContenedorPantallaState extends ConsumerState<ContenedorPantalla> {
  bool _seleccionando = false;
  final _elegidos = <String, int>{};

  Future<void> _agregarArticulos(Contenedor c, List<Articulo> todos) async {
    final sesion = await ref.read(sesionProvider.future);
    if (!mounted) return;
    final administra = sesion?.administra ?? false;
    final elegidos = await showModalBottomSheet<List<Articulo>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ElegirArticulos(contenedor: c, todos: todos),
    );
    if (elegidos == null || elegidos.isEmpty || !mounted) return;
    try {
      if (administra || sesion == null) {
        final n = await conAcceso<int>(context, ref,
            descripcion: 'acomodar ${elegidos.length} artículo${elegidos.length == 1 ? '' : 's'} en ${c.codigo}',
            requisito: Requisito.administracion,
            accion: () => ref.read(repositorioProvider).acomodar([for (final a in elegidos) a.id], c.id));
        if (n != null && mounted) avisar(context, 'Listo: $n artículo${n == 1 ? '' : 's'} en ${c.nombre}.');
      } else {
        final hecho = await conAcceso<bool>(context, ref, descripcion: 'proponer que están en ${c.codigo}', requisito: Requisito.cualquiera,
            accion: () async {
          for (final a in elegidos) {
            await ref.read(repositorioProvider).proponerUbicacion(a.id, c.id, null);
          }
          return true;
        });
        if (hecho == true && mounted) avisar(context, 'Propuesta enviada al responsable del laboratorio.');
      }
      _refrescar(ref);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _quitar(Contenedor c, Articulo a) async {
    final destino = await elegirContenedor(context, ref, para: a.categoria, excluir: c.id, titulo: 'Mover "${a.nombre}" a…', permitirNinguno: true);
    if (destino == null || !mounted) return;
    try {
      await conAcceso<int>(context, ref,
          descripcion: 'mover "${a.nombre}"',
          requisito: Requisito.administracion,
          accion: () => ref.read(repositorioProvider).acomodar([a.id], destino.id.isEmpty ? null : destino.id));
      _refrescar(ref);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _activar(Contenedor c) async {
    try {
      final hecho = await conAcceso<bool>(context, ref,
          descripcion: '${c.activo ? 'desactivar' : 'reactivar'} ${c.codigo}', requisito: Requisito.administracion, accion: () async {
        await ref.read(repositorioProvider).activarContenedor(c.id, !c.activo);
        return true;
      });
      if (hecho == true && mounted) {
        _refrescar(ref);
        avisar(context, c.activo ? 'Contenedor desactivado.' : 'Contenedor reactivado.');
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contenedores = ref.watch(contenedoresProvider);
    final articulos = ref.watch(articulosProvider).value ?? const <Articulo>[];
    final sesion = ref.watch(sesionProvider).value;
    final administra = sesion?.administra ?? false;
    final tema = Theme.of(context);
    final c = contenedores.value?.where((x) => x.codigo == widget.codigo.toUpperCase()).firstOrNull;

    if (c == null) {
      return TmArmazon(
               ruta: '/contenedores',
               titulo: widget.codigo,
               conRegresar: true,
               child: contenedores.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('La etiqueta ${widget.codigo} no está registrada.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => context.go('/contenedores'), child: const Text('Ver contenedores')),
                ]),
              ),
             );
    }

    final hijos = (contenedores.value ?? const <Contenedor>[]).where((h) => h.padreId == c.id && h.activo).toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    final aqui = articulos.where((a) => a.contenedorId == c.id).toList()..sort((a, b) => a.nombre.compareTo(b.nombre));
    final fueraDeLugar = aqui.where((a) => !c.acepta(a.categoria) && a.categoria != Categoria.sinClasificar).toList();
    final hayPrestado = aqui.any((a) => a.prestado > 0);
    final elegidosPrestables = aqui.where((a) => _elegidos.containsKey(a.id)).toList();
    final piezas = _elegidos.values.fold(0, (s, v) => s + v);

    return TmArmazon(
             ruta: '/contenedores',
             titulo: c.codigo,
             conRegresar: true,
             acciones: [if (administra)
            PopupMenuButton<String>(
              onSelected: (o) => switch (o) {
                'editar' => context.push('/contenedor/${c.codigo}/editar'),
                'adentro' => context.push('/contenedores/nuevo?padre=${c.id}'),
                'etiqueta' => context.push('/etiquetas?codigos=${c.codigo}'),
                _ => _activar(c),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'editar', child: ListTile(leading: Icon(Ico.editar), title: Text('Editar'))),
                if (c.activo)
                  const PopupMenuItem(
                      value: 'adentro', child: ListTile(leading: Icon(Ico.nuevaCarpeta), title: Text('Nuevo contenedor adentro'))),
                const PopupMenuItem(value: 'etiqueta', child: ListTile(leading: Icon(Ico.qr), title: Text('Imprimir etiqueta'))),
                PopupMenuItem(
                    value: 'activo',
                    child: ListTile(leading: Icon(c.activo ? Ico.desactivar : Ico.reactivar), title: Text(c.activo ? 'Desactivar' : 'Reactivar'))),
              ],
            )],
             barraInferior: !_seleccionando
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: Text('${elegidosPrestables.length} artículo${elegidosPrestables.length == 1 ? '' : 's'}, $piezas pieza${piezas == 1 ? '' : 's'}')),
                  FilledButton.icon(
                    onPressed: _elegidos.isEmpty
                        ? null
                        : () async {
                            final prestado = await context.push<bool>('/prestar?lineas=${_elegidos.entries.map((e) => '${e.key}:${e.value}').join(',')}');
                            // Ya prestado: se limpia la selección para no volver a prestar lo mismo.
                            if (prestado == true && mounted) {
                              setState(() {
                                _seleccionando = false;
                                _elegidos.clear();
                              });
                            }
                          },
                    icon: const Icon(Ico.prestar),
                    label: const Text('Prestar'),
                  ),
                ]),
              ),
            ),
             child: Centrado(
        child: RefreshIndicator(
          onRefresh: () async => _refrescar(ref),
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            if (!c.activo) const MaterialBanner(content: Text('Contenedor desactivado.'), leading: Icon(Ico.desactivar), actions: [SizedBox.shrink()]),
            if (c.foto != null)
              SizedBox(
                height: 200,
                child: Image.network(ref.read(repositorioProvider).urlFoto(c.foto!), fit: BoxFit.cover, width: double.infinity,
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.nombre, style: tema.textTheme.headlineSmall),
                Text(c.ruta, style: tema.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Insignia(c.nombreTipo, color: tema.colorScheme.primary),
                  Insignia(c.nombreCategoria,
                      color: c.categoriaExclusiva == null ? tema.colorScheme.outline : Avisos.estimado, icono: Ico.categoria),
                ]),
                if (c.nota != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.nota!)),
              ]),
            ),
            for (final a in fueraDeLugar)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                color: tema.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Ico.aviso),
                  title: Text('Aquí hay un artículo ${a.categoria.nombre} en un contenedor ${c.nombreCategoria.toLowerCase()}: "${a.nombre}". Muévelo.'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (c.activo)
                  FilledButton.tonalIcon(
                    onPressed: () => _agregarArticulos(c, articulos),
                    icon: const Icon(Ico.agregarALista),
                    label: Text(administra || sesion == null ? 'Agregar artículos' : 'Aquí hay algo que falta en la lista'),
                  ),
                if (aqui.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _seleccionando = !_seleccionando;
                      _elegidos.clear();
                    }),
                    icon: Icon(_seleccionando ? Ico.cerrar : Ico.contar),
                    label: Text(_seleccionando ? 'Terminar selección' : 'Prestar varios'),
                  ),
                if (hayPrestado)
                  OutlinedButton.icon(
                    onPressed: () => context.push('/contenedor/${c.codigo}/devolver'),
                    icon: const Icon(Ico.devolver),
                    label: const Text('Devolver varios'),
                  ),
              ]),
            ),
            if (hijos.isNotEmpty) ...[
              const _Titulo('Contenedores adentro'),
              for (final h in hijos)
                ListTile(
                  leading: const Icon(Ico.carpeta),
                  title: Text(h.nombre),
                  subtitle: Text('${h.codigo} · ${h.articulos} artículo${h.articulos == 1 ? '' : 's'}'),
                  trailing: const Icon(Ico.avanzar),
                  onTap: () => context.push('/contenedor/${h.codigo}'),
                ),
            ],
            _Titulo('Artículos (${aqui.length})'),
            if (aqui.isEmpty) const ListTile(title: Text('Este contenedor no tiene artículos registrados.')),
            for (final a in aqui)
              if (_seleccionando)
                _RenglonSeleccion(
                  articulo: a,
                  cantidad: _elegidos[a.id],
                  alCambiar: (v) => setState(() => v == null ? _elegidos.remove(a.id) : _elegidos[a.id] = v),
                )
              else
                ListTile(
                  leading: Miniatura(ruta: a.fotoPrincipal, tamano: 44),
                  title: Text(a.nombre),
                  subtitle: Text('${a.codigo} · ${a.cantidadMostrada} · ${a.disponibilidad}'),
                  onTap: () => context.push('/articulo/${a.id}'),
                  trailing: administra
                      ? IconButton(icon: const Icon(Ico.mover), tooltip: 'Mover', onPressed: () => _quitar(c, a))
                      : null,
                ),
          ]),
        ),
      ),
           );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(texto, style: Theme.of(context).textTheme.titleMedium));
}

class _RenglonSeleccion extends StatelessWidget {
  const _RenglonSeleccion({required this.articulo, required this.cantidad, required this.alCambiar});

  final Articulo articulo;
  final int? cantidad;
  final ValueChanged<int?> alCambiar;

  @override
  Widget build(BuildContext context) {
    final a = articulo;
    final prestable = a.prestable && a.disponible > 0 && !a.esConsumible;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Checkbox(value: cantidad != null, onChanged: prestable ? (v) => alCambiar(v == true ? 1 : null) : null),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.nombre),
            Text(prestable ? a.disponibilidad : (a.esConsumible ? 'Consumible: se registra su uso' : a.disponibilidad),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (cantidad != null) SelectorCantidad(valor: cantidad!, minimo: 1, maximo: a.disponible, alCambiar: alCambiar),
      ]),
    );
  }
}

/// Elegir varios artículos para acomodar en un contenedor. Los de otra categoría no se pueden elegir.
class ElegirArticulos extends StatefulWidget {
  const ElegirArticulos({super.key, required this.contenedor, required this.todos});

  final Contenedor contenedor;
  final List<Articulo> todos;

  @override
  State<ElegirArticulos> createState() => _ElegirArticulosState();
}

class _ElegirArticulosState extends State<ElegirArticulos> {
  String _texto = '';
  bool _soloSinUbicar = true;
  final _elegidos = <String>{};

  @override
  Widget build(BuildContext context) {
    final c = widget.contenedor;
    final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty);
    final lista = widget.todos
        .where((a) => a.activo && a.contenedorId != c.id)
        .where((a) => !_soloSinUbicar || a.contenedorId == null)
        .where((a) => palabras.every(a.textoBusqueda.contains))
        .toList()
      ..sort((a, b) => (c.acepta(b.categoria) ? 1 : 0).compareTo(c.acepta(a.categoria) ? 1 : 0));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Agregar a ${c.nombre} (${c.nombreCategoria.toLowerCase()})', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Ico.buscar), hintText: 'Buscar artículo'),
              onChanged: (t) => setState(() => _texto = t),
            ),
          ),
          CheckboxListTile(
            value: _soloSinUbicar,
            onChanged: (v) => setState(() => _soloSinUbicar = v ?? true),
            title: const Text('Solo los que no tienen ubicación'),
            dense: true,
          ),
          Expanded(
            child: ListView(children: [
              for (final a in lista.take(200))
                CheckboxListTile(
                  value: _elegidos.contains(a.id),
                  onChanged: c.acepta(a.categoria) ? (v) => setState(() => v == true ? _elegidos.add(a.id) : _elegidos.remove(a.id)) : null,
                  secondary: Miniatura(ruta: a.fotoPrincipal, tamano: 40),
                  title: Text(a.nombre),
                  subtitle: Text([
                    a.codigo,
                    a.categoria.nombre,
                    if (a.ubicacion != null) 'ahora en ${a.ubicacion}',
                    if (!c.acepta(a.categoria)) 'no va en un contenedor ${c.nombreCategoria.toLowerCase()}',
                  ].join(' · ')),
                ),
            ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _elegidos.isEmpty ? null : () => Navigator.pop(context, widget.todos.where((a) => _elegidos.contains(a.id)).toList()),
                  child: Text('Agregar ${_elegidos.length}'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Elegir un contenedor (mover un artículo, contenedor de arriba). Con [permitirNinguno], la opción
/// "Sin ubicación" regresa un contenedor con id vacío.
Future<Contenedor?> elegirContenedor(BuildContext context, WidgetRef ref,
    {Categoria? para, String? excluir, required String titulo, bool permitirNinguno = false}) async {
  final todos = await ref.read(contenedoresProvider.future);
  if (!context.mounted) return null;
  return showModalBottomSheet<Contenedor>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ElegirContenedor(todos: todos, para: para, excluir: excluir, titulo: titulo, permitirNinguno: permitirNinguno),
  );
}

class _ElegirContenedor extends StatefulWidget {
  const _ElegirContenedor({required this.todos, required this.titulo, required this.permitirNinguno, this.para, this.excluir});

  final List<Contenedor> todos;
  final Categoria? para;
  final String? excluir;
  final String titulo;
  final bool permitirNinguno;

  @override
  State<_ElegirContenedor> createState() => _ElegirContenedorState();
}

class _ElegirContenedorState extends State<_ElegirContenedor> {
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty);
    final activos = widget.todos.where((c) => c.activo && c.id != widget.excluir).toList();
    final arbol = comoArbol(activos).where((e) => palabras.every(normalizar('${e.$1.codigo} ${e.$1.ruta}').contains));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(widget.titulo, style: Theme.of(context).textTheme.titleMedium)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Ico.buscar), hintText: 'Buscar contenedor'),
              onChanged: (t) => setState(() => _texto = t),
            ),
          ),
          Expanded(
            child: ListView(children: [
              if (widget.permitirNinguno)
                ListTile(
                  leading: const Icon(Ico.sinUbicacion),
                  title: const Text('Sin ubicación'),
                  onTap: () => Navigator.pop(
                      context, const Contenedor(id: '', codigo: '', nombre: '', tipo: 'OTRO', activo: true, ruta: '', articulos: 0, subcontenedores: 0)),
                ),
              for (final (c, nivel) in arbol)
                ListTile(
                  contentPadding: EdgeInsets.only(left: 16.0 + nivel * 20, right: 16),
                  enabled: widget.para == null || c.acepta(widget.para!),
                  title: Text(c.nombre),
                  subtitle: Text([
                    c.codigo,
                    c.nombreCategoria,
                    if (widget.para != null && !c.acepta(widget.para!)) 'no acepta ${widget.para!.nombre}',
                  ].join(' · ')),
                  onTap: () => Navigator.pop(context, c),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Alta y edición de un contenedor (F-12).
class ContenedorFormPantalla extends ConsumerStatefulWidget {
  const ContenedorFormPantalla({super.key, this.codigo, this.padreId});

  final String? codigo;
  final String? padreId;

  @override
  ConsumerState<ContenedorFormPantalla> createState() => _ContenedorFormPantallaState();
}

class _ContenedorFormPantallaState extends ConsumerState<ContenedorFormPantalla> {
  final _form = GlobalKey<FormState>();
  final _id = const Uuid().v4();
  final _nombre = TextEditingController();
  final _nota = TextEditingController();
  final _fotos = <FotoNueva>[];
  String _tipo = 'CAJON';
  Categoria? _categoria;
  Contenedor? _padre;
  Contenedor? _actual;
  bool _cargado = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _nota.dispose();
    super.dispose();
  }

  void _cargar(List<Contenedor> todos) {
    if (_cargado) return;
    _cargado = true;
    if (widget.codigo != null) {
      final c = todos.where((x) => x.codigo == widget.codigo).firstOrNull;
      if (c == null) return;
      _actual = c;
      _nombre.text = c.nombre;
      _nota.text = c.nota ?? '';
      _tipo = c.tipo;
      _categoria = c.categoriaExclusiva;
      _padre = todos.where((x) => x.id == c.padreId).firstOrNull;
    } else if (widget.padreId != null) {
      _padre = todos.where((x) => x.id == widget.padreId).firstOrNull;
      _categoria = _padre?.categoriaExclusiva;
    }
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final repo = ref.read(repositorioProvider);
    try {
      final codigo = await conAcceso<String>(context, ref,
          descripcion: _actual == null ? 'dar de alta un contenedor' : 'editar ${_actual!.codigo}',
          requisito: Requisito.administracion, accion: () async {
        final nota = _nota.text.trim().isEmpty ? null : _nota.text.trim();
        if (_actual == null) {
          return repo.crearContenedor(
              id: _id, nombre: _nombre.text.trim(), tipo: _tipo, padreId: _padre?.id, categoria: _categoria,
              foto: _fotos.firstOrNull, nota: nota);
        }
        await repo.editarContenedor(_actual!,
            nombre: _nombre.text.trim(), tipo: _tipo, padreId: _padre?.id, categoria: _categoria, foto: _fotos.firstOrNull, nota: nota);
        return _actual!.codigo;
      });
      if (codigo == null || !mounted) return;
      ref.invalidate(contenedoresProvider);
      ref.invalidate(articulosProvider);
      avisar(context, _actual == null ? 'Contenedor $codigo creado.' : 'Guardado.');
      if (_actual == null) {
        context.pushReplacement('/contenedor/$codigo');
      } else {
        context.pop();
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contenedores = ref.watch(contenedoresProvider);
    return TmArmazon(
             ruta: '/contenedores',
             titulo: widget.codigo == null ? 'Nuevo contenedor' : 'Editar ${widget.codigo}',
             conRegresar: true,
             barraInferior: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
        ),
      ),
             child: Centrado(
        child: Cargando<List<Contenedor>>(
          valor: contenedores,
          datos: (todos) {
            _cargar(todos);
            return Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej. Gabinete 2, Cajón B, Bolsa de tornillos'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre.' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [for (final t in tiposContenedor.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
                  onChanged: (t) => setState(() => _tipo = t ?? 'CAJON'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Ico.arbol),
                  title: Text(_padre == null ? 'En la raíz (no está dentro de otro)' : 'Dentro de: ${_padre!.ruta}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final p = await elegirContenedor(context, ref,
                          excluir: _actual?.id, titulo: '¿Dentro de qué contenedor está?', permitirNinguno: true);
                      if (p != null) setState(() => _padre = p.id.isEmpty ? null : p);
                    },
                    child: const Text('Cambiar'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Qué puede guardar', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<Categoria?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('Mixto')),
                    ButtonSegment(value: Categoria.vex, label: Text('Solo VEX')),
                    ButtonSegment(value: Categoria.ftc, label: Text('Solo FTC')),
                  ],
                  selected: {_categoria},
                  onSelectionChanged: (s) => setState(() => _categoria = s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  _categoria == null
                      ? 'Mixto: herramientas, común y consumibles. Las piezas de VEX y FTC necesitan su propio contenedor.'
                      : 'Solo ${_categoria!.nombre}: la app no deja guardar aquí nada de otra categoría.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nota,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej. Junto a la ventana, con candado'),
                ),
                const SizedBox(height: 16),
                Text(_actual?.foto == null ? 'Foto (recomendada)' : 'Cambiar foto', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectorFotos(fotos: _fotos, alCambiar: () => setState(() {}), maximo: 1),
              ]),
            );
          },
        ),
      ),
           );
  }
}

/// Devolver varios artículos de un contenedor a la vez (F-03). Solo los que regresan bien;
/// si algo viene dañado o incompleto, se recibe desde su ficha.
class DevolverVariosPantalla extends ConsumerWidget {
  const DevolverVariosPantalla({super.key, required this.codigo});

  final String codigo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(contenedoresProvider).value?.where((x) => x.codigo == codigo).firstOrNull;
    return TmArmazon(
             ruta: '/contenedores',
             titulo: 'Devolver en $codigo',
             conRegresar: true,
             child: Centrado(
        child: c == null
            ? const Center(child: CircularProgressIndicator())
            : CargaConAcceso<List<PrestamoListado>>(
                descripcion: 'recibir devoluciones',
                requisito: Requisito.docente,
                cargar: (repo) => repo.prestamosDeContenedor(c.id),
                construir: (context, lista, recargar) => _DevolverVarios(lista: lista, recargar: recargar),
              ),
      ),
           );
  }
}

class _DevolverVarios extends ConsumerStatefulWidget {
  const _DevolverVarios({required this.lista, required this.recargar});

  final List<PrestamoListado> lista;
  final Future<void> Function() recargar;

  @override
  ConsumerState<_DevolverVarios> createState() => _DevolverVariosState();
}

class _DevolverVariosState extends ConsumerState<_DevolverVarios> {
  final _regresan = <String, int>{};
  String _comando = const Uuid().v4();
  bool _guardando = false;

  Future<void> _guardar() async {
    final lineas = {for (final e in _regresan.entries) if (e.value > 0) e.key: e.value};
    if (lineas.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: 'recibir ${lineas.length} devolución(es)', requisito: Requisito.docente,
          accion: () async {
        await ref.read(repositorioProvider).devolverVarios(lineas, _comando);
        return true;
      });
      if (hecho != true || !mounted) return;
      for (final p in widget.lista) {
        refrescarArticulo(ref, p.articuloId);
      }
      avisar(context, 'Devolución registrada.');
      setState(() {
        _regresan.clear();
        _comando = const Uuid().v4();
      });
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    if (widget.lista.isEmpty) {
      return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hay nada prestado de este contenedor.')))]);
    }
    final total = _regresan.values.fold(0, (s, v) => s + v);
    return ListView(padding: const EdgeInsets.all(12), children: [
      const ListTile(
        leading: Icon(Ico.info),
        title: Text('Marca lo que regresa en buen estado. Si algo viene dañado o incompleto, recíbelo desde la ficha del artículo.'),
      ),
      for (final p in widget.lista)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nombre, style: tema.textTheme.titleSmall),
                  Text('${p.aCargo} · debe ${conUnidad(p.pendiente, p.unidad)}', style: tema.textTheme.bodySmall),
                  Text('${p.vencido ? 'VENCIDO desde' : 'Vence'} ${fechaHora(p.venceEn)}',
                      style: tema.textTheme.bodySmall?.copyWith(color: p.vencido ? tema.colorScheme.error : null)),
                  TextButton(onPressed: () => context.push('/articulo/${p.articuloId}/devolver'), child: const Text('Viene dañado o incompleto')),
                ]),
              ),
              SelectorCantidad(
                valor: _regresan[p.id] ?? 0,
                maximo: p.pendiente,
                alCambiar: (v) => setState(() => _regresan[p.id] = v),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _guardando || total == 0 ? null : _guardar,
        icon: const Icon(Ico.devolver),
        label: Text(total == 0 ? 'Marca lo que regresa' : 'Recibir $total pieza${total == 1 ? '' : 's'}'),
      ),
    ]);
  }
}
