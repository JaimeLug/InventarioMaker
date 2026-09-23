import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'diseno/tokens.dart';
import 'pantallas/adeudos_pantallas.dart';
import 'pantallas/articulo_form_pantalla.dart';
import 'pantallas/avisos_ajustes_pantallas.dart';
import 'pantallas/bitacora_pantalla.dart';
import 'pantallas/codigo_pantalla.dart';
import 'pantallas/contenedores_pantallas.dart';
import 'pantallas/desglose_pantalla.dart';
import 'pantallas/inventario_pantallas.dart';
import 'pantallas/pendientes_pantallas.dart';
import 'pantallas/escanear_pantalla.dart';
import 'pantallas/etiquetas_pantalla.dart';
import 'pantallas/cuentas_pantalla.dart';
import 'pantallas/diseno_pantalla.dart';
import 'pantallas/devolucion_pantalla.dart';
import 'pantallas/ficha_pantalla.dart';
import 'pantallas/herramientas_pantalla.dart';
import 'pantallas/inventario_pantalla.dart';
import 'pantallas/tablero_pantalla.dart';
import 'pantallas/mi_cuenta_pantalla.dart';
import 'pantallas/prestamo_pantalla.dart';
import 'pantallas/prestamos_pantallas.dart';
import 'pantallas/reporte_pantalla.dart';
import 'pantallas/propuestas_pantallas.dart';
import 'pantallas/reportes_pantallas.dart';
import 'pantallas/sin_conexion_pantallas.dart';
import 'pantallas/revision_pantallas.dart';
import 'pantallas/solicitud_publica_pantallas.dart';
import 'pantallas/solicitudes_pantallas.dart';
import 'pantallas/mis_solicitudes_sel_pantalla.dart';

/// Todas las pantallas entran con la misma transición corta: se desvanecen y suben un poco.
/// Rápida a propósito: en el taller se navega con una mano y con prisa.
CustomTransitionPage<void> _pagina(Widget pantalla) => CustomTransitionPage<void>(
      child: pantalla,
      transitionDuration: const Duration(milliseconds: 170),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (context, animacion, _, hijo) {
        final suave = CurvedAnimation(parent: animacion, curve: Duracion.curva);
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return hijo;
        return FadeTransition(
          opacity: suave,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, .015), end: Offset.zero).animate(suave),
            child: hijo,
          ),
        );
      },
    );

final rutasProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', pageBuilder: (_, _) => _pagina(const TableroPantalla())),
      GoRoute(
        path: '/inventario',
        pageBuilder: (_, e) => _pagina(InventarioPantalla(
          filtroInicial: e.uri.queryParameters['filtro'],
          categoriaInicial: e.uri.queryParameters['categoria'],
        )),
      ),
      GoRoute(path: '/herramientas', pageBuilder: (_, _) => _pagina(const HerramientasPantalla())),
      GoRoute(path: '/articulo/nuevo', pageBuilder: (_, _) => _pagina(const ArticuloFormPantalla())),
      GoRoute(path: '/articulo/:id', pageBuilder: (_, e) => _pagina(FichaPantalla(id: e.pathParameters['id']!))),
      GoRoute(path: '/articulo/:id/editar', pageBuilder: (_, e) => _pagina(ArticuloFormPantalla(id: e.pathParameters['id']))),
      GoRoute(path: '/articulo/:id/prestar', pageBuilder: (_, e) => _pagina(PrestamoPantalla(articuloId: e.pathParameters['id']!))),
      GoRoute(path: '/articulo/:id/devolver', pageBuilder: (_, e) => _pagina(DevolucionPantalla(articuloId: e.pathParameters['id']!))),
      GoRoute(path: '/articulo/:id/reportar', pageBuilder: (_, e) => _pagina(ReportePantalla(articuloId: e.pathParameters['id']!))),
      GoRoute(
        path: '/prestar',
        pageBuilder: (_, e) => _pagina(PrestamoPantalla(lineas: {
          for (final par in (e.uri.queryParameters['lineas'] ?? '').split(',').where((x) => x.contains(':')))
            par.split(':').first: int.tryParse(par.split(':').last) ?? 1,
        })),
      ),
      // Fase 4a: contenedores, escaneo y etiquetas
      GoRoute(path: '/contenedores', pageBuilder: (_, _) => _pagina(const ContenedoresPantalla())),
      GoRoute(path: '/contenedores/nuevo', pageBuilder: (_, e) => _pagina(ContenedorFormPantalla(padreId: e.uri.queryParameters['padre']))),
      GoRoute(path: '/contenedor/:codigo', pageBuilder: (_, e) => _pagina(ContenedorPantalla(codigo: e.pathParameters['codigo']!.toUpperCase()))),
      GoRoute(path: '/contenedor/:codigo/editar', pageBuilder: (_, e) => _pagina(ContenedorFormPantalla(codigo: e.pathParameters['codigo']!.toUpperCase()))),
      GoRoute(path: '/contenedor/:codigo/devolver', pageBuilder: (_, e) => _pagina(DevolverVariosPantalla(codigo: e.pathParameters['codigo']!.toUpperCase()))),
      GoRoute(path: '/escanear', pageBuilder: (_, e) => _pagina(EscanearPantalla(devolver: e.uri.queryParameters['devolver'] == '1'))),
      // Fase 4b: pendientes, conteos, desglose e inventario periódico
      GoRoute(path: '/pendientes', pageBuilder: (_, _) => _pagina(const PendientesPantalla())),
      GoRoute(path: '/conteos', pageBuilder: (_, _) => _pagina(const ConteosPantalla())),
      GoRoute(path: '/desglose/:id', pageBuilder: (_, e) => _pagina(DesglosePantalla(articuloId: e.pathParameters['id']!))),
      GoRoute(path: '/inventarios', pageBuilder: (_, _) => _pagina(const InventariosPantalla())),
      GoRoute(path: '/inventario/:id', pageBuilder: (_, e) => _pagina(InventarioPeriodicoPantalla(id: e.pathParameters['id']!))),
      GoRoute(
        path: '/etiquetas',
        pageBuilder: (_, e) => _pagina(EtiquetasPantalla(codigos: (e.uri.queryParameters['codigos'] ?? '').split(',').where((c) => c.isNotEmpty).toList())),
      ),
      // Fase 5: reportes y actas
      GoRoute(path: '/reportes', pageBuilder: (_, _) => _pagina(const ReportesPantalla())),
      GoRoute(path: '/consulta-rapida', pageBuilder: (_, _) => _pagina(const ConsultaRapidaPantalla())),
      GoRoute(path: '/revisiones-kit', pageBuilder: (_, _) => _pagina(const RevisionesKitPantalla())),
      GoRoute(path: '/revision-kit/:id', pageBuilder: (_, e) => _pagina(RevisionKitPantalla(id: e.pathParameters['id']!))),
      GoRoute(path: '/acta-inventario/:id', pageBuilder: (_, e) => _pagina(ActaInventarioPantalla(id: e.pathParameters['id']!))),
      GoRoute(path: '/acta-entrega', pageBuilder: (_, _) => _pagina(const ActaEntregaPantalla())),
      // Fase 6: sin conexión
      GoRoute(path: '/sin-conexion', pageBuilder: (_, _) => _pagina(const SinConexionPantalla())),
      GoRoute(path: '/conflictos', pageBuilder: (_, _) => _pagina(const ConflictosPantalla())),
      GoRoute(path: '/mis-prestamos', pageBuilder: (_, _) => _pagina(const MisPrestamosPantalla())),
      GoRoute(path: '/mis-reportes', pageBuilder: (_, _) => _pagina(const MisReportesPantalla())),
      GoRoute(path: '/por-revisar', pageBuilder: (_, _) => _pagina(const PorRevisarPantalla())),
      GoRoute(path: '/propuestas', pageBuilder: (_, _) => _pagina(const PropuestasPantalla())),
      GoRoute(path: '/prestamos-abiertos', pageBuilder: (_, _) => _pagina(const PrestamosAbiertosPantalla())),
      GoRoute(path: '/bitacora', pageBuilder: (_, _) => _pagina(const BitacoraPantalla())),
      // Sin cuenta (Fase 3b). /s/<enlace> es la dirección que llega por correo.
      GoRoute(path: '/solicitud', pageBuilder: (_, _) => _pagina(const SolicitudPantalla())),
      GoRoute(path: '/s/:token', pageBuilder: (_, e) => _pagina(EstadoSolicitudPantalla(token: e.pathParameters['token']!))),
      GoRoute(path: '/mis-solicitudes', pageBuilder: (_, _) => _pagina(const MisSolicitudesPantalla())),
      GoRoute(path: '/mis-solicitudes-sel', pageBuilder: (_, _) => _pagina(const MisSolicitudesSelPantalla())),
      // Responsable y sub administración
      GoRoute(path: '/solicitudes', pageBuilder: (_, _) => _pagina(const BandejaPantalla())),
      GoRoute(path: '/solicitudes/:id', pageBuilder: (_, e) => _pagina(SolicitudDetallePantalla(id: e.pathParameters['id']!))),
      GoRoute(path: '/solicitudes/:id/entrega', pageBuilder: (_, e) => _pagina(EntregaPantalla(id: e.pathParameters['id']!))),
      GoRoute(path: '/adeudos', pageBuilder: (_, _) => _pagina(const AdeudosPantalla())),
      GoRoute(path: '/persona/:tipo/:id', pageBuilder: (_, e) => _pagina(PersonaPantalla(tipo: e.pathParameters['tipo']!, id: e.pathParameters['id']!))),
      GoRoute(path: '/expediente/:id', pageBuilder: (_, e) => _pagina(ExpedientePantalla(prestamoId: e.pathParameters['id']!))),
      GoRoute(path: '/avisos', pageBuilder: (_, _) => _pagina(const AvisosPantalla())),
      GoRoute(path: '/ajustes', pageBuilder: (_, _) => _pagina(const AjustesPantalla())),
      // Los QR de las etiquetas llevan esta dirección: /q/A-0101 o /q/C-0012
      GoRoute(path: '/q/:codigo', pageBuilder: (_, e) => _pagina(CodigoPantalla(codigo: e.pathParameters['codigo']!))),
      GoRoute(path: '/cuentas', pageBuilder: (_, _) => _pagina(const CuentasPantalla())),
      GoRoute(path: '/diseno', pageBuilder: (_, _) => _pagina(const DisenoPantalla())),
      GoRoute(path: '/mi-cuenta', pageBuilder: (_, _) => _pagina(const MiCuentaPantalla())),
    ],
    errorBuilder: (context, _) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Esa página no existe.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => context.go('/'), child: const Text('Ir al inventario')),
        ]),
      ),
    ),
  );
});
