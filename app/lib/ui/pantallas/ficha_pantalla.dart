import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/otros.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/fotos.dart';

/// Ficha del artículo (F-01): fotos, cifras, datos, pendientes e historial.
class FichaPantalla extends ConsumerWidget {
  const FichaPantalla({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articulo = ref.watch(articuloProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(articulo.value?.codigo ?? 'Artículo'),
        actions: [
          if (articulo.value?.activo ?? false)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar datos',
              onPressed: () => context.push('/articulo/$id/editar'),
            ),
          const BarraSesion(),
        ],
      ),
      body: Cargando<Articulo?>(
        valor: articulo,
        alReintentar: () => refrescarArticulo(ref, id),
        datos: (a) => a == null
            ? const Center(child: Text('Este artículo no existe.'))
            : RefreshIndicator(
                onRefresh: () async => refrescarArticulo(ref, id),
                child: Centrado(child: _Contenido(articulo: a)),
              ),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = articulo;
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Galeria(articulo: a),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.nombre, style: tema.textTheme.headlineSmall),
            if (a.marcaModelo != null) Text(a.marcaModelo!, style: tema.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: insigniasDe(a)),
          ]),
        ),
        _Cifras(articulo: a),
        const _Titulo('Datos'),
        _Dato('Categoría', [a.categoria.nombre, a.subcategoria].whereType<String>().join(' · ')),
        _Dato('Estado', a.estadoInventario.nombre),
        _Dato('Estado físico', a.estadoFisicoTexto ?? a.estadoFisico?.nombre),
        _Dato('Ubicación', a.ubicacion ?? 'Sin asignar'),
        _Dato('Número de resguardo', a.numResguardo),
        _Dato('Número de serie', a.numSerie),
        _Dato('Etiquetado', '${a.etiquetado.nombre}: ${a.etiquetado.explicacion}'),
        if (a.refFoto != null) _Dato('Ref. de la foto del levantamiento', '${a.refFoto}'),
        if (a.cantidadTexto != null) _Dato('Cantidad en el Excel original', '"${a.cantidadTexto}"'),
        _Dato('Observaciones', a.observaciones),
        _Pendientes(articuloId: a.id),
        _Historial(articuloId: a.id),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card.outlined(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Préstamos, devoluciones y reportes'),
              subtitle: const Text('Se habilitan en la Fase 3.'),
              textColor: tema.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}

class _Galeria extends ConsumerStatefulWidget {
  const _Galeria({required this.articulo});

  final Articulo articulo;

  @override
  ConsumerState<_Galeria> createState() => _GaleriaState();
}

class _GaleriaState extends ConsumerState<_Galeria> {
  final _pagina = PageController();
  int _actual = 0;
  bool _subiendo = false;

