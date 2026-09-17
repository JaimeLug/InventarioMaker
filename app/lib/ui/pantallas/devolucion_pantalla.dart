import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

/// Recibir una devolución (F-08): total, parcial, con daño o con faltantes perdidos.
class DevolucionPantalla extends ConsumerWidget {
  const DevolucionPantalla({super.key, required this.articuloId});

  final String articuloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articulo = ref.watch(articuloProvider(articuloId)).value;
    return Scaffold(
      appBar: AppBar(title: Text(articulo == null ? 'Recibir devolución' : 'Devolución: ${articulo.codigo}'), actions: const [BarraSesion()]),
      body: Centrado(
        child: CargaConAcceso<List<PrestamoAbierto>>(
          descripcion: 'recibir una devolución',
          requisito: Requisito.docente,
          cargar: (repo) => repo.prestamosDeArticulo(articuloId),
          construir: (context, prestamos, _) => prestamos.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hay préstamos abiertos de este artículo.')))])
              : _Devolucion(articuloId: articuloId, nombre: articulo?.nombre ?? '', unidad: articulo?.unidad ?? 'pieza', prestamos: prestamos),
        ),
      ),
    );
  }
}

class _Devolucion extends ConsumerStatefulWidget {
  const _Devolucion({required this.articuloId, required this.nombre, required this.unidad, required this.prestamos});

  final String articuloId;
  final String nombre;
  final String unidad;
  final List<PrestamoAbierto> prestamos;

  @override
  ConsumerState<_Devolucion> createState() => _DevolucionState();
}

class _DevolucionState extends ConsumerState<_Devolucion> {
  final _comando = const Uuid().v4();
  final _idDano = const Uuid().v4();
  final _idPerdida = const Uuid().v4();
  late PrestamoAbierto _prestamo = widget.prestamos.first;
  late int _regresan = _prestamo.pendiente;
  int _danadas = 0;
  bool _perdido = false;
  bool _sinFoto = false;
  bool _guardando = false;
  final _notaDano = TextEditingController();
  final _notaPerdida = TextEditingController();
  final _justificacion = TextEditingController();
  final _fotosDano = <FotoNueva>[];
  final _fotosPerdida = <FotoNueva>[];

  int get _faltan => _prestamo.pendiente - _regresan;

