import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/hoja_acceso.dart';
import '../../acceso/sesion.dart';
import '../../datos/errores.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../tema.dart';

/// En la barra superior: "Entrar", o con qué cuenta y nivel se está firmando.
class BarraSesion extends ConsumerWidget {
  const BarraSesion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    return sesion.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => IconButton(icon: const Icon(Icons.sync_problem), tooltip: 'Reintentar', onPressed: () => ref.invalidate(sesionProvider)),
      data: (s) => s == null
          ? TextButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Entrar'),
              onPressed: () async {
                if (await pedirAcceso(context, descripcion: 'entrar al inventario')) ref.invalidate(sesionProvider);
              },
            )
          : PopupMenuButton<String>(
              tooltip: 'Tu sesión',
              onSelected: (opcion) async {
                if (opcion == 'salir') {
                  await ref.read(repositorioProvider).salir();
                  ref.invalidate(sesionProvider);
                } else if (context.mounted) {
                  context.push('/$opcion');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text('${s.nombre}\n${s.rol.nombre}')),
                const PopupMenuItem(value: 'mis-prestamos', child: ListTile(leading: Icon(Icons.outbox_outlined), title: Text('Mis préstamos'))),
                const PopupMenuItem(value: 'mis-reportes', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Mis reportes'))),
                if (s.administra) ...[
                  const PopupMenuItem(value: 'por-revisar', child: ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('Por revisar'))),
                  const PopupMenuItem(
                      value: 'prestamos-abiertos', child: ListTile(leading: Icon(Icons.schedule), title: Text('Préstamos abiertos'))),
                  const PopupMenuItem(value: 'cuentas', child: ListTile(leading: Icon(Icons.group_outlined), title: Text('Cuentas'))),
                ],
                if (s.rol == Rol.subadmin)
                  const PopupMenuItem(value: 'bitacora', child: ListTile(leading: Icon(Icons.history_edu), title: Text('Bitácora'))),
                const PopupMenuItem(value: 'mi-cuenta', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Mi cuenta'))),
                const PopupMenuItem(value: 'salir', child: ListTile(leading: Icon(Icons.logout), title: Text('Cerrar sesión'))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  avatar: Icon(s.nivel == NivelSesion.pin ? Icons.dialpad : Icons.verified_user_outlined, size: 18),
                  label: Text('${s.nombreCorto} · ${s.nivel == NivelSesion.pin ? 'PIN' : 'Contraseña'}'),
                ),
              ),
            ),
    );
  }
}

class Miniatura extends ConsumerWidget {
  const Miniatura({super.key, required this.ruta, this.tamano = 56});

  final String? ruta;
  final double tamano;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final vacio = Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: colores.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.photo_camera_outlined, size: tamano * 0.35, color: colores.outline),
        if (tamano >= 56) Text('Sin foto', style: TextStyle(fontSize: 10, color: colores.outline)),
      ]),
    );
    if (ruta == null) return vacio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        ref.read(repositorioProvider).urlFoto(ruta!),
        width: tamano,
        height: tamano,
        fit: BoxFit.cover,
        cacheWidth: (tamano * 3).round(),
        errorBuilder: (_, _, _) => vacio,
      ),
    );
  }
}

class Insignia extends StatelessWidget {
  const Insignia(this.texto, {super.key, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 3)],
        Text(texto, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

List<Widget> insigniasDe(Articulo a) => [
      if (a.estadoInventario == EstadoInventario.sinClasificar)
        const Insignia('Sin clasificar: no usar', color: Avisos.sinClasificar, icono: Icons.block),
      if (a.cantidadEstimada && !a.conteoDesconocido)
        const Insignia('Cantidad estimada', color: Avisos.estimado, icono: Icons.pin_outlined),
      if (a.conteoDesconocido) const Insignia('Sin contar', color: Avisos.estimado, icono: Icons.pin_outlined),
      if (a.pendientesAbiertos > 0)
        Insignia('${a.pendientesAbiertos} pendiente${a.pendientesAbiertos == 1 ? '' : 's'}',
            color: Avisos.pendiente, icono: Icons.flag_outlined),
      if (a.fueraServicio > 0) Insignia('${a.fueraServicio} fuera de servicio', color: Avisos.sinClasificar),
    ];

/// Pantalla de carga o de error para datos que vienen del servidor.
class Cargando<T> extends StatelessWidget {
  const Cargando({super.key, required this.valor, required this.datos, this.alReintentar});

  final AsyncValue<T> valor;
  final Widget Function(T datos) datos;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return valor.when(
      data: datos,
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(traducir(e).mensaje, textAlign: TextAlign.center),
            if (alReintentar != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: alReintentar, child: const Text('Reintentar')),
            ],
          ]),
        ),
      ),
    );
  }
}
