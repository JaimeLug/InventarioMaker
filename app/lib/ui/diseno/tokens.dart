import 'package:flutter/material.dart';

import '../../modelos/catalogos.dart';

/// Los valores del sistema de diseño "Taller Maker" (Fase 7).
///
/// Ninguna pantalla escribe un color, un tamaño o un radio a mano: todo sale de aquí.
/// Se usa con `context.tm` (colores del tema activo), `Espacio`, `Radio`, `Sombra` y `Duracion`.
@immutable
class TmColores {
  const TmColores({
    required this.primario,
    required this.primarioEncima,
    required this.primarioPresionado,
    required this.sobrePrimario,
    required this.primarioSuave,
    required this.primarioTexto,
    required this.secundario,
    required this.secundarioEncima,
    required this.sobreSecundario,
    required this.acento,
    required this.acentoSuave,
    required this.fondo,
    required this.superficie,
    required this.superficie2,
    required this.superficieHundida,
    required this.superficieElevada,
    required this.nav,
    required this.nav2,
    required this.navTexto,
    required this.navTextoFuerte,
    required this.texto,
    required this.textoSecundario,
    required this.textoTenue,
    required this.textoDeshabilitado,
    required this.borde,
    required this.bordeFuerte,
    required this.foco,
    required this.exito,
    required this.exitoSuave,
    required this.exitoRelleno,
    required this.aviso,
    required this.avisoSuave,
    required this.avisoRelleno,
    required this.error,
    required this.errorSuave,
    required this.errorRelleno,
    required this.info,
    required this.infoSuave,
    required this.infoRelleno,
    required this.neutroRelleno,
    required this.categorias,
    required this.graficas,
    required this.rejillaGrafica,
  });

  // Marca y acción
  final Color primario, primarioEncima, primarioPresionado, sobrePrimario, primarioSuave, primarioTexto;
  final Color secundario, secundarioEncima, sobreSecundario;
  final Color acento, acentoSuave;
  // Superficies
  final Color fondo, superficie, superficie2, superficieHundida, superficieElevada;
  final Color nav, nav2, navTexto, navTextoFuerte;
  // Texto y bordes
  final Color texto, textoSecundario, textoTenue, textoDeshabilitado, borde, bordeFuerte, foco;
  // Estados: base (texto e iconos), suave (fondo) y relleno (barras)
  final Color exito, exitoSuave, exitoRelleno;
  final Color aviso, avisoSuave, avisoRelleno;
  final Color error, errorSuave, errorRelleno;
  final Color info, infoSuave, infoRelleno;
  final Color neutroRelleno;
  /// Solo para franjas, puntos e iconos: el nombre de la categoría siempre se escribe.
  final Map<Categoria, Color> categorias;
  final List<Color> graficas;
  final Color rejillaGrafica;

  Color deCategoria(Categoria c) => categorias[c] ?? neutroRelleno;

