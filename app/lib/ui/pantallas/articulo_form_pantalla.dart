import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/fotos.dart';

/// Alta de un artículo (F-11) o edición de sus datos. Sin [id] es alta.
///
/// Todo se captura antes de pedir acceso: si hay que identificarse, el formulario
/// sigue aquí debajo y se guarda solo al terminar (F-02).
class ArticuloFormPantalla extends ConsumerStatefulWidget {
  const ArticuloFormPantalla({super.key, this.id});

  final String? id;

  @override
  ConsumerState<ArticuloFormPantalla> createState() => _ArticuloFormPantallaState();
}

class _ArticuloFormPantallaState extends ConsumerState<ArticuloFormPantalla> {
  // Se generan una vez: reintentar un alta nunca la duplica.
  final _idNuevo = const Uuid().v4();
  final _comando = const Uuid().v4();

  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _marca = TextEditingController();
  final _subcategoria = TextEditingController();
  final _cantidad = TextEditingController(text: '1');
  final _unidad = TextEditingController(text: 'pieza');
  final _serie = TextEditingController();
  final _resguardo = TextEditingController();
  final _ubicacion = TextEditingController();
  final _observaciones = TextEditingController();
  final _justificacion = TextEditingController();

  final List<FotoNueva> _fotos = [];
  Categoria? _categoria;
  EstadoFisico? _estadoFisico = EstadoFisico.nuevo;
  Etiquetado? _etiquetado;
  bool _sinConteo = false;
  bool _consumible = false;
  bool _guardando = false;
  Articulo? _original;

  bool get _esAlta => widget.id == null;

  @override
  void initState() {
    super.initState();
    if (!_esAlta) _cargar();
  }

