import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/movimientos.dart';
import '../../modelos/otros.dart';
import '../../util/texto.dart';
import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';
import '../widgets/fotos.dart';
import '../../acceso/hoja_acceso.dart';
import '../../datos/local.dart';
import 'acciones_articulo.dart' as acciones;
import 'contenedores_pantallas.dart' show elegirContenedor;
import 'pendientes_pantallas.dart' show abrirPendiente, contarArticulo;
import '../../datos/avisos_disponible.dart';

/// Ficha del artículo (F-01): fotos, cifras, datos, pendientes e historial.
class FichaPantalla extends ConsumerWidget {
  const FichaPantalla({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articulo = ref.watch(articuloProvider(id));
    final actual = articulo.value;
    return TmArmazon(
      ruta: '/inventario',
      titulo: actual?.codigo ?? 'Artículo',
      // El visitante ve el catálogo, no el inventario.
      migas: ref.watch(sesionProvider).value == null ? const [('Catálogo', '/')] : const [('Inventario', '/inventario')],
      conRegresar: true,
      acciones: [
        if (actual?.activo ?? false)
          TmBotonIcono(Ico.editar, etiqueta: 'Editar datos', onTap: () => context.push('/articulo/$id/editar')),
        if (actual != null) _MenuAdministracion(articulo: actual),
      ],
      child: Cargando<Articulo?>(
        valor: articulo,
        alReintentar: () => refrescarArticulo(ref, id),
        datos: (a) => a == null
            ? const TmVacio(
                titulo: 'Este artículo no existe',
                texto: 'Puede que lo hayan dado de baja o que el código esté mal escrito.',
                icono: Ico.vacio,
              )
            : RefreshIndicator(
                onRefresh: () async => refrescarArticulo(ref, id),
                child: _Contenido(articulo: a),
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
    final c = context.tm;
    final dosColumnas = MediaQuery.sizeOf(context).width >= Quiebre.rieles;

    final visual = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Galeria(articulo: a),
      const SizedBox(height: Espacio.x3),
      TmTarjeta(
        padding: const EdgeInsets.all(Espacio.x3),
        child: Row(children: [
          Icon(Ico.qr, size: 40, color: c.texto),
          const SizedBox(width: Espacio.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('ETIQUETA', style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
              SelectableText(a.codigo, style: Tipografia.codigoFuerte.copyWith(fontSize: 20, color: c.texto)),
              // Cómo se etiqueta (no dónde está): "En contenedor" solo se leía como ubicación.
              Text(switch (a.etiquetado) {
                Etiquetado.individual => 'Lleva su propio QR',
                Etiquetado.contenedor => 'El QR va en su contenedor',
                Etiquetado.lote => 'Sin QR: se cuenta por lote',
              }, style: Tipografia.chico.copyWith(color: c.textoTenue)),
            ]),
          ),
          if (a.etiquetado == Etiquetado.individual)
            TmBotonIcono(Ico.imprimir, etiqueta: 'Imprimir su etiqueta', onTap: () => context.push('/etiquetas?codigos=${a.codigo}')),
        ]),
      ),
    ]);

    final encabezado = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TmCategoria(a.categoria),
        if (a.subcategoria != null) TmInsignia(a.subcategoria!, icono: Ico.deSubcategoria(a.subcategoria)),
        ...insigniasTm(a),
      ]),
      const SizedBox(height: Espacio.x2),
      SelectableText(a.nombre, style: Tipografia.h1.copyWith(color: c.texto)),
      if (a.marcaModelo != null) Text(a.marcaModelo!, style: Tipografia.cuerpo.copyWith(color: c.textoSecundario)),
    ]);

    final aviso = _avisoSituacion(a);

    final datos = TmTarjeta(
      titulo: 'Datos',
      icono: Ico.inventario,
      sinPadding: true,
      child: Column(children: [
        _Dato('Categoría', [a.categoria.nombre, a.subcategoria].whereType<String>().join(' · ')),
        _Dato('Estado', a.estadoInventario.nombre),
        _Dato('Estado físico', a.estadoFisicoTexto ?? a.estadoFisico?.nombre),
        _Ubicacion(articulo: a),
        _Dato('Número de resguardo', a.numResguardo),
        _Dato('Número de serie', a.numSerie),
        _Dato('Unidad', a.unidad),
        _Dato(
          'Mínimo para reponer',
          a.minimoReposicion == null ? (a.esConsumible ? 'Sin mínimo definido' : 'No aplica (no es consumible)') : '${a.minimoReposicion}',
        ),
        _Dato('Etiquetado', '${a.etiquetado.nombre}: ${a.etiquetado.explicacion}'),
        if (a.refFoto != null) _Dato('Ref. de la foto del levantamiento', '${a.refFoto}'),
        if (a.cantidadTexto != null) _Dato('Cantidad en el Excel original', '"${a.cantidadTexto}"'),
        _Dato('Observaciones', a.observaciones),
        if (a.noSePresta) _Dato('No se presta', a.noSePrestaMotivo),
      ]),
    );

    final detalle = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      encabezado,
      const SizedBox(height: Espacio.x4),
      if (!a.activo) ...[
        TmAlerta(
          titulo: a.bajaEnTramite ? 'Dado de baja · en trámite' : 'Dado de baja',
          texto: a.bajaEnTramite
              ? 'Falta registrar el número de oficio para cerrar el trámite.'
              : a.bajaOficio == null
                  ? 'Ya no cuenta en el inventario.'
                  : 'Oficio ${a.bajaOficio}. Ya no cuenta en el inventario.',
          tono: Tono.error,
          icono: Ico.baja,
        ),
        const SizedBox(height: Espacio.x4),
      ],
      _Cifras(articulo: a),
      if (aviso != null) ...[const SizedBox(height: Espacio.x3), aviso],
      if (a.activo) ...[const SizedBox(height: Espacio.x4), _Acciones(articulo: a)],
      const SizedBox(height: Espacio.x4),
      datos,
      const SizedBox(height: Espacio.x4),
      _Pendientes(articuloId: a.id),
      _Historial(articuloId: a.id),
    ]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Espacio.x4, Espacio.x4, Espacio.x4, Espacio.x10),
      children: [
        if (dosColumnas)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 360, child: visual),
            const SizedBox(width: Espacio.x6),
            Expanded(child: detalle),
          ])
        else ...[
          visual,
          const SizedBox(height: Espacio.x4),
          detalle,
        ],
      ],
    );
  }

  Widget? _avisoSituacion(Articulo a) => switch (SituacionStock.de(a)) {
        SituacionStock.sinContar => const TmAlerta(
            titulo: 'Nunca se ha contado',
            texto: 'No se puede prestar hasta que alguien lo cuente.',
            tono: Tono.info,
            icono: Ico.contar,
          ),
        SituacionStock.noSePresta => TmAlerta(
            titulo: 'No sale del taller',
            texto: a.noSePrestaMotivo,
            tono: Tono.info,
            icono: Ico.noSePresta,
          ),
        SituacionStock.agotado => const TmAlerta(titulo: 'Agotado', texto: 'No queda ninguno. Conviene reponerlo.', tono: Tono.error),
        SituacionStock.ningunoDisponible => TmAlerta(
            titulo: 'Ninguno disponible',
            texto: a.prestadoHasta == null
                ? 'Todo lo que hay está prestado, apartado o fuera de servicio.'
                : 'Todo está prestado; el más próximo regresa el ${fecha(a.prestadoHasta!)}.',
            tono: Tono.aviso,
            icono: Ico.reloj,
          ),
        SituacionStock.enMinimo => TmAlerta(
            titulo: 'Llegó a su mínimo',
            texto: 'Quedan ${conUnidad(a.disponible, a.unidad)} y el mínimo es ${a.minimoReposicion}.',
            tono: Tono.aviso,
          ),
        SituacionStock.disponible => a.cantidadEstimada
            ? const TmAlerta(
                titulo: 'La cantidad es estimada',
                texto: 'El ~ se quita cuando alguien haga un conteo físico.',
                tono: Tono.info,
                icono: Ico.contar,
              )
            : null,
      };
}

