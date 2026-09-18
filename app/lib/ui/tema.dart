import 'package:flutter/material.dart';

import 'diseno/tema.dart';

export 'diseno/tokens.dart' show TmColores, TmContexto, Espacio, Redondeo, Sombra, Duracion, Quiebre;

/// Tema claro y oscuro del sistema "Taller Maker" (Fase 7).
ThemeData temaClaro() => temaTallerMaker(Brightness.light);
ThemeData temaOscuro() => temaTallerMaker(Brightness.dark);

/// Colores de avisos que deben distinguirse de un vistazo (se conservan de fases
/// anteriores y ahora salen de los tokens).
abstract final class Avisos {
  static const sinClasificar = Color(0xFFB91C1C);
  static const pendiente = Color(0xFF9A5B00);
  static const estimado = Color(0xFF0B63D6);
}

/// Ancho máximo del contenido en pantallas grandes.
const anchoContenido = 1100.0;

class Centrado extends StatelessWidget {
  const Centrado({super.key, required this.child, this.ancho = anchoContenido});

  final Widget child;
  final double ancho;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: child));
}