  Future<void> _cargar() async {
    final a = await ref.read(articuloProvider(widget.id!).future);
    if (a == null || !mounted) return;
    setState(() {
      _original = a;
      _nombre.text = a.nombre;
      _marca.text = a.marcaModelo ?? '';
      _subcategoria.text = a.subcategoria ?? '';
      _unidad.text = a.unidad;
      _serie.text = a.numSerie ?? '';
      _resguardo.text = a.numResguardo ?? '';
      _ubicacion.text = a.ubicacionTexto ?? '';
      _observaciones.text = a.observaciones ?? '';
      _categoria = a.categoria;
      _estadoFisico = a.estadoFisico;
      _etiquetado = a.etiquetado;
      _consumible = a.esConsumible;
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _marca, _subcategoria, _cantidad, _unidad, _serie, _resguardo, _ubicacion, _observaciones, _justificacion]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Etiquetado sugerido (F-11): individual si tiene serie o resguardo o es eléctrica; lote si es consumible.
  Etiquetado get _etiquetadoSugerido {
    if (_categoria == Categoria.herramientasElectricas || _serie.text.trim().isNotEmpty || _resguardo.text.trim().isNotEmpty) {
      return Etiquetado.individual;
    }
    return _consumible ? Etiquetado.lote : Etiquetado.contenedor;
  }

  bool get _cambiaEntreVexYFtc =>
      _original != null && _categoria != null && _original!.categoria.esRobotica() && _categoria!.esRobotica() && _original!.categoria != _categoria;

  bool get _sePideJustificacion =>
      _cambiaEntreVexYFtc || (_original?.categoria == Categoria.sinClasificar && _categoria != Categoria.sinClasificar);

  Map<String, dynamic> _datos() => {
        'nombre': _nombre.text.trim(),
        'marca_modelo': _marca.text.trim(),
        'categoria': _categoria!.codigo,
        'subcategoria': _subcategoria.text.trim(),
        'unidad': _unidad.text.trim().isEmpty ? 'pieza' : _unidad.text.trim().toLowerCase(),
        'estado_fisico': _estadoFisico?.codigo,
        'etiquetado': (_etiquetado ?? _etiquetadoSugerido).codigo,
        'ubicacion': _ubicacion.text.trim(),
        'num_resguardo': _resguardo.text.trim(),
        'num_serie': _serie.text.trim(),
        'observaciones': _observaciones.text.trim().isEmpty ? null : _observaciones.text.trim(),
        'es_consumible': _consumible,
      };

  Future<void> _guardar() async {
    if (_esAlta && _fotos.isEmpty) {
      avisar(context, 'Agrega al menos una foto: sin foto no se sabe de qué objeto se trata.');
      return;
    }
    if (!_form.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      if (_esAlta) {
        final codigo = await conAcceso<String>(
          context,
          ref,
          descripcion: 'dar de alta "${_nombre.text.trim()}"',
          requisito: Requisito.administracion,
          accion: () => ref.read(repositorioProvider).crearArticulo(
                id: _idNuevo,
                comando: _comando,
                datos: _datos(),
                cantidad: _sinConteo ? null : int.parse(_cantidad.text),
                fotos: _fotos,
              ),
        );
        if (codigo != null && mounted) {
          ref.invalidate(articulosProvider);
          avisar(context, 'Listo: $codigo dado de alta.');
          context.pushReplacement('/articulo/$_idNuevo');
        }
      } else {
        final hecho = await conAcceso<bool>(
          context,
          ref,
          descripcion: _cambiaEntreVexYFtc
              ? 'pasar "${_nombre.text.trim()}" de ${_original!.categoria.nombre} a ${_categoria!.nombre}'
              : 'guardar cambios de "${_nombre.text.trim()}"',
          requisito: _cambiaEntreVexYFtc ? Requisito.administracionConfirmada : Requisito.administracion,
          accion: () async {
            final datos = _datos()..remove('estado_fisico');
            if (_estadoFisico != null) datos['estado_fisico'] = _estadoFisico!.codigo;
            await ref.read(repositorioProvider).editarArticulo(widget.id!, datos,
                justificacion: _justificacion.text.trim().isEmpty ? null : _justificacion.text.trim());
            return true;
          },
        );
        if (hecho == true && mounted) {
          refrescarArticulo(ref, widget.id!);
          avisar(context, 'Cambios guardados.');
          context.pop();
        }
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _agregarFoto() async {
    final foto = await elegirFoto(context);
    if (foto != null) setState(() => _fotos.add(foto));
  }

  @override
  Widget build(BuildContext context) {
    if (!_esAlta && _original == null) {
      return Scaffold(appBar: AppBar(title: const Text('Editar artículo')), body: const Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);

    return PopScope(
      canPop: !_guardando,
      child: Scaffold(
        appBar: AppBar(title: Text(_esAlta ? 'Nuevo artículo' : 'Editar ${_original!.codigo}'), actions: const [BarraSesion()]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_esAlta ? 'Dar de alta' : 'Guardar cambios'),
            ),
          ),
        ),
        body: Centrado(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_esAlta) ...[
                  const _Paso(1, 'Fotos', 'Sin foto no hay artículo. La primera será la principal.'),
                  _FotosElegidas(fotos: _fotos, alAgregar: _agregarFoto, alQuitar: (f) => setState(() => _fotos.remove(f)), alCambiar: () => setState(() {})),
                ],
                _Paso(_esAlta ? 2 : 1, 'Qué es', null),
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej. Vernier digital'),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => v == null || v.trim().length < 3 ? 'Escribe el nombre del artículo.' : null,
                  onChanged: (_) => setState(() {}),
                ),
                if (_esAlta) _Parecidos(nombre: _nombre.text, categoria: _categoria),
                const SizedBox(height: 12),
                TextFormField(controller: _marca, decoration: const InputDecoration(labelText: 'Marca / modelo')),
                const SizedBox(height: 12),
                DropdownButtonFormField<Categoria>(
                  value: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría *'),
                  items: [
                    for (final c in Categoria.values)
                      if (c != Categoria.sinClasificar || _original?.categoria == Categoria.sinClasificar)
                        DropdownMenuItem(value: c, child: Text(c.nombre)),
                  ],
                  validator: (v) => v == null || v == Categoria.sinClasificar ? 'Elige la categoría.' : null,
                  onChanged: (v) => setState(() {
                    _categoria = v;
                    if (v == Categoria.consumibles) _consumible = true;
                  }),
                ),
                if (_sePideJustificacion) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: _cambiaEntreVexYFtc ? tema.colorScheme.errorContainer : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_cambiaEntreVexYFtc)
                          const Text('VEX y FTC no se mezclan. Pasar una pieza de uno a otro queda registrado con tu nombre '
                              'y te pedirá confirmar tu contraseña.'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _justificacion,
                          decoration: const InputDecoration(labelText: '¿Por qué cambia de categoría?', hintText: 'Ej. Tiene logo de REV'),
                          validator: (v) => _cambiaEntreVexYFtc && (v == null || v.trim().isEmpty) ? 'Escribe por qué.' : null,
                        ),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(controller: _subcategoria, decoration: const InputDecoration(labelText: 'Subcategoría', hintText: 'Ej. Medición')),
                _Paso(_esAlta ? 3 : 2, 'Cantidad y estado', _esAlta ? null : 'La cantidad no se edita aquí: cambia solo con movimientos.'),
                if (_esAlta) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cantidad,
                        enabled: !_sinConteo,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Cantidad contada'),
                        validator: (v) => _sinConteo || (v != null && int.tryParse(v) != null) ? null : 'Escribe cuántos hay.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _CampoUnidad(controller: _unidad)),
                  ]),
                  CheckboxListTile(
                    value: _sinConteo,
                    onChanged: (v) => setState(() => _sinConteo = v ?? false),
                    title: const Text('Aún no sé cuántos hay'),
                    subtitle: const Text('Queda como "por contar" y no se presta hasta contarlo.'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ] else
                  _CampoUnidad(controller: _unidad),
                SwitchListTile(
                  value: _consumible,
                  onChanged: (v) => setState(() => _consumible = v),
                  title: const Text('Es consumible'),
                  subtitle: const Text('Se gasta y no se devuelve (cinta, lija, filamento…).'),
                  contentPadding: EdgeInsets.zero,
                ),
                DropdownButtonFormField<EstadoFisico>(
                  value: _estadoFisico,
                  decoration: const InputDecoration(labelText: 'Estado físico'),
                  items: [for (final e in EstadoFisico.values) DropdownMenuItem(value: e, child: Text(e.nombre))],
                  onChanged: (v) => setState(() => _estadoFisico = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serie,
                  decoration: const InputDecoration(labelText: 'Número de serie'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _resguardo,
                  decoration: const InputDecoration(labelText: 'Número de resguardo', hintText: 'P13/0000'),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                ),
                _Paso(_esAlta ? 4 : 3, 'Dónde vive', 'Los contenedores con QR (cajones, gavetas) llegan en la Fase 4.'),
                TextFormField(
                  controller: _ubicacion,
                  decoration: const InputDecoration(labelText: 'Ubicación', hintText: 'Ej. Gabinete 2, cajón B'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Etiquetado>(
                  value: _etiquetado,
                  decoration: InputDecoration(
                    labelText: 'Etiquetado',
                    helperText: _etiquetado == null ? 'Sugerido: ${_etiquetadoSugerido.nombre}' : _etiquetado!.explicacion,
                  ),
                  items: [for (final e in Etiquetado.values) DropdownMenuItem(value: e, child: Text(e.nombre))],
                  onChanged: (v) => setState(() => _etiquetado = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observaciones,
                  decoration: const InputDecoration(labelText: 'Observaciones'),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso(this.numero, this.titulo, this.ayuda);

  final int numero;
  final String titulo;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 14, child: Text('$numero', style: tema.textTheme.labelLarge)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: tema.textTheme.titleMedium),
            if (ayuda != null) Text(ayuda!, style: tema.textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _CampoUnidad extends StatelessWidget {
  const _CampoUnidad({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: controller.value,
      optionsBuilder: (v) => unidadesComunes.where((u) => u.startsWith(normalizar(v.text))),
      onSelected: (u) => controller.text = u,
      fieldViewBuilder: (context, campo, foco, _) => TextFormField(
        controller: campo,
        focusNode: foco,
        decoration: const InputDecoration(labelText: 'Unidad', hintText: 'pieza, caja, bolsa…'),
        onChanged: (t) => controller.text = t,
      ),
    );
  }
}

class _FotosElegidas extends StatelessWidget {
  const _FotosElegidas({required this.fotos, required this.alAgregar, required this.alQuitar, required this.alCambiar});

  final List<FotoNueva> fotos;
  final VoidCallback alAgregar;
  final ValueChanged<FotoNueva> alQuitar;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final (i, f) in fotos.indexed)
        SizedBox(
          width: 140,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(f.bytes, width: 140, height: 140, fit: BoxFit.cover)),
              Positioned(
                right: 0,
                child: IconButton.filledTonal(icon: const Icon(Icons.close), tooltip: 'Quitar', onPressed: () => alQuitar(f)),
              ),
              if (i == 0)
                const Positioned(left: 6, bottom: 6, child: Chip(label: Text('Principal'), visualDensity: VisualDensity.compact)),
            ]),
            DropdownButton<TipoFoto>(
              value: f.tipo,
              isExpanded: true,
              items: [for (final t in TipoFoto.delCatalogo) DropdownMenuItem(value: t, child: Text(t.nombre))],
              onChanged: (t) {
                if (t == null) return;
                f.tipo = t;
                alCambiar();
              },
            ),
          ]),
        ),
      SizedBox(
        width: 140,
        height: 140,
        child: OutlinedButton(
          onPressed: alAgregar,
          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_a_photo_outlined, size: 32),
            SizedBox(height: 8),
            Text('Agregar foto', textAlign: TextAlign.center),
          ]),
        ),
      ),
    ]);
  }
}

/// Evita duplicados: si ya hay algo con nombre parecido en la misma categoría, lo muestra.
class _Parecidos extends ConsumerWidget {
  const _Parecidos({required this.nombre, required this.categoria});

  final String nombre;
  final Categoria? categoria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palabras = normalizar(nombre).split(' ').where((p) => p.length >= 4).toList();
    if (palabras.isEmpty) return const SizedBox.shrink();
    final todos = ref.watch(articulosProvider).value ?? const <Articulo>[];
    final parecidos = todos
        .where((a) => (categoria == null || a.categoria == categoria) && palabras.every(normalizar(a.nombre).contains))
        .take(3)
        .toList();
    if (parecidos.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('¿Es alguno de estos? Si es el mismo, no lo des de alta otra vez.'),
        ),
        for (final a in parecidos)
          ListTile(
            leading: Miniatura(ruta: a.fotoPrincipal, tamano: 40),
            title: Text(a.nombre),
            subtitle: Text('${a.codigo} · ${a.cantidadMostrada}'),
            onTap: () => context.push('/articulo/${a.id}'),
          ),
      ]),
    );
  }
}