/// Las insignias que van junto al nombre, con el estilo del sistema de diseño.
List<Widget> insigniasTm(Articulo a) => [
      if (a.estadoInventario == EstadoInventario.sinClasificar)
        const TmInsignia('Sin clasificar: no usar', tono: Tono.error, icono: Ico.alerta),
      if (a.estadoInventario == EstadoInventario.verificado) const TmInsignia('Verificado', tono: Tono.ok, icono: Ico.verificado),
      if (a.estadoInventario == EstadoInventario.porVerificar) const TmInsignia('Por verificar', tono: Tono.info, icono: Ico.porVerificar),
      if (a.conteoDesconocido)
        const TmInsignia('Sin contar', tono: Tono.aviso, icono: Ico.contar)
      else if (a.cantidadEstimada)
        const TmInsignia('Cantidad estimada', tono: Tono.info, icono: Ico.contar),
      if (a.pendientesAbiertos > 0)
        TmInsignia('${a.pendientesAbiertos} pendiente${a.pendientesAbiertos == 1 ? '' : 's'}', tono: Tono.aviso, icono: Ico.pendientes),
      if (a.fueraServicio > 0) TmInsignia('${a.fueraServicio} fuera de servicio', tono: Tono.error, icono: Ico.aviso),
      if (a.noSePresta) const TmInsignia('No se presta', tono: Tono.contorno, icono: Ico.noSePresta),
    ];

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
        requisito: Requisito.cualquiera,
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
          : const Icon(Ico.agregarFoto),
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
              Icon(Ico.foto, size: 48, color: tema.colorScheme.outline),
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
                  child: FotoConCopia(ruta: lista[i].ruta, url: lista[i].url, fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(child: Icon(Ico.imagenRota, color: Colors.white54, size: 48))),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              // Las fotos de la selección de robótica se ven, pero marcadas hasta el visto bueno.
              if (!actual.verificada) ...[
                const TmInsignia('Sin verificar', tono: Tono.aviso, icono: Ico.enEspera),
                const SizedBox(width: Espacio.x2),
              ],
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
        body: InteractiveViewer(maxScale: 6, child: Center(child: FotoConCopia(ruta: foto.ruta, url: foto.url, fit: BoxFit.contain))),
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
    final c = context.tm;
    final estrecho = MediaQuery.sizeOf(context).width < 480;
    Widget cifra(String etiqueta, String valor, {bool destacada = false}) => Container(
          padding: const EdgeInsets.all(Espacio.x3),
          decoration: BoxDecoration(
            color: destacada ? c.exitoSuave : c.superficie,
            border: Border(right: BorderSide(color: c.borde), bottom: BorderSide(color: c.borde)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(etiqueta.toUpperCase(), style: Tipografia.etiqueta.copyWith(color: c.textoTenue, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(valor, style: Tipografia.cifraChica.copyWith(fontSize: 24, color: destacada ? c.exito : c.texto), maxLines: 1),
          ]),
        );

    final cifras = [
      cifra('Disponibles', a.conteoDesconocido ? '?' : '${a.cantidadEstimada ? '~' : ''}${a.disponible < 0 ? 0 : a.disponible}', destacada: true),
      cifra('Prestados', '${a.prestado}'),
      cifra('Fuera de serv.', '${a.fueraServicio}'),
      cifra('Existencia', a.conteoDesconocido ? '?' : '${a.cantidadEstimada ? '~' : ''}${a.existencia}'),
    ];

    return TmTarjeta(
      sinPadding: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Redondeo.lg)),
          child: GridView.count(
            crossAxisCount: estrecho ? 2 : 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: estrecho ? 2.6 : 1.9,
            children: cifras,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Espacio.x4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TmExistencias(a, conLeyenda: true),
            if (a.prestadoHasta != null) ...[
              const SizedBox(height: Espacio.x2),
              Row(children: [
                Icon(Ico.reloj, size: 15, color: c.textoTenue),
                const SizedBox(width: 5),
                Text('El próximo regresa el ${fecha(a.prestadoHasta!)}', style: Tipografia.chico.copyWith(color: c.textoSecundario)),
              ]),
            ],
            if (a.apartado > 0) ...[
              const SizedBox(height: Espacio.x1),
              Text('${a.apartado} apartado${a.apartado == 1 ? '' : 's'} por solicitudes aprobadas',
                  style: Tipografia.chico.copyWith(color: c.textoSecundario)),
            ],
          ]),
        ),
      ]),
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

