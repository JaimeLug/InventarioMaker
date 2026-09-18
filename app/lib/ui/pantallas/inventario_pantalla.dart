import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../datos/proveedores.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../util/texto.dart';
import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';
import '../widgets/comunes.dart';

enum _Vista { tabla, tarjetas }

/// Consulta del inventario (F-01): cualquiera, con o sin cuenta.
class InventarioPantalla extends ConsumerStatefulWidget {
  const InventarioPantalla({super.key, this.enTablero = false});

  /// Cuando el catálogo se muestra dentro de otra pantalla (sin sesión) no repite el armazón.
  final bool enTablero;

  @override
  ConsumerState<InventarioPantalla> createState() => _InventarioPantallaState();
}

class _InventarioPantallaState extends ConsumerState<InventarioPantalla> {
  final _busqueda = TextEditingController();
  Categoria? _categoria;
  String? _rama;
  bool _disponibles = false;
  bool _conPendientes = false;
  bool _porContar = false;
  bool _sinUbicacion = false;
  bool _sinFoto = false;
  bool _enMinimo = false;
  _Vista _vista = _Vista.tabla;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  bool get _hayFiltros =>
      _busqueda.text.isNotEmpty || _categoria != null || _rama != null || _disponibles || _conPendientes || _porContar || _sinUbicacion || _sinFoto || _enMinimo;

  void _limpiar() => setState(() {
        _busqueda.clear();
        _categoria = null;
        _rama = null;
        _disponibles = _conPendientes = _porContar = _sinUbicacion = _sinFoto = _enMinimo = false;
      });