  @override
  void dispose() {
    _pagina.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    final foto = await elegirFoto(context);
    if (foto == null || !mounted) return;
    final tipo = await showDialog<TipoFoto>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿Qué muestra la foto?'),
        children: [
          for (final t in TipoFoto.delCatalogo)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, t), child: Text(t.nombre)),
        ],
      ),
    );
    if (tipo == null || !mounted) return;
    foto.tipo = tipo;

    setState(() => _subiendo = true);
    try {
      final hecho = await conAcceso<bool>(
        context,
        ref,
        descripcion: 'agregar una foto a "${widget.articulo.nombre}"',
        requisito: Requisito.docente,
        accion: () async {
          await ref.read(repositorioProvider).agregarFoto(widget.articulo.id, foto);
          return true;
        },
      );
      if (hecho == true && mounted) {
        refrescarArticulo(ref, widget.articulo.id);
        avisar(context, 'Foto agregada.');
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _hacerPrincipal(Foto foto) async {
    try {
      final hecho = await conAcceso<bool>(
        context,
        ref,
        descripcion: 'cambiar la foto principal',
        requisito: Requisito.administracion,
        accion: () async {
          await ref.read(repositorioProvider).hacerPrincipal(foto.id);
          return true;
        },
      );
      if (hecho == true && mounted) {
        refrescarArticulo(ref, widget.articulo.id);
        _pagina.jumpToPage(0);
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fotos = ref.watch(fotosProvider(widget.articulo.id));
    final sesion = ref.watch(sesionProvider).value;
    final tema = Theme.of(context);

    final botonAgregar = FilledButton.tonalIcon(
      onPressed: _subiendo || !widget.articulo.activo ? null : _agregar,
      icon: _subiendo
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.add_a_photo_outlined),
      label: const Text('Agregar foto'),
    );

    return fotos.when(
      loading: () => const SizedBox(height: 280, child: Center(child: CircularProgressIndicator())),
      error: (_, _) => SizedBox(height: 120, child: Center(child: botonAgregar)),
      data: (lista) {
        if (lista.isEmpty) {
          return Container(
            height: 220,
            color: tema.colorScheme.surfaceContainerHighest,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.photo_camera_outlined, size: 48, color: tema.colorScheme.outline),
              const SizedBox(height: 8),
              const Text('Este artículo todavía no tiene foto.'),
              const SizedBox(height: 12),
              botonAgregar,
            ]),
          );
        }
        final actual = lista[_actual.clamp(0, lista.length - 1)];
        return Column(children: [
          SizedBox(
            height: 300,
            child: PageView.builder(
              controller: _pagina,
              itemCount: lista.length,
              onPageChanged: (i) => setState(() => _actual = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _verCompleta(context, lista[i]),
                child: Container(
                  color: Colors.black,
                  child: Image.network(lista[i].url, fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48))),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  [if (actual.esPrincipal) 'Principal', actual.tipo.nombre, fecha(actual.tomadaEn), '${_actual + 1} de ${lista.length}']
                      .join(' · '),
                  style: tema.textTheme.bodySmall,
                ),
              ),
              if (!actual.esPrincipal && (sesion?.administra ?? false))
                TextButton(onPressed: () => _hacerPrincipal(actual), child: const Text('Hacer principal')),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Align(alignment: Alignment.centerLeft, child: botonAgregar)),
        ]);
      },
    );
  }

  void _verCompleta(BuildContext context, Foto foto) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(foto.tipo.nombre)),
        body: InteractiveViewer(maxScale: 6, child: Center(child: Image.network(foto.url))),
      ),
    ));
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context) {
    final a = articulo;
    final tema = Theme.of(context);
    Widget cifra(String etiqueta, String valor) => Column(children: [
          Text(valor, style: tema.textTheme.titleLarge),
          Text(etiqueta, style: tema.textTheme.labelSmall),
        ]);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(a.disponibilidad,
              style: tema.textTheme.headlineMedium?.copyWith(
                color: a.prestable && a.disponible > 0 ? tema.colorScheme.primary : tema.colorScheme.error,
              )),
          if (a.prestadoHasta != null) Text('Prestado hasta el ${fecha(a.prestadoHasta!)}', style: tema.textTheme.bodyMedium),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            cifra('Existencia', a.cantidadMostrada),
            cifra('Prestado', '${a.prestado}'),
            cifra('Fuera de servicio', '${a.fueraServicio}'),
            if (a.apartado > 0) cifra('Apartado', '${a.apartado}'),
          ]),
          if (a.cantidadEstimada || a.conteoDesconocido) ...[
            const SizedBox(height: 12),
            Text(
              a.conteoDesconocido
                  ? 'Nunca se ha contado: no se presta hasta que alguien lo cuente.'
                  : 'La cantidad es estimada (~) hasta que se haga un conteo físico.',
              style: tema.textTheme.bodySmall?.copyWith(color: Avisos.estimado),
              textAlign: TextAlign.center,
            ),
          ],
        ]),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String? valor;

  @override
  Widget build(BuildContext context) {
    if (valor == null || valor!.isEmpty) return const SizedBox.shrink();
    return ListTile(dense: true, title: Text(etiqueta), subtitle: SelectableText(valor!, style: Theme.of(context).textTheme.bodyLarge));
  }
}

class _Pendientes extends ConsumerWidget {
  const _Pendientes({required this.articuloId});

  final String articuloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(pendientesProvider(articuloId)).value ?? const [];
    if (lista.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Titulo('Pendientes por verificar'),
      for (final p in lista)
        ListTile(
          leading: Icon(Icons.flag_outlined, color: p.prioridadAlta ? Avisos.sinClasificar : Avisos.pendiente),
          title: Text(p.nombre),
          subtitle: Text(p.descripcion),
        ),
    ]);
  }
}

class _Historial extends ConsumerWidget {
  const _Historial({required this.articuloId});

  final String articuloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(historialProvider(articuloId)).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Titulo('Historial'),
      if (lista.isEmpty) const ListTile(title: Text('Sin movimientos todavía.')),
      for (final m in lista)
        ListTile(
          dense: true,
          leading: const Icon(Icons.history),
          title: Text('${m.nombre} · ${m.cantidad}'),
          subtitle: Text([fechaHora(m.fecha), if (m.prestadoHasta != null) 'prestado hasta el ${fecha(m.prestadoHasta!)}'].join(' · ')),
        ),
    ]);
  }
}
