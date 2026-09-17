import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';

/// Por revisar (responsable y sub administración): reportes y consumos por autorizar.
class PorRevisarPantalla extends ConsumerWidget {
  const PorRevisarPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Por revisar')),
      body: Centrado(
        child: CargaConAcceso<List<Incidencia>>(
          descripcion: 'revisar reportes',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.porRevisar(),
          construir: (context, lista, recargar) => _Revision(lista: lista, recargar: recargar),
        ),
      ),
    );
  }
}

class _Revision extends ConsumerStatefulWidget {
  const _Revision({required this.lista, required this.recargar});

  final List<Incidencia> lista;
  final Future<void> Function() recargar;

  @override
  ConsumerState<_Revision> createState() => _RevisionState();
}

class _RevisionState extends ConsumerState<_Revision> {
  final _consumosElegidos = <String>{};
  bool _inicializado = false;

  List<Incidencia> get _reportes => widget.lista.where((i) => i.tipo != 'CONSUMO').toList();
  List<Incidencia> get _consumos => widget.lista.where((i) => i.tipo == 'CONSUMO').toList();

  Future<void> _resolver(List<Incidencia> cuales, {required bool confirmar}) async {
    String? motivo;
    if (!confirmar) {
      motivo = await pedirTexto(context,
          titulo: 'Descartar', etiqueta: 'Por qué se descarta *', ayuda: 'Ej. Apareció en el cajón C', boton: 'Descartar');
      if (motivo == null || !mounted) return;
    }
    final descripcion = cuales.length == 1
        ? '${confirmar ? 'confirmar' : 'descartar'} ${cuales.first.nombreTipo.toLowerCase()} de "${cuales.first.nombre}"'
        : '${confirmar ? 'autorizar' : 'descartar'} ${cuales.length} consumos';
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: descripcion, requisito: Requisito.administracionConfirmada,
          accion: () async {
        await ref.read(repositorioProvider).resolverIncidencias([for (final i in cuales) i.id], confirmar: confirmar, motivo: motivo);
        return true;
      });
      if (hecho != true || !mounted) return;
      for (final i in cuales) {
        refrescarArticulo(ref, i.articuloId);
      }
      avisar(context, confirmar ? 'Listo: aplicado.' : 'Descartado.');
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _preguntar(Incidencia i) async {
    final texto = await pedirTexto(context, titulo: 'Pedir más información', etiqueta: 'Pregunta para ${i.reportadaPor}', boton: 'Enviar');
    if (texto == null || !mounted) return;
    try {
      await conAcceso<bool>(context, ref, descripcion: 'comentar el reporte', requisito: Requisito.docente, accion: () async {
        await ref.read(repositorioProvider).comentarIncidencia(i.id, texto);
        return true;
      });
      await widget.recargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_inicializado) {
      _consumosElegidos.addAll(_consumos.map((c) => c.id));
      _inicializado = true;
    }
    final tema = Theme.of(context);
    if (widget.lista.isEmpty) {
      return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hay nada por revisar.')))]);
    }
    final elegidos = _consumos.where((c) => _consumosElegidos.contains(c.id)).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (_reportes.isNotEmpty) Text('Reportes de pérdida y daño', style: tema.textTheme.titleMedium),
      for (final i in _reportes)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i.nombreTipo}: ${conUnidad(i.cantidad, i.unidad)} de ${i.nombre}', style: tema.textTheme.titleSmall),
              Text('${i.codigo} · ${i.enTaller ? 'en el taller' : 'estaba prestado'}', style: tema.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(i.nota),
              if (i.sinFotoJustificacion != null) Text('Sin foto: ${i.sinFotoJustificacion}', style: tema.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (i.fotos.isNotEmpty) Wrap(spacing: 8, children: [for (final f in i.fotos) FotoPrivada(ruta: f)]),
              const SizedBox(height: 8),
              Text([
                'Reportó ${i.reportadaPor} el ${fechaHora(i.reportadaEn)}',
                if (i.aCargo != null) 'A cargo de: ${i.aCargo}',
              ].join('\n'), style: tema.textTheme.bodySmall),
              for (final c in i.comentarios)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('💬 ${c.autor}: ${c.texto}', style: tema.textTheme.bodySmall)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: () => _resolver([i], confirmar: true), child: const Text('Confirmar')),
                OutlinedButton(onPressed: () => _resolver([i], confirmar: false), child: const Text('Descartar')),
                TextButton(onPressed: () => _preguntar(i), child: const Text('Pedir información')),
                TextButton(onPressed: () => context.push('/articulo/${i.articuloId}'), child: const Text('Ver artículo')),
              ]),
            ]),
          ),
        ),
      if (_consumos.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Consumos por autorizar', style: tema.textTheme.titleMedium),
        for (final c in _consumos)
          CheckboxListTile(
            value: _consumosElegidos.contains(c.id),
            onChanged: (v) => setState(() => v == true ? _consumosElegidos.add(c.id) : _consumosElegidos.remove(c.id)),
            title: Text('${conUnidad(c.cantidad, c.unidad)} de ${c.nombre}'),
            subtitle: Text('${c.reportadaPor} · ${fechaHora(c.reportadaEn)}${c.nota == 'Consumo' ? '' : ' · ${c.nota}'}'),
          ),
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: elegidos.isEmpty ? null : () => _resolver(elegidos, confirmar: true),
            child: Text('Autorizar ${elegidos.length}'),
          ),
          OutlinedButton(onPressed: elegidos.isEmpty ? null : () => _resolver(elegidos, confirmar: false), child: const Text('Descartar')),
        ]),
      ],
    ]);
  }
}

/// Mis reportes: en qué quedaron y las preguntas del responsable.
class MisReportesPantalla extends ConsumerWidget {
  const MisReportesPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reportes')),
      body: Centrado(
        child: CargaConAcceso<List<Incidencia>>(
          descripcion: 'ver tus reportes',
          requisito: Requisito.docente,
          cargar: (repo) => repo.misReportes(),
          construir: (context, lista, recargar) {
            final tema = Theme.of(context);
            if (lista.isEmpty) {
              return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No has levantado reportes.')))]);
            }
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final i in lista)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${i.nombreTipo}: ${i.cantidad} · ${i.nombre}', style: tema.textTheme.titleSmall)),
                        Chip(label: Text(i.nombreEstado)),
                      ]),
                      Text(i.nota),
                      if (i.fotos.isNotEmpty) Wrap(spacing: 8, children: [for (final f in i.fotos) FotoPrivada(ruta: f, tamano: 64)]),
                      if (i.resueltaPor != null)
                        Text('${i.nombreEstado} por ${i.resueltaPor}${i.motivoResolucion == null ? '' : ': ${i.motivoResolucion}'}',
                            style: tema.textTheme.bodySmall),
                      for (final c in i.comentarios) Text('💬 ${c.autor}: ${c.texto}', style: tema.textTheme.bodySmall),
                      if (i.estado == 'PENDIENTE' && i.comentarios.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            final texto = await pedirTexto(context, titulo: 'Responder', etiqueta: 'Tu respuesta', boton: 'Enviar');
                            if (texto == null || !context.mounted) return;
                            try {
                              await conAcceso<bool>(context, ref, descripcion: 'responder', requisito: Requisito.docente, accion: () async {
                                await ref.read(repositorioProvider).comentarIncidencia(i.id, texto);
                                return true;
                              });
                              await recargar();
                            } on Object catch (e) {
                              if (context.mounted) avisarError(context, e);
                            }
                          },
                          child: const Text('Responder'),
                        ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