  List<Articulo> _filtrar(List<Articulo> todos) {
    final palabras = normalizar(_busqueda.text).split(' ').where((p) => p.isNotEmpty).toList();
    return todos.where((a) {
      if (_categoria != null && a.categoria != _categoria) return false;
      if (_rama != null && a.subcategoria != _rama) return false;
      if (_conPendientes && a.pendientesAbiertos == 0) return false;
      if (_disponibles && (!a.prestable || a.disponible <= 0)) return false;
      if (_enMinimo && SituacionStock.de(a) != SituacionStock.enMinimo && SituacionStock.de(a) != SituacionStock.agotado) return false;
      if (_sinFoto && a.fotoPrincipal != null) return false;
      if (_sinUbicacion && a.contenedorId != null) return false;
      if (_porContar && !(a.cantidadEstimada || a.conteoDesconocido)) return false;
      return palabras.every(a.textoBusqueda.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final articulos = ref.watch(articulosProvider);
    final administra = ref.watch(sesionProvider).value?.administra ?? false;
    final ancho = MediaQuery.sizeOf(context).width;
    final riel = ancho >= Quiebre.lateral;
    final compacto = ancho < Quiebre.compacto;

    final cuerpo = RefreshIndicator(
      onRefresh: () {
        ref.invalidate(vencidosProvider);
        ref.invalidate(porRevisarProvider);
        ref.invalidate(pendientesAbiertosProvider);
        return ref.refresh(articulosProvider.future);
      },
      child: articulos.when(
        loading: () => ListView(padding: const EdgeInsets.all(Espacio.x4), children: const [TmCargandoLista()]),
        error: (e, _) => ListView(children: [
          TmErrorCarga(
            mensaje: 'No se pudo leer el inventario. Revisa la conexión; lo que hayas capturado no se pierde.',
            onReintentar: () => ref.invalidate(articulosProvider),
          ),
        ]),
        data: (todos) {
          final lista = _filtrar(todos);
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _barraHerramientas(todos, compacto, riel)),
            if (lista.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: TmVacio(
                  icono: _hayFiltros ? Ico.sinResultados : Ico.vacio,
                  titulo: _hayFiltros ? 'Sin resultados${_busqueda.text.isEmpty ? '' : ' para “${_busqueda.text}”'}' : 'Todavía no hay artículos',
                  texto: _hayFiltros
                      ? 'Revisa cómo se escribe, busca por código (A-0214) o por marca, o quita los filtros.'
                      : 'Da de alta el primero o importa el Excel del levantamiento.',
                  acciones: [
                    if (_hayFiltros) TmBoton('Quitar filtros', icono: Ico.cerrar, onTap: _limpiar),
                    if (administra) TmBoton('Nuevo artículo', tipo: TipoBoton.secundario, icono: Ico.nuevo, onTap: () => context.push('/articulo/nuevo')),
                  ],
                ),
              )
            else if (_vista == _Vista.tabla && !compacto)
              SliverToBoxAdapter(child: _Tabla(lista: lista))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Espacio.x4, 0, Espacio.x4, Espacio.x4),
                sliver: compacto
                    ? SliverList.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Espacio.x2),
                        itemBuilder: (_, i) => _TarjetaArticulo(articulo: lista[i]),
                      )
                    : SliverGrid.builder(
                        itemCount: lista.length,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320, mainAxisSpacing: Espacio.x3, crossAxisSpacing: Espacio.x3, mainAxisExtent: 172),
                        itemBuilder: (_, i) => _TarjetaArticulo(articulo: lista[i]),
                      ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Espacio.x4),
                child: Text(
                  lista.length == todos.length ? '${todos.length} artículos' : '${lista.length} de ${todos.length} artículos',
                  style: Tipografia.chico.copyWith(color: context.tm.textoTenue),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ]);
        },
      ),
    );

    final conRiel = riel
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 250,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Espacio.x4, Espacio.x4, 0, Espacio.x4),
                child: _RielFiltros(
                  todos: articulos.value ?? const [],
                  categoria: _categoria,
                  disponibles: _disponibles,
                  enMinimo: _enMinimo,
                  conPendientes: _conPendientes,
                  porContar: _porContar,
                  sinUbicacion: _sinUbicacion,
                  sinFoto: _sinFoto,
                  onCategoria: (c) => setState(() {
                    _categoria = c;
                    _rama = null;
                  }),
                  onFiltro: (cual, valor) => setState(() => switch (cual) {
                        'disponibles' => _disponibles = valor,
                        'minimo' => _enMinimo = valor,
                        'pendientes' => _conPendientes = valor,
                        'contar' => _porContar = valor,
                        'ubicacion' => _sinUbicacion = valor,
                        _ => _sinFoto = valor,
                      }),
                  onLimpiar: _hayFiltros ? _limpiar : null,
                ),
              ),
            ),
            Expanded(child: cuerpo),
          ])
        : cuerpo;

    if (widget.enTablero) return conRiel;
    return TmArmazon(
      ruta: '/inventario',
      titulo: 'Inventario',
      fab: administra && compacto
          ? FloatingActionButton(
              onPressed: () => context.push('/articulo/nuevo'),
              tooltip: 'Nuevo artículo',
              child: const Icon(Ico.nuevo),
            )
          : null,
      acciones: [
        if (administra && !compacto)
          Padding(
            padding: const EdgeInsets.only(right: Espacio.x2),
            child: TmBoton('Nuevo artículo', tipo: TipoBoton.secundario, icono: Ico.nuevo, tamano: TamanoBoton.chico, onTap: () => context.push('/articulo/nuevo')),
          ),
      ],
      child: conRiel,
    );
  }

  Widget _barraHerramientas(List<Articulo> todos, bool compacto, bool conRiel) {
    final c = context.tm;
    final ramas = _categoria == Categoria.vex
        ? ({for (final a in todos) if (a.categoria == Categoria.vex && a.subcategoria != null) a.subcategoria!}.toList()..sort())
        : const <String>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.x4, Espacio.x4, Espacio.x4, Espacio.x2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TmBuscador(controlador: _busqueda, onCambio: (_) => setState(() {}))),
          if (!compacto) ...[
            const SizedBox(width: Espacio.x2),
            TmSegmento<_Vista>(
              valor: _vista,
              opciones: const [(_Vista.tabla, 'Tabla', Icons.view_list_outlined), (_Vista.tarjetas, 'Tarjetas', Icons.grid_view_outlined)],
              onCambio: (v) => setState(() => _vista = v),
            ),
          ] else ...[
            const SizedBox(width: Espacio.x2),
            TmBotonIcono(Ico.filtros, etiqueta: 'Filtros', onTap: _abrirFiltros),
          ],
        ]),
        if (!conRiel) ...[
          const SizedBox(height: Espacio.x3),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              TmChip('Todas', seleccionado: _categoria == null, conteo: todos.length, onTap: () => setState(() {
                    _categoria = null;
                    _rama = null;
                  })),
              for (final cat in Categoria.values) ...[
                const SizedBox(width: Espacio.x2),
                TmChip(
                  cat.nombre,
                  seleccionado: _categoria == cat,
                  color: c.deCategoria(cat),
                  conteo: todos.where((a) => a.categoria == cat).length,
                  onTap: () => setState(() {
                    _categoria = _categoria == cat ? null : cat;
                    _rama = null;
                  }),
                ),
              ],
            ]),
          ),
        ],
        if (ramas.isNotEmpty) ...[
          const SizedBox(height: Espacio.x2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text('Rama VEX  ', style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
              for (final r in ramas) ...[
                TmChip(r, seleccionado: _rama == r, onTap: () => setState(() => _rama = _rama == r ? null : r)),
                const SizedBox(width: Espacio.x2),
              ],
            ]),
          ),
        ],
        if (!conRiel && !compacto) ...[
          const SizedBox(height: Espacio.x2),
          Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
            TmChip('Disponible ahora', icono: Ico.ok, seleccionado: _disponibles, onTap: () => setState(() => _disponibles = !_disponibles)),
            TmChip('Mínimo o agotado', icono: Ico.aviso, seleccionado: _enMinimo, onTap: () => setState(() => _enMinimo = !_enMinimo)),
            TmChip('Con pendientes', icono: Ico.pendientes, seleccionado: _conPendientes, onTap: () => setState(() => _conPendientes = !_conPendientes)),
            TmChip('Por contar', icono: Ico.contar, seleccionado: _porContar, onTap: () => setState(() => _porContar = !_porContar)),
            TmChip('Sin ubicación', icono: Ico.ubicacion, seleccionado: _sinUbicacion, onTap: () => setState(() => _sinUbicacion = !_sinUbicacion)),
            TmChip('Sin foto', icono: Ico.sinFoto, seleccionado: _sinFoto, onTap: () => setState(() => _sinFoto = !_sinFoto)),
            if (_hayFiltros) TmBoton('Quitar filtros', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.cerrar, onTap: _limpiar),
          ]),
        ],
      ]),
    );
  }

  void _abrirFiltros() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void cambiar(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.x4, 0, Espacio.x4, Espacio.x4),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FILTROS', style: Tipografia.etiqueta.copyWith(color: context.tm.textoTenue)),
                const SizedBox(height: Espacio.x3),
                Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
                  TmChip('Todas', seleccionado: _categoria == null, onTap: () => cambiar(() => _categoria = null)),
                  for (final cat in Categoria.values)
                    TmChip(cat.nombre,
                        seleccionado: _categoria == cat,
                        color: context.tm.deCategoria(cat),
                        onTap: () => cambiar(() => _categoria = _categoria == cat ? null : cat)),
                ]),
                const SizedBox(height: Espacio.x4),
                Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
                  TmChip('Disponible ahora', icono: Ico.ok, seleccionado: _disponibles, onTap: () => cambiar(() => _disponibles = !_disponibles)),
                  TmChip('Mínimo o agotado', icono: Ico.aviso, seleccionado: _enMinimo, onTap: () => cambiar(() => _enMinimo = !_enMinimo)),
                  TmChip('Con pendientes', icono: Ico.pendientes, seleccionado: _conPendientes, onTap: () => cambiar(() => _conPendientes = !_conPendientes)),
                  TmChip('Por contar', icono: Ico.contar, seleccionado: _porContar, onTap: () => cambiar(() => _porContar = !_porContar)),
                  TmChip('Sin ubicación', icono: Ico.ubicacion, seleccionado: _sinUbicacion, onTap: () => cambiar(() => _sinUbicacion = !_sinUbicacion)),
                  TmChip('Sin foto', icono: Ico.sinFoto, seleccionado: _sinFoto, onTap: () => cambiar(() => _sinFoto = !_sinFoto)),
                ]),
                const SizedBox(height: Espacio.x4),
                Row(children: [
                  TmBoton('Quitar filtros', tipo: TipoBoton.fantasma, onTap: () {
                    _limpiar();
                    Navigator.pop(context);
                  }),
                  const Spacer(),
                  TmBoton('Ver resultados', tipo: TipoBoton.secundario, onTap: () => Navigator.pop(context)),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Riel de filtros en pantallas anchas.
class _RielFiltros extends StatelessWidget {
  const _RielFiltros({
    required this.todos,
    required this.categoria,
    required this.disponibles,
    required this.enMinimo,
    required this.conPendientes,
    required this.porContar,
    required this.sinUbicacion,
    required this.sinFoto,
    required this.onCategoria,
    required this.onFiltro,
    required this.onLimpiar,
  });

  final List<Articulo> todos;
  final Categoria? categoria;
  final bool disponibles, enMinimo, conPendientes, porContar, sinUbicacion, sinFoto;
  final ValueChanged<Categoria?> onCategoria;
  final void Function(String cual, bool valor) onFiltro;
  final VoidCallback? onLimpiar;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    Widget item(String texto, {IconData? icono, Color? color, required bool activo, required VoidCallback onTap, int? conteo}) => Semantics(
          selected: activo,
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: Redondeo.rSm,
            child: Container(
              height: Quiebre.toque,
              padding: const EdgeInsets.symmetric(horizontal: Espacio.x3),
              decoration: BoxDecoration(
                color: activo ? c.superficieHundida : Colors.transparent,
                borderRadius: Redondeo.rSm,
                border: Border(left: BorderSide(color: activo ? c.primario : Colors.transparent, width: 3)),
              ),
              child: Row(children: [
                if (color != null)
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)))
                else if (icono != null)
                  Icon(icono, size: 18, color: c.textoSecundario),
                const SizedBox(width: Espacio.x2),
                Expanded(
                  child: Text(texto,
                      style: Tipografia.chicoFuerte.copyWith(fontSize: 15, color: activo ? c.texto : c.textoSecundario),
                      overflow: TextOverflow.ellipsis),
                ),
                if (conteo != null) Text('$conteo', style: Tipografia.codigo.copyWith(fontSize: 12, color: c.textoTenue)),
              ]),
            ),
          ),
        );

    return TmTarjeta(
      padding: const EdgeInsets.symmetric(vertical: Espacio.x3, horizontal: Espacio.x2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.x3, 0, Espacio.x3, Espacio.x2),
          child: Text('CATEGORÍA', style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
        ),
        item('Todas', icono: Ico.inventario, activo: categoria == null, conteo: todos.length, onTap: () => onCategoria(null)),
        for (final cat in Categoria.values)
          item(cat.nombre,
              color: c.deCategoria(cat),
              activo: categoria == cat,
              conteo: todos.where((a) => a.categoria == cat).length,
              onTap: () => onCategoria(categoria == cat ? null : cat)),
        const SizedBox(height: Espacio.x3),
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.x3, 0, Espacio.x3, Espacio.x2),
          child: Text('SITUACIÓN', style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
        ),
        item('Disponible ahora',
            icono: Ico.ok,
            activo: disponibles,
            conteo: todos.where((a) => a.prestable && a.disponible > 0).length,
            onTap: () => onFiltro('disponibles', !disponibles)),
        item('Mínimo o agotado',
            icono: Ico.aviso,
            activo: enMinimo,
            conteo: todos.where((a) => [SituacionStock.enMinimo, SituacionStock.agotado].contains(SituacionStock.de(a))).length,
            onTap: () => onFiltro('minimo', !enMinimo)),
        item('Con pendientes',
            icono: Ico.pendientes,
            activo: conPendientes,
            conteo: todos.where((a) => a.pendientesAbiertos > 0).length,
            onTap: () => onFiltro('pendientes', !conPendientes)),
        const SizedBox(height: Espacio.x3),
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.x3, 0, Espacio.x3, Espacio.x2),
          child: Text('REVISIÓN', style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
        ),
        item('Por contar',
            icono: Ico.contar,
            activo: porContar,
            conteo: todos.where((a) => a.cantidadEstimada || a.conteoDesconocido).length,
            onTap: () => onFiltro('contar', !porContar)),
        item('Sin ubicación',
            icono: Ico.ubicacion, activo: sinUbicacion, conteo: todos.where((a) => a.contenedorId == null).length, onTap: () => onFiltro('ubicacion', !sinUbicacion)),
        item('Sin foto', icono: Ico.sinFoto, activo: sinFoto, conteo: todos.where((a) => a.fotoPrincipal == null).length, onTap: () => onFiltro('foto', !sinFoto)),
        if (onLimpiar != null) ...[
          const SizedBox(height: Espacio.x2),
          TmBoton('Quitar filtros', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.cerrar, onTap: onLimpiar),
        ],
      ]),
    );
  }
}

