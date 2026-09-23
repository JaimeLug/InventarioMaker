import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../util/texto.dart';
import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../tema.dart';
import '../widgets/comunes.dart';

class MisSolicitudesSelPantalla extends ConsumerWidget {
  const MisSolicitudesSelPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitudes = ref.watch(misSolicitudesSelProvider);

    return TmArmazon(
      ruta: '/mis-solicitudes-sel',
      titulo: 'Mis solicitudes',
      child: Centrado(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(misSolicitudesSelProvider),
          child: Cargando<List<Map<String, dynamic>>>(
            valor: solicitudes,
            alReintentar: () => ref.invalidate(misSolicitudesSelProvider),
            datos: (lista) {
              if (lista.isEmpty) {
                return ListView(children: [
                  TmVacio(
                    icono: Ico.solicitudes,
                    titulo: 'No tienes solicitudes',
                    texto: 'Pide material prestado desde la ficha de cualquier artículo que esté disponible en el catálogo.',
                    acciones: [
                      TmBoton(
                        'Ver catálogo',
                        tipo: TipoBoton.primario,
                        icono: Ico.inventario,
                        onTap: () => context.push('/inventario'),
                      ),
                    ],
                  ),
                ]);
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: lista.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _TarjetaSolicitudSel(solicitud: lista[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TarjetaSolicitudSel extends ConsumerWidget {
  const _TarjetaSolicitudSel({required this.solicitud});

  final Map<String, dynamic> solicitud;

  Tono _tonoEstado(String estado) => switch (estado) {
        'PENDIENTE' => Tono.aviso,
        'APROBADA' => Tono.ok,
        'ENTREGADO' => Tono.info,
        'DEVUELTA' => Tono.neutro,
        'RECHAZADA' => Tono.error,
        'CANCELADA' => Tono.neutro,
        _ => Tono.neutro,
      };

  String _textoEstado(String estado) => switch (estado) {
        'PENDIENTE' => 'Esperando aprobación',
        'APROBADA' => 'Aprobada · Lista para recoger',
        'ENTREGADO' => 'En préstamo',
        'DEVUELTA' => 'Devuelta',
        'RECHAZADA' => 'Rechazada',
        'CANCELADA' => 'Cancelada',
        _ => estado,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tm;
    final s = solicitud;
    final folio = s['folio'] as String? ?? '';
    final estado = s['estado'] as String? ?? 'PENDIENTE';
    final motivo = s['motivo'] as String? ?? '';
    final articulos = s['articulos'] as String? ?? '';
    final dev = s['fecha_devolucion_comprometida'] as String?;
    final motivoRechazo = s['motivo_rechazo'] as String?;
    final notaAprobacion = s['nota_aprobacion'] as String?;

    DateTime? fechaDev;
    if (dev != null) {
      try {
        fechaDev = DateTime.parse(dev).toLocal();
      } catch (_) {}
    }

    return TmTarjeta(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(folio, style: Tipografia.cuerpoFuerte),
                const Spacer(),
                TmInsignia(_textoEstado(estado), tono: _tonoEstado(estado)),
              ],
            ),
            const SizedBox(height: 8),
            Text(motivo, style: Tipografia.cuerpo),
            if (articulos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.fondo,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(articulos, style: Tipografia.chico),
              ),
            ],
            if (fechaDev != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Ico.reloj, size: 14, color: c.textoSecundario),
                  const SizedBox(width: 4),
                  Text('Devolución: ${fecha(fechaDev)}', style: Tipografia.chico.copyWith(color: c.textoSecundario)),
                ],
              ),
            ],
            if (notaAprobacion != null && notaAprobacion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Nota del responsable: $notaAprobacion',
                  style: Tipografia.chico.copyWith(color: c.primario)),
            ],
            if (motivoRechazo != null && motivoRechazo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Motivo de rechazo: $motivoRechazo',
                  style: Tipografia.chico.copyWith(color: c.error)),
            ],
            if (estado == 'PENDIENTE') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TmBoton(
                  'Cancelar solicitud',
                  tipo: TipoBoton.peligro,
                  icono: Ico.cerrar,
                  onTap: () async {
                    final si = await confirmar(
                      context,
                      titulo: '¿Cancelar solicitud $folio?',
                      consecuencia: 'Tu solicitud de material será cancelada y ya no se procesará.',
                      botonSi: 'Cancelar solicitud',
                      peligro: true,
                    );
                    if (!si || !context.mounted) return;
                    try {
                      await ref.read(repositorioProvider).cancelarSolicitudSeleccion(s['id'] as String);
                      ref.invalidate(misSolicitudesSelProvider);
                      if (context.mounted) avisar(context, 'Solicitud cancelada.');
                    } catch (e) {
                      if (context.mounted) avisarError(context, e);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
