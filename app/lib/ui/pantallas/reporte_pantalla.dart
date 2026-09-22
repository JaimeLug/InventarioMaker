import '../armazon.dart';
import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

/// Reportar pérdida o daño (F-09). No descuenta nada: queda en revisión del responsable.
class ReportePantalla extends ConsumerStatefulWidget {
  const ReportePantalla({super.key, required this.articuloId});

  final String articuloId;

  @override
  ConsumerState<ReportePantalla> createState() => _ReportePantallaState();
}

class _ReportePantallaState extends ConsumerState<ReportePantalla> {
  final _id = const Uuid().v4();
  final _nota = TextEditingController();
  final _justificacion = TextEditingController();
  final _fotos = <FotoNueva>[];
  String _tipo = 'DANO';
  int _cantidad = 1;
  bool _prestado = false;
  PrestamoAbierto? _prestamo;
  bool _sinFoto = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nota.dispose();
    _justificacion.dispose();
    super.dispose();
  }

  Future<void> _elegirPrestamo(Articulo a) async {
    try {
      final prestamos = await conAcceso(
        context,
        ref,
        descripcion: 'ver los préstamos de "${a.nombre}"',
        requisito: Requisito.docente,
        accion: () => ref.read(repositorioProvider).prestamosDeArticulo(a.id),
      );
      if (prestamos == null || !mounted) return;
      if (prestamos.isEmpty) {
        avisar(context, 'Este artículo no tiene préstamos abiertos.');
        return;
      }
      final elegido = await showDialog<PrestamoAbierto>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('¿Qué préstamo?'),
          children: [
            for (final p in prestamos)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: ListTile(title: Text(p.aCargo), subtitle: Text('Pendientes: ${p.pendiente} · desde ${fecha(p.fecha)}')),
              ),
          ],
        ),
      );
      if (elegido != null) setState(() => [_prestamo = elegido, _cantidad = 1]);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _guardar(Articulo a) async {
    String? problema;
    if (_nota.text.trim().length < 15) problema = 'Describe qué pasó (al menos 15 letras).';
    if (_fotos.isEmpty && (!_sinFoto || _justificacion.text.trim().length < 15)) {
      problema ??= 'Agrega una foto o explica por qué no se puede tomar.';
    }
    if (_prestado && _prestamo == null) problema ??= 'Elige el préstamo.';
    if (problema != null) {
      avisar(context, problema);
      return;
    }
    setState(() => _guardando = true);
    try {
      final hecho = await conAcceso<bool>(
        context,
        ref,
        descripcion: 'reportar ${_tipo == 'DANO' ? 'un daño' : 'una pérdida'} de "${a.nombre}"',
        requisito: Requisito.docente,
        accion: () async {
          await ref.read(repositorioProvider).reportar(
                id: _id,
                articuloId: a.id,
                tipo: _tipo,
                cantidad: _cantidad,
                nota: _nota.text.trim(),
                fotos: _fotos,
                prestamoId: _prestado ? _prestamo?.id : null,
                sinFoto: _sinFoto ? _justificacion.text.trim() : null,
              );
          return true;
        },
      );
      if (hecho == true && mounted) {
        refrescarArticulo(ref, a.id);
        avisar(context, 'Reporte enviado. El responsable del laboratorio lo revisará.');
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
    final articulo = ref.watch(articuloProvider(widget.articuloId));
    return TmArmazon(
             ruta: '/inventario',
             titulo: 'Reportar problema',
             conRegresar: true,
             child: Cargando<Articulo?>(
        valor: articulo,
        datos: (a) {
          if (a == null) return const Center(child: Text('El artículo no existe.'));
          final tema = Theme.of(context);
          final enTaller = a.existencia - a.prestado - a.fueraServicio;
          final maximo = _prestado ? (_prestamo?.pendiente ?? 1) : enTaller;
          return Centrado(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Miniatura(ruta: a.fotoPrincipal, tamano: 48),
                title: Text(a.nombre),
                subtitle: Text(a.codigo),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'DANO', icon: Icon(Ico.reparar), label: Text('Se dañó')),
                  ButtonSegment(value: 'PERDIDA', icon: Icon(Ico.perdida), label: Text('Se perdió')),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() {
                  _tipo = s.first;
                  if (_tipo == 'DANO') _prestado = false;
                }),
              ),
              if (_tipo == 'PERDIDA')
                SwitchListTile(
                  value: _prestado,
                  onChanged: (v) => setState(() => _prestado = v),
                  title: const Text('Se perdió estando prestado'),
                  subtitle: Text(_prestado
                      ? (_prestamo == null ? 'Elige el préstamo' : 'A nombre de ${_prestamo!.aCargo}')
                      : 'Estaba en el taller'),
                  contentPadding: EdgeInsets.zero,
                ),
              if (_prestado)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(onPressed: () => _elegirPrestamo(a), child: Text(_prestamo == null ? 'Elegir préstamo' : 'Cambiar préstamo')),
                ),
              if (_tipo == 'DANO')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Si algo prestado regresa dañado, regístralo al recibir la devolución.', style: tema.textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              SelectorCantidad(
                etiqueta: 'Cantidad',
                valor: _cantidad.clamp(1, maximo < 1 ? 1 : maximo),
                minimo: 1,
                maximo: maximo < 1 ? 1 : maximo,
                alCambiar: (v) => setState(() => _cantidad = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nota,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Qué pasó *', hintText: 'Ej. El cautín no calienta, cable pelado cerca del mango'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SelectorFotos(fotos: _fotos, texto: 'Foto *', alCambiar: () => setState(() {})),
              CheckboxListTile(
                value: _sinFoto,
                onChanged: (v) => setState(() => _sinFoto = v ?? false),
                title: const Text('No es posible tomar foto'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_sinFoto)
                TextField(controller: _justificacion, decoration: const InputDecoration(labelText: 'Por qué no *')),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _guardando ? null : () => _guardar(a),
                icon: _guardando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Ico.reportar),
                label: const Text('Enviar reporte'),
              ),
            ]),
          );
        },
      ),
           );
  }
}