/// Tabla para computadora: código, categoría, existencias, ubicación y estado.
class _Tabla extends ConsumerWidget {
  const _Tabla({required this.lista});

  final List<Articulo> lista;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tm;
    Widget encabezado(String t, {bool derecha = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacio.x3, vertical: Espacio.x2),
          child: Text(t.toUpperCase(),
              style: Tipografia.etiqueta.copyWith(color: c.textoTenue), textAlign: derecha ? TextAlign.right : TextAlign.left),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.x4, 0, Espacio.x4, Espacio.x4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.superficie, borderRadius: Redondeo.rLg, border: Border.all(color: c.borde)),
        child: Column(children: [
          Container(
            color: c.superficie2,
            child: Row(children: [
              Expanded(flex: 42, child: encabezado('Artículo')),
              Expanded(flex: 12, child: encabezado('Código')),
              Expanded(flex: 18, child: encabezado('Categoría')),
              Expanded(flex: 16, child: encabezado('Disponibles')),
              Expanded(flex: 18, child: encabezado('Estado')),
              const SizedBox(width: Quiebre.toque),
            ]),
          ),
          for (final (i, a) in lista.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.borde),
            _Renglon(articulo: a),
          ],
        ]),
      ),
    );
  }
}

class _Renglon extends ConsumerWidget {
  const _Renglon({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = articulo;
    final c = context.tm;
    return InkWell(
      onTap: () => context.push('/articulo/${a.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espacio.x3, vertical: Espacio.x2),
        child: Row(children: [
          Expanded(
            flex: 42,
            child: Row(children: [
              Miniatura(ruta: a.fotoPrincipal, tamano: 44),
              const SizedBox(width: Espacio.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(a.nombre, style: Tipografia.cuerpoFuerte.copyWith(color: c.texto), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (a.marcaModelo != null)
                    Text(a.marcaModelo!, style: Tipografia.chico.copyWith(color: c.textoTenue), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(children: [
                    Icon(Ico.ubicacion, size: 13, color: c.textoTenue),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(a.ubicacion ?? 'Sin ubicación',
                          style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoTenue), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
          Expanded(flex: 12, child: Text(a.codigo, style: Tipografia.codigo.copyWith(color: c.textoSecundario))),
          Expanded(flex: 18, child: TmCategoria(a.categoria, corto: true)),
          Expanded(flex: 16, child: TmExistencias(a, compacto: true)),
          Expanded(
            flex: 18,
            child: Wrap(spacing: Espacio.x1, runSpacing: Espacio.x1, children: [
              _insigniaEstado(a),
              if (a.pendientesAbiertos > 0) TmInsignia('${a.pendientesAbiertos} pendiente${a.pendientesAbiertos == 1 ? '' : 's'}', tono: Tono.aviso, icono: Ico.pendientes),
              if (a.noSePresta) const TmInsignia('No se presta', tono: Tono.contorno, icono: Ico.noSePresta),
            ]),
          ),
          TmBotonIcono(Ico.avanzar, etiqueta: 'Abrir ficha de ${a.nombre}', tamano: TamanoBoton.chico, onTap: () => context.push('/articulo/${a.id}')),
        ]),
      ),
    );
  }
}

TmInsignia _insigniaEstado(Articulo a) => switch (a.estadoInventario) {
      EstadoInventario.verificado => const TmInsignia('Verificado', tono: Tono.ok, icono: Ico.verificado),
      EstadoInventario.porVerificar => const TmInsignia('Por verificar', tono: Tono.info, icono: Ico.porVerificar),
      EstadoInventario.porContar => const TmInsignia('Por contar', tono: Tono.aviso, icono: Ico.contar),
      EstadoInventario.sinClasificar => const TmInsignia('Sin clasificar', tono: Tono.error, icono: Ico.alerta),
      EstadoInventario.desglosado => const TmInsignia('Desglosado', tono: Tono.neutro, icono: Ico.kits),
      EstadoInventario.dadoDeBaja => const TmInsignia('Dado de baja', tono: Tono.neutro, icono: Ico.baja),
    };

/// Tarjeta del artículo (celular y vista de tarjetas).
class _TarjetaArticulo extends StatelessWidget {
  const _TarjetaArticulo({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context) {
    final a = articulo;
    final c = context.tm;
    return TmTarjeta(
      onTap: () => context.push('/articulo/${a.id}'),
      padding: const EdgeInsets.all(Espacio.x3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Miniatura(ruta: a.fotoPrincipal, tamano: 56),
        const SizedBox(width: Espacio.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text(a.codigo, style: Tipografia.codigo.copyWith(color: c.textoTenue)),
              const Spacer(),
              Flexible(child: TmCategoria(a.categoria, corto: true)),
            ]),
            const SizedBox(height: 2),
            Text(a.nombre, style: Tipografia.cuerpoFuerte.copyWith(color: c.texto), maxLines: 2, overflow: TextOverflow.ellipsis),
            Row(children: [
              Icon(Ico.ubicacion, size: 13, color: c.textoTenue),
              const SizedBox(width: 3),
              Expanded(
                child: Text(a.ubicacion ?? 'Sin ubicación',
                    style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoTenue), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: Espacio.x2),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TmExistencias(a)),
              if (a.pendientesAbiertos > 0)
                TmInsignia('${a.pendientesAbiertos}', tono: Tono.aviso, icono: Ico.pendientes)
              else if (a.noSePresta)
                const TmInsignia('No se presta', tono: Tono.contorno, icono: Ico.noSePresta),
            ]),
          ]),
        ),
      ]),
    );
  }
}