/// Dónde vive el artículo. Administración lo cambia; un docente propone si lo encontró en otro lugar.
class _Ubicacion extends ConsumerWidget {
  const _Ubicacion({required this.articulo});

  final Articulo articulo;

  Future<void> _cambiar(BuildContext context, WidgetRef ref, bool administra) async {
    final a = articulo;
    final destino = await elegirContenedor(context, ref,
        para: a.categoria,
        excluir: a.contenedorId,
        titulo: administra ? 'Mover "${a.nombre}" a…' : '¿Dónde lo encontraste?',
        permitirNinguno: administra);
    if (destino == null || !context.mounted) return;
    try {
      if (administra) {
        await conAcceso<int>(context, ref,
            descripcion: 'cambiar la ubicación de "${a.nombre}"',
            requisito: Requisito.administracion,
            accion: () => ref.read(repositorioProvider).acomodar([a.id], destino.id.isEmpty ? null : destino.id));
      } else {
        final hecho = await conAcceso<bool>(context, ref, descripcion: 'proponer otra ubicación', requisito: Requisito.cualquiera, accion: () async {
          await ref.read(repositorioProvider).proponerUbicacion(a.id, destino.id, null);
          return true;
        });
        if (hecho == true && context.mounted) avisar(context, 'Propuesta enviada al responsable del laboratorio.');
      }
      refrescarArticulo(ref, a.id);
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = articulo;
    final sesion = ref.watch(sesionProvider).value;
    final administra = sesion?.administra ?? false;
    return ListTile(
      dense: true,
      title: const Text('Ubicación'),
      subtitle: Text(a.ubicacion ?? 'Sin asignar', style: Theme.of(context).textTheme.bodyLarge),
      onTap: a.contenedorCodigo == null ? null : () => context.push('/contenedor/${a.contenedorCodigo}'),
      trailing: !a.activo || sesion == null
          ? (a.contenedorCodigo == null ? null : const Icon(Ico.avanzar))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (administra && a.etiquetado == Etiquetado.individual)
                IconButton(icon: const Icon(Ico.qr), tooltip: 'Imprimir su etiqueta', onPressed: () => context.push('/etiquetas?codigos=${a.codigo}')),
              TextButton(
                onPressed: () => _cambiar(context, ref, administra),
                child: Text(administra ? 'Cambiar' : 'Está en otro lugar'),
              ),
            ]),
    );
  }
}

