import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../datos/proveedores.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';

/// Consulta libre (F-01): cualquiera, sin cuenta.
class InicioPantalla extends ConsumerStatefulWidget {
  const InicioPantalla({super.key});

  @override
  ConsumerState<InicioPantalla> createState() => _InicioPantallaState();
}

class _InicioPantallaState extends ConsumerState<InicioPantalla> {
  final _busqueda = TextEditingController();
  Categoria? _categoria;
  bool _conPendientes = false;
  bool _disponibles = false;
  bool _sinFoto = false;
  bool _porContar = false;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  List<Articulo> _filtrar(List<Articulo> todos) {
    final palabras = normalizar(_busqueda.text).split(' ').where((p) => p.isNotEmpty).toList();
    return todos.where((a) {
      if (_categoria != null && a.categoria != _categoria) return false;
      if (_conPendientes && a.pendientesAbiertos == 0) return false;
      if (_disponibles && (!a.prestable || a.disponible <= 0)) return false;
      if (_sinFoto && a.fotoPrincipal != null) return false;
      if (_porContar && !(a.cantidadEstimada || a.conteoDesconocido)) return false;
      return palabras.every(a.textoBusqueda.contains);
    }).toList();
  }

  void _limpiar() => setState(() {
        _busqueda.clear();
        _categoria = null;
        _conPendientes = _disponibles = _sinFoto = _porContar = false;
      });

  @override
  Widget build(BuildContext context) {
    final articulos = ref.watch(articulosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventario Maker'), actions: const [BarraSesion()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/articulo/nuevo'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo artículo'),
      ),
      body: Centrado(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(articulosProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _busqueda,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, marca, código, serie…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _busqueda.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear), tooltip: 'Borrar', onPressed: () => setState(_busqueda.clear)),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    ChoiceChip(label: const Text('Todas'), selected: _categoria == null, onSelected: (_) => setState(() => _categoria = null)),
                    for (final c in Categoria.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(c.nombre),
                          selected: _categoria == c,
                          onSelected: (s) => setState(() => _categoria = s ? c : null),
                        ),
                      ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    FilterChip(label: const Text('Disponible ahora'), selected: _disponibles, onSelected: (v) => setState(() => _disponibles = v)),
                    const SizedBox(width: 8),
                    FilterChip(label: const Text('Con pendientes'), selected: _conPendientes, onSelected: (v) => setState(() => _conPendientes = v)),
                    const SizedBox(width: 8),
                    FilterChip(label: const Text('Por contar'), selected: _porContar, onSelected: (v) => setState(() => _porContar = v)),
                    const SizedBox(width: 8),
                    FilterChip(label: const Text('Sin foto'), selected: _sinFoto, onSelected: (v) => setState(() => _sinFoto = v)),
                  ]),
                ),
              ),
              ...articulos.when(
                loading: () => [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [
                  SliverFillRemaining(
                    child: Cargando<void>(valor: AsyncError(e, StackTrace.current), datos: (_) => const SizedBox(),
                        alReintentar: () => ref.invalidate(articulosProvider)),
                  ),
                ],
                data: (todos) {
                  final lista = _filtrar(todos);
                  return [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Text(
                          lista.length == todos.length ? '${todos.length} artículos' : '${lista.length} de ${todos.length} artículos',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                    if (lista.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('No encontramos nada con esa búsqueda.'),
                            const SizedBox(height: 12),
                            OutlinedButton(onPressed: _limpiar, child: const Text('Quitar filtros')),
                          ]),
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
                        itemBuilder: (_, i) => _Renglon(articulo: lista[i]),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context) {
    final a = articulo;
    final tema = Theme.of(context);
    final detalle = [a.marcaModelo, a.ubicacion].whereType<String>().where((t) => t.isNotEmpty).join(' · ');
    final insignias = insigniasDe(a);

    return InkWell(
      onTap: () => context.push('/articulo/${a.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Miniatura(ruta: a.fotoPrincipal),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.nombre, style: tema.textTheme.titleMedium),
              if (detalle.isNotEmpty) Text(detalle, style: tema.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Text('${a.codigo} · ${a.categoria.nombre}', style: tema.textTheme.labelSmall),
                ...insignias,
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(a.cantidadMostrada, style: tema.textTheme.titleSmall),
            Text(
              a.disponibilidad,
              style: tema.textTheme.bodySmall?.copyWith(
                color: a.prestable && a.disponible > 0 ? tema.colorScheme.primary : tema.colorScheme.outline,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
