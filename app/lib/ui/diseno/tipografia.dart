import 'package:flutter/material.dart';

/// Tres familias, empacadas en la app para que se vean igual sin conexión:
/// Barlow (interfaz), Barlow Condensed (títulos técnicos) e IBM Plex Mono (códigos y cifras).
abstract final class Fuente {
  static const ui = 'Barlow';
  static const tecnica = 'BarlowCondensed';
  static const mono = 'IBMPlexMono';
}

/// Cifras que se alinean en columnas y cero con barra.
const cifrasTabulares = [FontFeature.tabularFigures()];

abstract final class Tipografia {
  /// Título de página: condensada, mayúsculas.
  static const display = TextStyle(fontFamily: Fuente.tecnica, fontSize: 32, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: .6);
  static const displayChico = TextStyle(fontFamily: Fuente.tecnica, fontSize: 26, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: .5);
  static const h1 = TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontSize: 20, height: 1.2, fontWeight: FontWeight.w700);
  static const h3 = TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w700);
  static const cuerpo = TextStyle(fontSize: 16, height: 1.45);
  static const cuerpoFuerte = TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w600);
  static const chico = TextStyle(fontSize: 14, height: 1.4);
  static const chicoFuerte = TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600);

  /// Etiquetas en mayúsculas sobre cifras y campos.
  static const etiqueta =
      TextStyle(fontFamily: Fuente.tecnica, fontSize: 12, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 1.2);

  /// Cifra grande de tablero y ficha.
  static const cifra =
      TextStyle(fontFamily: Fuente.mono, fontSize: 30, height: 1, fontWeight: FontWeight.w600, fontFeatures: cifrasTabulares, letterSpacing: -.8);
  static const cifraChica =
      TextStyle(fontFamily: Fuente.mono, fontSize: 20, height: 1.1, fontWeight: FontWeight.w600, fontFeatures: cifrasTabulares);

  /// Código de etiqueta, número de serie, resguardo.
  static const codigo = TextStyle(fontFamily: Fuente.mono, fontSize: 13.5, height: 1.35, fontFeatures: cifrasTabulares);
  static const codigoFuerte =
      TextStyle(fontFamily: Fuente.mono, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, fontFeatures: cifrasTabulares);
  static const boton = TextStyle(fontSize: 16, height: 1.2, fontWeight: FontWeight.w600);
}

/// El tema de texto de Material armado con la escala de arriba.
TextTheme temaDeTexto(Color texto, Color secundario) => TextTheme(
      displaySmall: Tipografia.display.copyWith(color: texto),
      headlineMedium: Tipografia.h1.copyWith(color: texto),
      headlineSmall: Tipografia.h2.copyWith(color: texto),
      titleLarge: Tipografia.h2.copyWith(color: texto),
      titleMedium: Tipografia.h3.copyWith(color: texto),
      titleSmall: Tipografia.chicoFuerte.copyWith(color: texto),
      bodyLarge: Tipografia.cuerpo.copyWith(color: texto),
      bodyMedium: Tipografia.cuerpo.copyWith(color: texto),
      bodySmall: Tipografia.chico.copyWith(color: secundario),
      labelLarge: Tipografia.boton.copyWith(color: texto),
      labelMedium: Tipografia.chicoFuerte.copyWith(color: secundario),
      labelSmall: Tipografia.etiqueta.copyWith(color: secundario),
    );