class _Pendientes extends ConsumerWidget {
  const _Pendientes({required this.articuloId});

  final String articuloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abiertos = (ref.watch(pendientesAbiertosProvider).value ?? const []).where((p) => p.articuloId == articuloId).toList();
    final articulo = ref.watch(articuloProvider(articuloId)).value;
    if (abiertos.isEmpty || articulo == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Titulo('Pendientes por verificar'),
      for (final p in abiertos)
        ListTile(
          leading: Icon(Ico.reportar, color: p.prioridadAlta ? Avisos.sinClasificar : Avisos.pendiente),
          title: Text(nombresTarea[p.tipo] ?? p.tipo),
          subtitle: Text(p.descripcion),
          trailing: const Icon(Ico.avanzar),
          onTap: () => abrirPendiente(context, ref, p, articulo),
        ),
    ]);
  }
}

class _Historial extends ConsumerWidget {
  const _Historial({required this.articuloId});

  final String articuloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).value;
    // Con nombres, solo para responsable y sub administración con contraseña.
    if (sesion != null && sesion.administra && sesion.nivel == NivelSesion.contrasena) {
      return _HistorialDetallado(articuloId: articuloId);
    }
    final lista = ref.watch(historialProvider(articuloId)).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Titulo('Historial'),
      if (lista.isEmpty) const ListTile(title: Text('Sin movimientos todavía.')),
      for (final m in lista)
        ListTile(
          dense: true,
          leading: const Icon(Ico.historial),
          title: Text('${m.nombre} · ${m.cantidad}'),
          subtitle: Text([fechaHora(m.fecha), if (m.prestadoHasta != null) 'prestado hasta el ${fecha(m.prestadoHasta!)}'].join(' · ')),
        ),
    ]);
  }
}

