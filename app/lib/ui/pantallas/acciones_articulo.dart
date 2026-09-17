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
import '../widgets/formularios.dart';

/// Acción que se confirma con un diálogo y luego pasa por el gate.
Future<void> _ejecutar(BuildContext context, WidgetRef ref, Articulo a,
    {required String descripcion, required Requisito requisito, required Future<String> Function(Repositorio repo) accion}) async {
  try {
    final mensaje = await conAcceso<String>(context, ref,
        descripcion: descripcion, requisito: requisito, accion: () => accion(ref.read(repositorioProvider)));
    if (mensaje != null && context.mounted) {
      refrescarArticulo(ref, a.id);
      avisar(context, mensaje);
    }
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}

// --- F-10 Registrar uso ------------------------------------------------------------------
Future<void> registrarUso(BuildContext context, WidgetRef ref, Articulo a) async {
  final comando = const Uuid().v4();
  var cantidad = 1;
  final nota = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Registrar uso: ${a.nombre}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SelectorCantidad(valor: cantidad, minimo: 1, maximo: a.disponible, alCambiar: (v) => setState(() => cantidad = v)),
          Text(plural(a.unidad)),
          const SizedBox(height: 12),
          TextField(controller: nota, decoration: const InputDecoration(labelText: 'Para qué (opcional)', hintText: 'Ej. Práctica de vinil 5°B')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar')),
        ],
      ),
    ),
  );
  final texto = nota.text.trim();
  nota.dispose();
  if (ok != true || !context.mounted) return;
  await _ejecutar(context, ref, a, descripcion: 'registrar el uso de "${a.nombre}"', requisito: Requisito.docente, accion: (repo) async {
    final aplicado = await repo.registrarUso(a.id, cantidad, texto.isEmpty ? null : texto, comando);
    return aplicado ? 'Uso registrado.' : 'Uso registrado. El responsable del laboratorio lo autorizará.';
  });
}

// --- Reparación ------------------------------------------------------------------------------
Future<void> registrarReparacion(BuildContext context, WidgetRef ref, Articulo a) async {
  var cantidad = 1;
  final nota = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Regresa a servicio'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Fuera de servicio: ${a.fueraServicio}'),
          SelectorCantidad(valor: cantidad, minimo: 1, maximo: a.fueraServicio, alCambiar: (v) => setState(() => cantidad = v)),
          TextField(controller: nota, decoration: const InputDecoration(labelText: 'Qué se reparó (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar')),
        ],
      ),
    ),
  );
  final texto = nota.text.trim();
  nota.dispose();
  if (ok != true || !context.mounted) return;
  await _ejecutar(context, ref, a, descripcion: 'registrar la reparación de "${a.nombre}"', requisito: Requisito.administracion,
      accion: (repo) async {
    await repo.reparar(a.id, cantidad, texto.isEmpty ? null : texto);
    return 'Reparación registrada.';
  });
}

// --- F-13 Ajuste de conteo --------------------------------------------------------------------
Future<void> ajustarConteo(BuildContext context, WidgetRef ref, Articulo a) async {
  final enTaller = a.existencia - a.prestado - a.fueraServicio;
  final contados = TextEditingController(text: a.conteoDesconocido ? '' : '$enTaller');
  final nota = TextEditingController();
  var motivo = 'CONTEO_FISICO';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final n = int.tryParse(contados.text);
      final diferencia = n == null ? null : n - enTaller;
      final pareceperdida = motivo == 'NO_SE_ENCONTRO' && (diferencia ?? 0) < 0;
      return AlertDialog(
        title: Text('Ajustar conteo: ${a.nombre}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.conteoDesconocido
                ? 'Nunca se ha contado.'
                : 'En el sistema: ${a.cantidadMostrada} = $enTaller en el taller'
                    '${a.prestado > 0 ? ' + ${a.prestado} prestados' : ''}'
                    '${a.fueraServicio > 0 ? ' + ${a.fueraServicio} fuera de servicio (en el taller aparte)' : ''}.'),
            const SizedBox(height: 12),
            TextField(
              controller: contados,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '¿Cuántos hay aquí, en el taller?', helperText: 'Sin contar lo prestado ni lo dañado'),
              onChanged: (_) => setState(() {}),
            ),
            if (diferencia != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  diferencia == 0 ? 'Coincide.' : (diferencia < 0 ? 'Faltan ${-diferencia}.' : 'Sobran $diferencia.'),
                  style: TextStyle(fontWeight: FontWeight.bold, color: diferencia == 0 ? null : Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: motivo,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [for (final m in motivosAjuste.entries) DropdownMenuItem(value: m.key, child: Text(m.value))],
              onChanged: (v) => setState(() => motivo = v ?? motivo),
            ),
            if (pareceperdida)
              Card(
                margin: const EdgeInsets.only(top: 8),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: const Text('¿Existían y ya no están? Eso es una pérdida.'),
                  subtitle: const Text('Un ajuste corrige un dato mal capturado. Para algo que se perdió, levanta un reporte.'),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                      context.push('/articulo/${a.id}/reportar');
                    },
                    child: const Text('Reportar'),
                  ),
                ),
              ),
            if ((diferencia ?? 0) != 0) ...[
              const SizedBox(height: 12),
              TextField(controller: nota, maxLines: 2, decoration: const InputDecoration(labelText: 'Explica la diferencia *')),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: n == null || ((diferencia ?? 0) != 0 && nota.text.trim().isEmpty) ? null : () => Navigator.pop(context, true),
            child: const Text('Guardar conteo'),
          ),
        ],
      );
    }),
  );
  final n = int.tryParse(contados.text);
  final texto = nota.text.trim();
  contados.dispose();
  nota.dispose();
  if (ok != true || n == null || !context.mounted) return;
  await _ejecutar(context, ref, a, descripcion: 'guardar el conteo de "${a.nombre}"', requisito: Requisito.administracionConfirmada,
      accion: (repo) async {
    final r = await repo.ajustarConteo(a.id, n, motivo, texto.isEmpty ? null : texto);
    return r.diferencia == 0
        ? 'Conteo confirmado. Estado: ${r.estado.nombre}.'
        : 'Ajuste registrado (${r.diferencia > 0 ? '+' : ''}${r.diferencia}). Estado: ${r.estado.nombre}.';
  });
}