  static const claro = TmColores(
    primario: Color(0xFFC8102E),
    primarioEncima: Color(0xFFA50D26),
    primarioPresionado: Color(0xFF870A1F),
    sobrePrimario: Color(0xFFFFFFFF),
    primarioSuave: Color(0xFFFBE9EC),
    primarioTexto: Color(0xFFB00E28),
    secundario: Color(0xFF2A2E35),
    secundarioEncima: Color(0xFF3A3F48),
    sobreSecundario: Color(0xFFFFFFFF),
    acento: Color(0xFF0B63D6),
    acentoSuave: Color(0xFFE4EEFC),
    fondo: Color(0xFFEEF0F3),
    superficie: Color(0xFFFFFFFF),
    superficie2: Color(0xFFF5F6F8),
    superficieHundida: Color(0xFFE4E7EB),
    superficieElevada: Color(0xFFFFFFFF),
    nav: Color(0xFF15171B),
    nav2: Color(0xFF1F2228),
    navTexto: Color(0xFFC9CED6),
    navTextoFuerte: Color(0xFFFFFFFF),
    texto: Color(0xFF14171B),
    textoSecundario: Color(0xFF4A515B),
    textoTenue: Color(0xFF666E79),
    textoDeshabilitado: Color(0xFF9AA1AB),
    borde: Color(0xFFD6DAE0),
    bordeFuerte: Color(0xFFAEB5BF),
    foco: Color(0xFF0B63D6),
    exito: Color(0xFF127A3E),
    exitoSuave: Color(0xFFE2F3E8),
    exitoRelleno: Color(0xFF1E9E55),
    aviso: Color(0xFF9A5B00),
    avisoSuave: Color(0xFFFFF3D1),
    avisoRelleno: Color(0xFFFFB400),
    error: Color(0xFF9B1C1C),
    errorSuave: Color(0xFFFBE6E6),
    errorRelleno: Color(0xFFB91C1C),
    info: Color(0xFF0B63D6),
    infoSuave: Color(0xFFE4EEFC),
    infoRelleno: Color(0xFF2F7CE8),
    neutroRelleno: Color(0xFF8A919B),
    categorias: {
      Categoria.vex: Color(0xFFC8102E),
      Categoria.ftc: Color(0xFFE0600C),
      Categoria.herramientas: Color(0xFFC28A00),
      Categoria.herramientasElectricas: Color(0xFF0B63D6),
      Categoria.consumibles: Color(0xFF0E8A7E),
      Categoria.comun: Color(0xFF5F6773),
      Categoria.sinClasificar: Color(0xFF8A919B),
    },
    graficas: [Color(0xFF2A2E35), Color(0xFF0B63D6), Color(0xFFE0600C), Color(0xFF0E8A7E), Color(0xFFC28A00)],
    rejillaGrafica: Color(0xFFE1E4E8),
  );

  static const oscuro = TmColores(
    primario: Color(0xFFD91F36),
    primarioEncima: Color(0xFFEC3A50),
    primarioPresionado: Color(0xFFB8182D),
    sobrePrimario: Color(0xFFFFFFFF),
    primarioSuave: Color(0xFF3A1419),
    primarioTexto: Color(0xFFFF7A88),
    secundario: Color(0xFFE6E8EC),
    secundarioEncima: Color(0xFFFFFFFF),
    sobreSecundario: Color(0xFF15171B),
    acento: Color(0xFF5AA2FF),
    acentoSuave: Color(0xFF132741),
    fondo: Color(0xFF0D0F12),
    superficie: Color(0xFF15181D),
    superficie2: Color(0xFF1B1F25),
    superficieHundida: Color(0xFF101216),
    superficieElevada: Color(0xFF20252C),
    nav: Color(0xFF08090B),
    nav2: Color(0xFF15181D),
    navTexto: Color(0xFFA9B0BA),
    navTextoFuerte: Color(0xFFFFFFFF),
    texto: Color(0xFFECEEF1),
    textoSecundario: Color(0xFFB5BBC4),
    textoTenue: Color(0xFF8F96A0),
    textoDeshabilitado: Color(0xFF5C636D),
    borde: Color(0xFF2A2F37),
    bordeFuerte: Color(0xFF555E6A),
    foco: Color(0xFF5AA2FF),
    exito: Color(0xFF4ED688),
    exitoSuave: Color(0xFF10291B),
    exitoRelleno: Color(0xFF2FB36A),
    aviso: Color(0xFFFFC24A),
    avisoSuave: Color(0xFF2E2208),
    avisoRelleno: Color(0xFFFFB400),
    error: Color(0xFFFF7B7B),
    errorSuave: Color(0xFF331416),
    errorRelleno: Color(0xFFE04848),
    info: Color(0xFF5AA2FF),
    infoSuave: Color(0xFF132741),
    infoRelleno: Color(0xFF3D8BF0),
    neutroRelleno: Color(0xFF6B727C),
    categorias: {
      Categoria.vex: Color(0xFFFF4A5E),
      Categoria.ftc: Color(0xFFFF8A3D),
      Categoria.herramientas: Color(0xFFFFC24A),
      Categoria.herramientasElectricas: Color(0xFF5AA2FF),
      Categoria.consumibles: Color(0xFF3FD0BF),
      Categoria.comun: Color(0xFF9AA2AD),
      Categoria.sinClasificar: Color(0xFF6B727C),
    },
    graficas: [Color(0xFFE6E8EC), Color(0xFF5AA2FF), Color(0xFFFF8A3D), Color(0xFF3FD0BF), Color(0xFFFFC24A)],
    rejillaGrafica: Color(0xFF2A2F37),
  );
}

