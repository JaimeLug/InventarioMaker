import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'pantallas/devolucion_pantalla.dart';
import 'pantallas/ficha_pantalla.dart';
import 'pantallas/inicio_pantalla.dart';
import 'pantallas/mi_cuenta_pantalla.dart';
import 'pantallas/prestamo_pantalla.dart';
import 'pantallas/prestamos_pantallas.dart';
import 'pantallas/reporte_pantalla.dart';
import 'pantallas/reportes_pantallas.dart';
import 'pantallas/revision_pantallas.dart';
import 'pantallas/solicitud_publica_pantallas.dart';
import 'pantallas/solicitudes_pantallas.dart';

final rutasProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const InicioPantalla()),
      GoRoute(path: '/articulo/nuevo', builder: (_, _) => const ArticuloFormPantalla()),
      GoRoute(path: '/articulo/:id', builder: (_, e) => FichaPantalla(id: e.pathParameters['id']!)),
      GoRoute(path: '/articulo/:id/editar', builder: (_, e) => ArticuloFormPantalla(id: e.pathParameters['id'])),
      GoRoute(path: '/articulo/:id/prestar', builder: (_, e) => PrestamoPantalla(articuloId: e.pathParameters['id']!)),
      GoRoute(path: '/articulo/:id/devolver', builder: (_, e) => DevolucionPantalla(articuloId: e.pathParameters['id']!)),
      GoRoute(path: '/articulo/:id/reportar', builder: (_, e) => ReportePantalla(articuloId: e.pathParameters['id']!)),
      GoRoute(
        path: '/prestar',
        builder: (_, e) => PrestamoPantalla(lineas: {
          for (final par in (e.uri.queryParameters['lineas'] ?? '').split(',').where((x) => x.contains(':')))
            par.split(':').first: int.tryParse(par.split(':').last) ?? 1,
        }),
      ),
      // Fase 4a: contenedores, escaneo y etiquetas
      GoRoute(path: '/contenedores', builder: (_, _) => const ContenedoresPantalla()),
      GoRoute(path: '/contenedores/nuevo', builder: (_, e) => ContenedorFormPantalla(padreId: e.uri.queryParameters['padre'])),
      GoRoute(path: '/contenedor/:codigo', builder: (_, e) => ContenedorPantalla(codigo: e.pathParameters['codigo']!.toUpperCase())),
      GoRoute(path: '/contenedor/:codigo/editar', builder: (_, e) => ContenedorFormPantalla(codigo: e.pathParameters['codigo']!.toUpperCase())),
      GoRoute(path: '/contenedor/:codigo/devolver', builder: (_, e) => DevolverVariosPantalla(codigo: e.pathParameters['codigo']!.toUpperCase())),
      GoRoute(path: '/escanear', builder: (_, e) => EscanearPantalla(devolver: e.uri.queryParameters['devolver'] == '1')),
      // Fase 4b: pendientes, conteos, desglose e inventario periódico
      GoRoute(path: '/pendientes', builder: (_, _) => const PendientesPantalla()),
      GoRoute(path: '/conteos', builder: (_, _) => const ConteosPantalla()),
      GoRoute(path: '/desglose/:id', builder: (_, e) => DesglosePantalla(articuloId: e.pathParameters['id']!)),
      GoRoute(path: '/inventarios', builder: (_, _) => const InventariosPantalla()),
      GoRoute(path: '/inventario/:id', builder: (_, e) => InventarioPantalla(id: e.pathParameters['id']!)),
      GoRoute(
        path: '/etiquetas',
        builder: (_, e) => EtiquetasPantalla(codigos: (e.uri.queryParameters['codigos'] ?? '').split(',').where((c) => c.isNotEmpty).toList()),
      ),
      // Fase 5: reportes y actas
      GoRoute(path: '/reportes', builder: (_, _) => const ReportesPantalla()),
      GoRoute(path: '/consulta-rapida', builder: (_, _) => const ConsultaRapidaPantalla()),
      GoRoute(path: '/revisiones-kit', builder: (_, _) => const RevisionesKitPantalla()),
      GoRoute(path: '/revision-kit/:id', builder: (_, e) => RevisionKitPantalla(id: e.pathParameters['id']!)),
      GoRoute(path: '/acta-inventario/:id', builder: (_, e) => ActaInventarioPantalla(id: e.pathParameters['id']!)),
      GoRoute(path: '/acta-entrega', builder: (_, _) => const ActaEntregaPantalla()),
      GoRoute(path: '/mis-prestamos', builder: (_, _) => const MisPrestamosPantalla()),
      GoRoute(path: '/mis-reportes', builder: (_, _) => const MisReportesPantalla()),
      GoRoute(path: '/por-revisar', builder: (_, _) => const PorRevisarPantalla()),
      GoRoute(path: '/prestamos-abiertos', builder: (_, _) => const PrestamosAbiertosPantalla()),
      GoRoute(path: '/bitacora', builder: (_, _) => const BitacoraPantalla()),
      // Sin cuenta (Fase 3b). /s/<enlace> es la dirección que llega por correo.
      GoRoute(path: '/solicitud', builder: (_, _) => const SolicitudPantalla()),
      GoRoute(path: '/s/:token', builder: (_, e) => EstadoSolicitudPantalla(token: e.pathParameters['token']!)),
      GoRoute(path: '/mis-solicitudes', builder: (_, _) => const MisSolicitudesPantalla()),
      // Responsable y sub administración
      GoRoute(path: '/solicitudes', builder: (_, _) => const BandejaPantalla()),
      GoRoute(path: '/solicitudes/:id', builder: (_, e) => SolicitudDetallePantalla(id: e.pathParameters['id']!)),
      GoRoute(path: '/solicitudes/:id/entrega', builder: (_, e) => EntregaPantalla(id: e.pathParameters['id']!)),
      GoRoute(path: '/adeudos', builder: (_, _) => const AdeudosPantalla()),
      GoRoute(path: '/persona/:tipo/:id', builder: (_, e) => PersonaPantalla(tipo: e.pathParameters['tipo']!, id: e.pathParameters['id']!)),
      GoRoute(path: '/expediente/:id', builder: (_, e) => ExpedientePantalla(prestamoId: e.pathParameters['id']!)),
      GoRoute(path: '/avisos', builder: (_, _) => const AvisosPantalla()),
      GoRoute(path: '/ajustes', builder: (_, _) => const AjustesPantalla()),
      // Los QR de las etiquetas llevan esta dirección: /q/A-0101 o /q/C-0012
      GoRoute(path: '/q/:codigo', builder: (_, e) => CodigoPantalla(codigo: e.pathParameters['codigo']!)),
      GoRoute(path: '/cuentas', builder: (_, _) => const CuentasPantalla()),
      GoRoute(path: '/mi-cuenta', builder: (_, _) => const MiCuentaPantalla()),
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