class _Acciones extends ConsumerWidget {
  const _Acciones({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = articulo;
    final sesion = ref.watch(sesionProvider);
    // Sin cuenta: alumnos y maestros piden (F-04). Quien tiene cuenta presta directo (F-07).
    if (!sesion.isLoading && sesion.value == null) {
      final enCarrito = ref.watch(carritoProvider).any((l) => l.articuloId == a.id);
      final sePide = a.prestable && a.disponible > 0 && !a.esConsumible;
      if (!sePide && !a.esConsumible && a.prestado + a.apartado + a.fueraServicio > 0) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.tonalIcon(
              onPressed: () => pedirAvisoDisponible(context, ref, a),
              icon: const Icon(Ico.avisoActivo),
              label: const Text('Avísame cuando regrese'),
            ),
            TextButton(onPressed: () => pedirAcceso(context, descripcion: 'prestar o recibir material'), child: const Text('Soy docente')),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: !sePide
                ? null
                : () {
                    ref.read(carritoProvider.notifier).agregar(a);
                    context.push('/solicitud');
                  },
            icon: Icon(enCarrito ? Ico.ok : Ico.carrito),
            label: Text(enCarrito ? 'Ya está en tu solicitud' : 'Pedir prestado'),
          ),
          if (a.esConsumible) const Text('Los consumibles se piden en persona en el laboratorio.'),
          TextButton(
            onPressed: () => pedirAcceso(context, descripcion: 'prestar o recibir material'),
            child: const Text('Soy docente'),
          ),
        ]),
      );
    }

    final esSel = sesion.value?.esSeleccion ?? false;
    if (esSel) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          if (a.prestable && a.disponible > 0 && !a.esConsumible)
            FilledButton.icon(
              onPressed: () => _pedirPrestadoSeleccion(context, ref, a),
              icon: const Icon(Ico.carrito),
              label: const Text('Pedir prestado'),
            ),
          OutlinedButton.icon(
            onPressed: () => context.push('/articulo/${a.id}/reportar'),
            icon: const Icon(Ico.reportar),
            label: const Text('Reportar problema'),
          ),
          OutlinedButton.icon(
            onPressed: () => contarArticulo(context, ref, a),
            icon: const Icon(Ico.conteo),
            label: const Text('Contar'),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (a.esConsumible)
          FilledButton.icon(
            onPressed: a.prestable && a.disponible > 0 ? () => acciones.registrarUso(context, ref, a) : null,
            icon: const Icon(Ico.quitarCirculo),
            label: const Text('Registrar uso'),
          )
        else
          FilledButton.icon(
            onPressed: a.prestable && a.disponible > 0 ? () => context.push('/articulo/${a.id}/prestar') : null,
            icon: const Icon(Ico.prestar),
            label: const Text('Prestar'),
          ),
        if (a.prestado > 0)
          OutlinedButton.icon(
            onPressed: () => context.push('/articulo/${a.id}/devolver'),
            icon: const Icon(Ico.devolver),
            label: const Text('Recibir devolución'),
          ),
        OutlinedButton.icon(
          onPressed: () => context.push('/articulo/${a.id}/reportar'),
          icon: const Icon(Ico.reportar),
          label: const Text('Reportar problema'),
        ),
        OutlinedButton.icon(
          onPressed: () => contarArticulo(context, ref, a),
          icon: const Icon(Ico.conteo),
          label: const Text('Contar'),
        ),
      ]),
    );
  }
}