  @override
  void dispose() {
    for (final c in [_notaDano, _notaPerdida, _justificacion]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _problema() {
    if (_regresan == 0 && !(_faltan > 0 && _perdido)) return 'Indica cuántos regresan.';
    if (_danadas > 0) {
      if (_notaDano.text.trim().length < 15) return 'Describe el daño (al menos 15 letras).';
      if (_fotosDano.isEmpty) return 'Toma al menos una foto del daño.';
    }
    if (_faltan > 0 && _perdido) {
      if (_notaPerdida.text.trim().length < 15) return 'Describe qué pasó con lo que falta (al menos 15 letras).';
      if (_fotosPerdida.isEmpty && (!_sinFoto || _justificacion.text.trim().length < 15)) {
        return 'Agrega una foto o explica por qué no se puede tomar.';
      }
    }
    return null;
  }

  Future<void> _guardar() async {
    final problema = _problema();
    if (problema != null) {
      avisar(context, problema);
      return;
    }
    setState(() => _guardando = true);
    try {
      final hecho = await conAcceso<bool>(
        context,
        ref,
        descripcion: 'recibir la devolución de "${widget.nombre}"',
        requisito: Requisito.docente,
        accion: () async {
          await ref.read(repositorioProvider).devolver(
                comando: _comando,
                prestamoId: _prestamo.id,
                regresan: _regresan,
                danadas: _danadas,
                incidenciaDanoId: _idDano,
                notaDano: _notaDano.text.trim(),
                fotosDano: _fotosDano,
                faltantePerdido: _faltan > 0 && _perdido,
                incidenciaPerdidaId: _idPerdida,
                notaPerdida: _notaPerdida.text.trim(),
                fotosPerdida: _fotosPerdida,
                sinFotoPerdida: _sinFoto ? _justificacion.text.trim() : null,
              );
          return true;
        },
      );
      if (hecho != true || !mounted) return;
      refrescarArticulo(ref, widget.articuloId);
      final reportes = (_danadas > 0 ? 1 : 0) + (_faltan > 0 && _perdido ? 1 : 0);
      avisar(context, [
        'Devolución registrada: regresaron $_regresan de ${_prestamo.pendiente}.',
        if (_faltan > 0 && !_perdido) 'Quedan $_faltan pendientes a nombre de ${_prestamo.aCargo}.',
        if (reportes > 0) 'Se avisó al responsable para revisar.',
      ].join(' '));
      context.pop();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Préstamo', style: tema.textTheme.titleMedium),
      for (final p in widget.prestamos)
        RadioListTile<String>(
          value: p.id,
          groupValue: _prestamo.id,
          onChanged: (_) => setState(() {
            _prestamo = p;
            _regresan = p.pendiente;
            _danadas = 0;
          }),
          title: Text(p.aCargo),
          subtitle: Text('Pendientes: ${conUnidad(p.pendiente, widget.unidad)} · '
              '${p.vencido ? 'VENCIDO desde' : 'vence'} ${fechaHora(p.venceEn)}'
              '${p.autorizo == null ? '' : ' · prestó ${p.autorizo}'}'),
          contentPadding: EdgeInsets.zero,
        ),
      const Divider(height: 32),
      Text('Qué regresa', style: tema.textTheme.titleMedium),
      const SizedBox(height: 8),
      SelectorCantidad(
        etiqueta: 'Regresan',
        valor: _regresan,
        maximo: _prestamo.pendiente,
        alCambiar: (v) => setState(() {
          _regresan = v;
          if (_danadas > v) _danadas = v;
        }),
      ),
      const SizedBox(height: 8),
      SelectorCantidad(etiqueta: 'Con daño', valor: _danadas, maximo: _regresan, alCambiar: (v) => setState(() => _danadas = v)),
      if (_danadas > 0) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _notaDano,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Qué le pasó *', hintText: 'Ej. La punta roja llegó quemada'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        SelectorFotos(fotos: _fotosDano, texto: 'Foto del daño *', alCambiar: () => setState(() {})),
        const SizedBox(height: 4),
        Text('Las piezas dañadas quedan apartadas hasta que el responsable lo revise.', style: tema.textTheme.bodySmall),
      ],
      if (_faltan > 0) ...[
        const Divider(height: 32),
        Text('Faltan ${conUnidad(_faltan, widget.unidad)}', style: tema.textTheme.titleMedium),
        RadioListTile<bool>(
          value: false,
          groupValue: _perdido,
          onChanged: (_) => setState(() => _perdido = false),
          title: const Text('Las traerá después'),
          subtitle: Text('Siguen a nombre de ${_prestamo.aCargo}.'),
          contentPadding: EdgeInsets.zero,
        ),
        RadioListTile<bool>(
          value: true,
          groupValue: _perdido,
          onChanged: (_) => setState(() => _perdido = true),
          title: const Text('Se perdieron'),
          subtitle: const Text('Se reporta al responsable; queda a nombre de quien las tenía.'),
          contentPadding: EdgeInsets.zero,
        ),
        if (_perdido) ...[
          TextField(
            controller: _notaPerdida,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Qué pasó *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          SelectorFotos(fotos: _fotosPerdida, alCambiar: () => setState(() {})),
          CheckboxListTile(
            value: _sinFoto,
            onChanged: (v) => setState(() => _sinFoto = v ?? false),
            title: const Text('No es posible tomar foto'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_sinFoto)
            TextField(
              controller: _justificacion,
              decoration: const InputDecoration(labelText: 'Por qué no *', hintText: 'Ej. Se perdieron fuera de la escuela'),
              onChanged: (_) => setState(() {}),
            ),
        ],
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _guardando ? null : _guardar,
        icon: _guardando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.move_to_inbox),
        label: const Text('Registrar devolución'),
      ),
    ]);
  }
}
