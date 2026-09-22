import '../diseno/iconos.dart';
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
import '../../sin_conexion/cola.dart';
import '../pantallas/sin_conexion_pantallas.dart';
import '../tema.dart';

/// En la barra superior: "Entrar", o con qué cuenta y nivel se está firmando.
class BarraSesion extends ConsumerWidget {
  const BarraSesion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    return Row(mainAxisSize: MainAxisSize.min, children: [const IndicadorConexion(), _sesion(context, ref, sesion)]);
  }

  Widget _sesion(BuildContext context, WidgetRef ref, AsyncValue<Sesion?> sesion) {
    return sesion.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => IconButton(icon: const Icon(Ico.problemaSincronia), tooltip: 'Reintentar', onPressed: () => ref.invalidate(sesionProvider)),
      data: (s) => s == null
          ? TextButton.icon(
              icon: const Icon(Ico.entrar),
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
                const PopupMenuItem(value: 'mis-prestamos', child: ListTile(leading: Icon(Ico.prestar), title: Text('Mis préstamos'))),
                const PopupMenuItem(value: 'mis-reportes', child: ListTile(leading: Icon(Ico.reportar), title: Text('Mis reportes'))),
                const PopupMenuItem(value: 'avisos', child: ListTile(leading: Icon(Ico.campana), title: Text('Avisos'))),
                const PopupMenuItem(value: 'contenedores', child: ListTile(leading: Icon(Ico.caja), title: Text('Contenedores'))),
                const PopupMenuItem(value: 'pendientes', child: ListTile(leading: Icon(Ico.reportar), title: Text('Pendientes'))),
                const PopupMenuItem(value: 'conteos', child: ListTile(leading: Icon(Ico.conteo), title: Text('Conteos'))),
                const PopupMenuItem(value: 'inventarios', child: ListTile(leading: Icon(Ico.revisar), title: Text('Inventarios'))),
                if (s.administra) ...[
                  const PopupMenuItem(value: 'conflictos', child: ListTile(leading: Icon(Ico.problemaSincronia), title: Text('Conflictos sin conexión'))),
                  const PopupMenuItem(value: 'reportes', child: ListTile(leading: Icon(Ico.reportes), title: Text('Reportes'))),
                  const PopupMenuItem(value: 'solicitudes', child: ListTile(leading: Icon(Ico.solicitudes), title: Text('Solicitudes'))),
                  const PopupMenuItem(value: 'adeudos', child: ListTile(leading: Icon(Ico.adeudos), title: Text('Adeudos'))),
                  const PopupMenuItem(value: 'etiquetas', child: ListTile(leading: Icon(Ico.qr), title: Text('Imprimir etiquetas'))),
                  const PopupMenuItem(value: 'por-revisar', child: ListTile(leading: Icon(Ico.revisar), title: Text('Por revisar'))),
                  const PopupMenuItem(
                      value: 'prestamos-abiertos', child: ListTile(leading: Icon(Ico.reloj), title: Text('Préstamos abiertos'))),
                  const PopupMenuItem(value: 'cuentas', child: ListTile(leading: Icon(Ico.cuentas), title: Text('Cuentas'))),
                ],
                if (s.rol == Rol.subadmin) ...[
                  const PopupMenuItem(value: 'bitacora', child: ListTile(leading: Icon(Ico.bitacora), title: Text('Bitácora'))),
                  const PopupMenuItem(value: 'ajustes', child: ListTile(leading: Icon(Ico.filtros), title: Text('Ajustes'))),
                ],
                const PopupMenuItem(value: 'mi-cuenta', child: ListTile(leading: Icon(Ico.persona), title: Text('Mi cuenta'))),
                const PopupMenuItem(value: 'diseno', child: ListTile(leading: Icon(Ico.diseno), title: Text('Sistema de diseño'))),
                const PopupMenuItem(value: 'salir', child: ListTile(leading: Icon(Ico.salir), title: Text('Cerrar sesión'))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  avatar: Icon(s.nivel == NivelSesion.pin ? Ico.pin : Ico.conContrasena, size: 18),
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
        Icon(Ico.foto, size: tamano * 0.35, color: colores.outline),
        if (tamano >= 56) Text('Sin foto', style: TextStyle(fontSize: 10, color: colores.outline)),
      ]),
    );
    if (ruta == null) return vacio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FotoConCopia(
        ruta: ruta!,
        url: ref.read(repositorioProvider).urlFoto(ruta!),
        miniatura: true,
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
        const Insignia('Sin clasificar: no usar', color: Avisos.sinClasificar, icono: Ico.desactivar),
      if (a.cantidadEstimada && !a.conteoDesconocido)
        const Insignia('Cantidad estimada', color: Avisos.estimado, icono: Ico.conteo),
      if (a.conteoDesconocido) const Insignia('Sin contar', color: Avisos.estimado, icono: Ico.conteo),
      if (a.pendientesAbiertos > 0)
        Insignia('${a.pendientesAbiertos} pendiente${a.pendientesAbiertos == 1 ? '' : 's'}',
            color: Avisos.pendiente, icono: Ico.reportar),
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
            Icon(Ico.sinConexion, size: 48, color: Theme.of(context).colorScheme.outline),
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

/// Foto del catálogo que también se ve sin señal: la completa si ya se abrió antes, o su miniatura guardada.
class FotoConCopia extends StatelessWidget {
  const FotoConCopia({
    super.key,
    required this.ruta,
    required this.url,
    this.miniatura = false,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.errorBuilder,
  });

  final String ruta;
  final String url;
  final bool miniatura;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final cola = ColaSinConexion.instancia;
    final copia = cola == null ? null : (miniatura ? cola.miniatura(ruta) ?? cola.fotoGrande(ruta) : cola.fotoGrande(ruta) ?? cola.miniatura(ruta));
    Widget deArchivo() => Image.file(copia!, fit: fit, width: width, height: height, cacheWidth: cacheWidth);
    if (cola != null && cola.sinSenal && copia != null) return deArchivo();
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      frameBuilder: (context, child, cuadro, _) {
        if (cuadro != null && !miniatura) cola?.guardarFotoVista(ruta, url);
        return child;
      },
      errorBuilder: (context, error, pila) => copia != null ? deArchivo() : (errorBuilder?.call(context, error, pila) ?? const SizedBox.shrink()),
    );
  }
}