Future<void> _pedirPrestadoSeleccion(BuildContext context, WidgetRef ref, Articulo a) async {
  final repo = ref.read(repositorioProvider);
  final ficha = await repo.seleccionMiFicha();
  if (!context.mounted) return;
  if (ficha == null) {
    avisar(context, 'Tu cuenta no está vinculada a una ficha de alumno. Habla con el responsable.');
    return;
  }
  final impedimento = ficha['impedimento'] as String?;
  if (impedimento != null) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No puedes pedir material'),
        content: Text(impedimento),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
    return;
  }

  final form = GlobalKey<FormState>();
  final motivoCtrl = TextEditingController();
  final notaCtrl = TextEditingController();
  int cantidad = 1;
  // Los plazos los pone la configuración: si el calendario deja elegir de más, el servidor lo rechaza.
  final config = await ref.read(configuracionProvider.future).catchError((_) => <String, dynamic>{});
  if (!context.mounted) return;
  final diasMax = (config['plazo_max_alumno_dias'] as num?)?.toInt() ?? 14;
  final diasDefault = ((config['plazo_default_dias'] as num?)?.toInt() ?? 7).clamp(1, diasMax);
  DateTime fechaDevolucion = DateTime.now().add(Duration(days: diasDefault));

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text('Pedir prestado: ${a.nombre}'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disponible: ${a.disponible} ${a.unidad}'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Para qué lo necesitas *',
                    hintText: 'Ej. Proyecto de robótica, práctica',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Escribe el motivo.' : null,
                ),
                const SizedBox(height: 12),
                SelectorCantidad(
                  etiqueta: 'Cantidad:',
                  valor: cantidad,
                  minimo: 1,
                  maximo: a.disponible,
                  alCambiar: (v) => setDialogState(() => cantidad = v),
                ),
                if (a.disponible <= 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Solo hay 1 ${a.unidad} disponible en el taller.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.outline,
                          ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('Devolver el: ${fechaDevolucion.day}/${fechaDevolucion.month}/${fechaDevolucion.year}'
                          ' · máximo $diasMax días'),
                    ),
                    TextButton(
                      child: const Text('Cambiar fecha'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: fechaDevolucion,
                          firstDate: DateTime.now().add(const Duration(days: 1)),
                          lastDate: DateTime.now().add(Duration(days: diasMax)),
                        );
                        if (picked != null) {
                          setDialogState(() => fechaDevolucion = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas adicionales',
                    hintText: 'Opcional',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    ),
  );

  if (confirmado != true || !context.mounted) return;
  try {
    final res = await repo.crearSolicitudSeleccion(
      lineas: [(articuloId: a.id, cantidad: cantidad)],
      motivo: motivoCtrl.text.trim(),
      fechaDevolucion: fechaDevolucion,
      nota: notaCtrl.text.trim().isEmpty ? null : notaCtrl.text.trim(),
    );
    ref.invalidate(misSolicitudesSelProvider);
    if (context.mounted) {
      avisar(context, 'Solicitud ${res.folio} enviada. El responsable la revisará.');
      context.push('/mis-solicitudes-sel');
    }
  } catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}

