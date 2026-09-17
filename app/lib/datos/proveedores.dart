import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acceso/sesion.dart';
import '../modelos/articulo.dart';
import '../modelos/otros.dart';
import 'repositorio.dart';

/// El catálogo completo. Son pocos cientos de renglones: se baja una vez y se filtra en el dispositivo.
final articulosProvider = FutureProvider<List<Articulo>>((ref) => ref.watch(repositorioProvider).articulos());

final articuloProvider = FutureProvider.family<Articulo?, String>((ref, id) => ref.watch(repositorioProvider).articulo(id));

final fotosProvider = FutureProvider.family<List<Foto>, String>((ref, id) => ref.watch(repositorioProvider).fotos(id));

final historialProvider =
    FutureProvider.family<List<MovimientoPublico>, String>((ref, id) => ref.watch(repositorioProvider).historial(id));

final pendientesProvider =
    FutureProvider.family<List<Pendiente>, String>((ref, id) => ref.watch(repositorioProvider).pendientes(id));

/// La sesión según el servidor. Si la jornada ya terminó, se cierra aquí mismo.
final sesionProvider = FutureProvider<Sesion?>((ref) async {
  final repo = ref.watch(repositorioProvider);
  final sesion = await repo.miSesion();
  if (repo.hayToken && (sesion == null || !sesion.vigente || !sesion.activo)) {
    await repo.salir();
    return null;
  }
  return sesion;
});

/// Préstamos vencidos: el número es público (sin nombres) para la franja del Inicio.
final vencidosProvider = FutureProvider<int>((ref) => ref.watch(repositorioProvider).vencidosContar());

/// Reportes y consumos por revisar (solo cuenta para responsable y sub administración).
final porRevisarProvider = FutureProvider<int>((ref) async {
  final sesion = await ref.watch(sesionProvider.future);
  if (sesion == null || !sesion.administra) return 0;
  return ref.watch(repositorioProvider).porRevisarContar();
});

/// Solicitudes por revisar y por entregar (responsable y sub administración).
final solicitudesContarProvider = FutureProvider<int>((ref) async {
  final sesion = await ref.watch(sesionProvider.future);
  if (sesion == null || !sesion.administra) return 0;
  final c = await ref.watch(repositorioProvider).solicitudesContar();
  return c.porRevisar + c.porEntregar;
});

/// Avisos sin leer de la cuenta con sesión (la campana).
final avisosSinLeerProvider = FutureProvider<int>((ref) async {
  final sesion = await ref.watch(sesionProvider.future);
  if (sesion == null) return 0;
  return ref.watch(repositorioProvider).avisosSinLeer();
});

/// Configuración pública (plazos, hora de fin de jornada, dominio de correo).
final configuracionProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(repositorioProvider).configuracion());

/// Después de cambiar algo de un artículo, se vuelve a leer todo lo que lo muestra.
void refrescarArticulo(WidgetRef ref, String id) => refrescarArticuloEn(ref.container, id);

void refrescarArticuloEn(ProviderContainer c, String id) {
  c.invalidate(articulosProvider);
  c.invalidate(articuloProvider(id));
  c.invalidate(fotosProvider(id));
  c.invalidate(historialProvider(id));
  c.invalidate(pendientesProvider(id));
  c.invalidate(vencidosProvider);
  c.invalidate(porRevisarProvider);
  c.invalidate(solicitudesContarProvider);
  c.invalidate(avisosSinLeerProvider);
}
