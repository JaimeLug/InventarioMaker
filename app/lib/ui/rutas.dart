import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pantallas/articulo_form_pantalla.dart';
import 'pantallas/bitacora_pantalla.dart';
import 'pantallas/codigo_pantalla.dart';
import 'pantallas/cuentas_pantalla.dart';
import 'pantallas/devolucion_pantalla.dart';
import 'pantallas/ficha_pantalla.dart';
import 'pantallas/inicio_pantalla.dart';
import 'pantallas/mi_cuenta_pantalla.dart';
import 'pantallas/prestamo_pantalla.dart';
import 'pantallas/prestamos_pantallas.dart';
import 'pantallas/reporte_pantalla.dart';
import 'pantallas/revision_pantallas.dart';

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
      GoRoute(path: '/mis-prestamos', builder: (_, _) => const MisPrestamosPantalla()),
      GoRoute(path: '/mis-reportes', builder: (_, _) => const MisReportesPantalla()),
      GoRoute(path: '/por-revisar', builder: (_, _) => const PorRevisarPantalla()),
      GoRoute(path: '/prestamos-abiertos', builder: (_, _) => const PrestamosAbiertosPantalla()),
      GoRoute(path: '/bitacora', builder: (_, _) => const BitacoraPantalla()),
      // Los QR de las etiquetas llevan esta dirección (Fase 4): /q/A-0101 o /q/C-0012
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