Future<void> _marcarPrestable(BuildContext context, WidgetRef ref, Articulo a) async {
  String? motivo;
  if (!a.noSePresta) {
    motivo = await pedirTexto(context,
        titulo: 'No se presta', etiqueta: 'Por qué *', ayuda: 'Ej. Solo son las cajas vacías; equipo fijo del laboratorio', boton: 'Guardar');
    if (motivo == null) return;
  }
  if (!context.mounted) return;
  try {
    final hecho = await conAcceso<bool>(context, ref,
        descripcion: a.noSePresta ? 'permitir que se preste' : 'marcar que no se presta', requisito: Requisito.administracion, accion: () async {
      await ref.read(repositorioProvider).marcarPrestable(a.id, a.noSePresta, motivo);
      return true;
    });
    if (hecho == true && context.mounted) refrescarArticulo(ref, a.id);
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}

class _MenuAdministracion extends ConsumerWidget {
  const _MenuAdministracion({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).value;
    if (sesion == null || !sesion.administra) return const SizedBox.shrink();
    final a = articulo;
    return PopupMenuButton<String>(
      tooltip: 'Administrar',
      icon: const Icon(Ico.mas),
      onSelected: (opcion) => switch (opcion) {
        'conteo' => acciones.ajustarConteo(context, ref, a),
        'reparacion' => acciones.registrarReparacion(context, ref, a),
        'baja' => acciones.darDeBaja(context, ref, a),
        'desglose' => context.push('/desglose/${a.id}'),
        'prestable' => _marcarPrestable(context, ref, a),
        'oficio' => acciones.registrarOficio(context, ref, a),
        _ => acciones.reactivar(context, ref, a),
      },
      itemBuilder: (_) => [
        if (a.activo) ...[
          const PopupMenuItem(value: 'conteo', child: ListTile(leading: Icon(Ico.conteo), title: Text('Ajustar conteo'))),
          const PopupMenuItem(value: 'desglose', child: ListTile(leading: Icon(Ico.desarchivar), title: Text('Abrir y desglosar'))),
          PopupMenuItem(
              value: 'prestable',
              child: ListTile(
                  leading: Icon(a.noSePresta ? Ico.prestar : Ico.noSePresta),
                  title: Text(a.noSePresta ? 'Permitir que se preste' : 'Marcar que no se presta'))),
          if (a.fueraServicio > 0)
            const PopupMenuItem(value: 'reparacion', child: ListTile(leading: Icon(Ico.herramientas), title: Text('Regresa a servicio'))),
          const PopupMenuItem(value: 'baja', child: ListTile(leading: Icon(Ico.baja), title: Text('Dar de baja'))),
        ] else ...[
          if (a.bajaEnTramite)
            const PopupMenuItem(value: 'oficio', child: ListTile(leading: Icon(Ico.oficio), title: Text('Registrar oficio'))),
          if (a.estadoInventario == EstadoInventario.dadoDeBaja)
            const PopupMenuItem(value: 'reactivar', child: ListTile(leading: Icon(Ico.reactivar), title: Text('Reactivar'))),
        ],
      ],
    );
  }
}

class _HistorialDetallado extends ConsumerWidget {
  const _HistorialDetallado({required this.articuloId});

  final String articuloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se relee junto con el resto de la ficha: depende del historial público para refrescarse.
    ref.watch(historialProvider(articuloId));
    return FutureBuilder<List<MovimientoDetallado>>(
      future: ref.read(repositorioProvider).historialConNombres(articuloId),
      builder: (context, snap) {
        final tema = Theme.of(context);
        final lista = snap.data ?? const <MovimientoDetallado>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Titulo('Historial'),
          if (snap.connectionState != ConnectionState.done) const LinearProgressIndicator(),
          if (snap.connectionState == ConnectionState.done && lista.isEmpty) const ListTile(title: Text('Sin movimientos todavía.')),
          for (final m in lista)
            ListTile(
              dense: true,
              leading: Icon(m.conflicto ? Ico.problemaSincronia : Ico.historial, color: m.conflicto ? tema.colorScheme.error : null),
              title: Text('${m.nombre}${m.cantidad == null ? '' : ' · ${m.cantidad}'}${m.aCargo == null ? '' : ' · a cargo de ${m.aCargo}'}'),
              subtitle: Text([
                '${fechaHora(m.fecha)}${m.autorizo == null ? '' : ' · ${m.autorizo}'}',
                if (m.nota != null) m.nota!,
              ].join('\n')),
            ),
        ]);
      },
    );
  }
}
