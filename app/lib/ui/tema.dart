import 'package:flutter/material.dart';

ThemeData temaClaro() {
  final colores = ColorScheme.fromSeed(seedColor: const Color(0xFF00695C), surface: const Color(0xFFF6F7F6));
  return ThemeData(
    colorScheme: colores,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: false),
    // Botones y renglones grandes: se usa en el taller, con el celular en una mano.
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 48))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48))),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    chipTheme: const ChipThemeData(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Colores de avisos que deben distinguirse de un vistazo.
abstract final class Avisos {
  static const sinClasificar = Color(0xFFB3261E);
  static const pendiente = Color(0xFF8A5A00);
  static const estimado = Color(0xFF5B5F97);
}

/// Ancho máximo del contenido en pantallas grandes (sub administración usa computadora).
const anchoContenido = 900.0;

class Centrado extends StatelessWidget {
  const Centrado({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: anchoContenido), child: child));
}
