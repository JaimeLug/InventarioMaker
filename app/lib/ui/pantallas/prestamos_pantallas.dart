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

/// Lo que tengo a mi nombre y lo que presté a alumnos o maestros.
class MisPrestamosPantalla extends StatelessWidget {
  const MisPrestamosPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis préstamos')),
      body: Centrado(
        child: CargaConAcceso<List<PrestamoListado>>(
          descripcion: 'ver tus préstamos',
          requisito: Requisito.docente,
          cargar: (repo) => repo.misPrestamos(),
          construir: (context, lista, recargar) => _ListaPrestamos(lista: lista, recargar: recargar, vacio: 'No tienes préstamos abiertos.'),
        ),
      ),
    );
  }
}

/// Todo lo que está fuera del taller (responsable y sub administración).
class PrestamosAbiertosPantalla extends StatelessWidget {
  const PrestamosAbiertosPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préstamos abiertos')),
      body: Centrado(
        child: CargaConAcceso<List<PrestamoListado>>(
          descripcion: 'ver los préstamos abiertos',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.prestamosAbiertos(),
          construir: (context, lista, recargar) => _ListaPrestamos(lista: lista, recargar: recargar, vacio: 'No hay nada prestado.'),
        ),
      ),
    );
  }
}

class _ListaPrestamos extends ConsumerWidget {
  const _ListaPrestamos({required this.lista, required this.recargar, required this.vacio});

  final List<PrestamoListado> lista;
  final Future<void> Function() recargar;
  final String vacio;

  Future<void> _extender(BuildContext context, WidgetRef ref, PrestamoListado p) async {
    final fechaNueva = await elegirFechaDevolucion(context, desde: p.venceEn.isAfter(DateTime.now()) ? p.venceEn : null);
    if (fechaNueva == null || !context.mounted) return;
    final motivo = await pedirTexto(context, titulo: 'Extender hasta el ${fecha(fechaNueva)}', etiqueta: 'Por qué se extiende *', boton: 'Extender');
    if (motivo == null || !context.mounted) return;
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: 'extender el préstamo de "${p.nombre}"', requisito: Requisito.docente,
          accion: () async {
        await ref.read(repositorioProvider).extenderPrestamo(p.id, fechaNueva, motivo);
        return true;
      });
      if (hecho == true && context.mounted) {
        ref.invalidate(vencidosProvider);
        avisar(context, 'Préstamo extendido hasta el ${fecha(fechaNueva)}.');
        await recargar();
      }
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    if (lista.isEmpty) return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(vacio)))]);
    final vencidos = lista.where((p) => p.vencido).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (vencidos > 0)
        Card(
          color: tema.colorScheme.errorContainer,
          child: ListTile(leading: const Icon(Icons.warning_amber), title: Text('$vencidos vencido${vencidos == 1 ? '' : 's'}')),
        ),
      for (final p in lista)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${conUnidad(p.pendiente, p.unidad)} · ${p.nombre}', style: tema.textTheme.titleSmall),
              Text('${p.codigo} · a cargo de ${p.aMiNombre ? 'ti' : p.aCargo}${p.autorizo == null ? '' : ' · prestó ${p.autorizo}'}',
                  style: tema.textTheme.bodySmall),
              Text(
                '${p.vencido ? 'VENCIDO desde' : 'Vence'} ${fechaHora(p.venceEn)}${p.extensiones > 0 ? ' (extendido ${p.extensiones} vez)' : ''}',
                style: tema.textTheme.bodyMedium?.copyWith(color: p.vencido ? tema.colorScheme.error : null),
              ),
              Wrap(spacing: 8, children: [
                TextButton(onPressed: () => context.push('/articulo/${p.articuloId}/devolver'), child: const Text('Recibir devolución')),
                TextButton(onPressed: () => _extender(context, ref, p), child: const Text('Extender')),
              ]),
            ]),
          ),
        ),
    ]);
  }
}