// --- F-14 Baja, oficio y reactivación ------------------------------------------------------------
Future<void> darDeBaja(BuildContext context, WidgetRef ref, Articulo a) async {
  var total = true;
  var cantidad = 1;
  var deFuera = false;
  var motivo = 'IRREPARABLE';
  final justificacion = TextEditingController();
  final oficio = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final maximo = deFuera ? a.fueraServicio : a.existencia - a.prestado - a.fueraServicio;
      return AlertDialog(
        title: Text('Dar de baja: ${a.nombre}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Todo el artículo')), ButtonSegment(value: false, label: Text('Algunas piezas'))],
              selected: {total},
              onSelectionChanged: (s) => setState(() => total = s.first),
            ),
            if (total && a.prestado > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Hay ${a.prestado} prestados: primero deben regresar o confirmarse como perdidos.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (!total) ...[
              if (a.fueraServicio > 0)
                CheckboxListTile(
                  value: deFuera,
                  onChanged: (v) => setState(() => [deFuera = v ?? false, cantidad = 1]),
                  title: Text('De las ${a.fueraServicio} fuera de servicio'),
                  contentPadding: EdgeInsets.zero,
                ),
              SelectorCantidad(valor: cantidad, minimo: 1, maximo: maximo < 1 ? 1 : maximo, alCambiar: (v) => setState(() => cantidad = v)),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: motivo,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [for (final m in motivosBaja.entries) DropdownMenuItem(value: m.key, child: Text(m.value))],
              onChanged: (v) => setState(() => motivo = v ?? motivo),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: justificacion,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Justificación *', helperText: 'Al menos 15 letras'),
              onChanged: (_) => setState(() {}),
            ),
            if (total && a.numResguardo != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: oficio,
                decoration: InputDecoration(
                  labelText: 'Número de oficio de baja',
                  helperText: 'Tiene resguardo ${a.numResguardo}. Sin oficio, queda "en trámite".',
                ),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: justificacion.text.trim().length < 15 ? null : () => Navigator.pop(context, true),
            child: const Text('Dar de baja'),
          ),
        ],
      );
    }),
  );
  final just = justificacion.text.trim();
  final ofi = oficio.text.trim();
  justificacion.dispose();
  oficio.dispose();
  if (ok != true || !context.mounted) return;
  await _ejecutar(context, ref, a, descripcion: 'dar de baja "${a.nombre}"', requisito: Requisito.administracionConfirmada,
      accion: (repo) async {
    final enTramite = await repo.darDeBaja(a.id,
        cantidad: total ? null : cantidad, deFueraDeServicio: deFuera, motivo: motivo, justificacion: just, oficio: ofi.isEmpty ? null : ofi);
    if (!total) return 'Baja de $cantidad registrada.';
    return enTramite ? 'Artículo dado de baja. Queda en trámite hasta registrar el oficio.' : 'Artículo dado de baja.';
  });
}

Future<void> registrarOficio(BuildContext context, WidgetRef ref, Articulo a) async {
  final oficio = await pedirTexto(context, titulo: 'Oficio de baja', etiqueta: 'Número de oficio', ayuda: 'Ej. SA/123/2026');
  if (oficio == null || !context.mounted) return;
  await _ejecutar(context, ref, a, descripcion: 'registrar el oficio de baja', requisito: Requisito.administracion, accion: (repo) async {
    await repo.registrarOficioBaja(a.id, oficio);
    return 'Oficio registrado.';
  });
}

Future<void> reactivar(BuildContext context, WidgetRef ref, Articulo a) async {
  final cantidad = TextEditingController(text: '1');
  final justificacion = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Reactivar: ${a.nombre}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Úsalo si se dio de baja por error o el equipo se recuperó.'),
          const SizedBox(height: 12),
          TextField(
            controller: cantidad,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '¿Cuántos hay?'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: justificacion,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Por qué se reactiva *', helperText: 'Al menos 15 letras'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: justificacion.text.trim().length < 15 ? null : () => Navigator.pop(context, true), child: const Text('Reactivar')),
        ],
      ),
    ),
  );
  final n = int.tryParse(cantidad.text) ?? 0;
  final just = justificacion.text.trim();
  cantidad.dispose();
  justificacion.dispose();
  if (ok != true || !context.mounted) return;
  await _ejecutar(context, ref, a, descripcion: 'reactivar "${a.nombre}"', requisito: Requisito.administracionConfirmada,
      accion: (repo) async {
    await repo.reactivar(a.id, n, just);
    return 'Artículo reactivado.';
  });
}