/// Envoltura para que los colores viajen dentro del tema de Flutter.
@immutable
class TmTema extends ThemeExtension<TmTema> {
  const TmTema(this.colores);

  final TmColores colores;

  @override
  TmTema copyWith({TmColores? colores}) => TmTema(colores ?? this.colores);

  /// Los dos juegos de color se cambian de golpe (no se mezclan a medias: los colores
  /// de estado deben verse exactos, no a la mitad entre claro y oscuro).
  @override
  TmTema lerp(ThemeExtension<TmTema>? otro, double t) =>
      t < 0.5 || otro is! TmTema ? this : otro;
}

extension TmContexto on BuildContext {
  /// Los colores del tema activo: `context.tm.primario`.
  TmColores get tm => Theme.of(this).extension<TmTema>()?.colores ?? TmColores.claro;
}

/// Espacio en múltiplos de 4: dentro de un componente 4–12, entre componentes 16, entre secciones 24.
abstract final class Espacio {
  static const x1 = 4.0, x2 = 8.0, x3 = 12.0, x4 = 16.0, x5 = 20.0, x6 = 24.0, x8 = 32.0, x10 = 40.0, x12 = 48.0;
}

abstract final class Redondeo {
  static const xs = 3.0, sm = 6.0, md = 8.0, lg = 12.0, pastilla = 999.0;
  static const rXs2 = BorderRadius.all(Radius.circular(xs));
  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rPastilla = BorderRadius.all(Radius.circular(pastilla));
}

abstract final class Sombra {
  /// Tarjetas en reposo.
  static List<BoxShadow> uno(Brightness b) => b == Brightness.dark
      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(0, 1))]
      : const [BoxShadow(color: Color(0x0F14171B), blurRadius: 2, offset: Offset(0, 1))];

  /// Encima, menús y barras fijas.
  static List<BoxShadow> dos(Brightness b) => b == Brightness.dark
      ? const [BoxShadow(color: Color(0x73000000), blurRadius: 16, offset: Offset(0, 6))]
      : const [BoxShadow(color: Color(0x1514171B), blurRadius: 12, offset: Offset(0, 4))];

  /// Modales y avisos flotantes.
  static List<BoxShadow> tres(Brightness b) => b == Brightness.dark
      ? const [BoxShadow(color: Color(0x99000000), blurRadius: 48, offset: Offset(0, 20))]
      : const [BoxShadow(color: Color(0x2914171B), blurRadius: 40, offset: Offset(0, 16))];
}

abstract final class Duracion {
  /// Encima y presionado.
  static const rapida = Duration(milliseconds: 120);

  /// Aparecer menús, modales y avisos.
  static const base = Duration(milliseconds: 180);
  static const curva = Cubic(.2, .7, .2, 1);
}

/// Anchos a partir de los cuales cambia el acomodo (mismos del prototipo).
abstract final class Quiebre {
  /// Barra lateral completa.
  static const lateral = 1240.0;

  /// Rieles de iconos.
  static const rieles = 1000.0;

  /// Debajo de esto: barra inferior, tarjetas en vez de tabla y formularios de una columna.
  static const compacto = 760.0;

  /// Toque mínimo cómodo (con guantes, en el taller).
  static const toque = 44.0;
}
