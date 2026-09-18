import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tipografia.dart';
import 'tokens.dart';

/// El tema de Material armado con los tokens. Ninguna pantalla define colores por su cuenta.
ThemeData temaTallerMaker(Brightness brillo) {
  final c = brillo == Brightness.dark ? TmColores.oscuro : TmColores.claro;
  final texto = temaDeTexto(c.texto, c.textoSecundario);
  final esquema = ColorScheme(
    brightness: brillo,
    primary: c.primario,
    onPrimary: c.sobrePrimario,
    primaryContainer: c.primarioSuave,
    onPrimaryContainer: c.primarioTexto,
    secondary: c.secundario,
    onSecondary: c.sobreSecundario,
    secondaryContainer: c.superficieHundida,
    onSecondaryContainer: c.texto,
    tertiary: c.acento,
    onTertiary: c.sobrePrimario,
    tertiaryContainer: c.acentoSuave,
    onTertiaryContainer: c.acento,
    error: c.errorRelleno,
    onError: Colors.white,
    errorContainer: c.errorSuave,
    onErrorContainer: c.error,
    surface: c.superficie,
    onSurface: c.texto,
    surfaceContainerLowest: c.superficieHundida,
    surfaceContainerLow: c.superficie2,
    surfaceContainer: c.superficie,
    surfaceContainerHigh: c.superficie2,
    surfaceContainerHighest: c.superficieHundida,
    onSurfaceVariant: c.textoSecundario,
    outline: c.bordeFuerte,
    outlineVariant: c.borde,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xCC0A0C0F),
    inverseSurface: c.nav,
    onInverseSurface: c.navTextoFuerte,
    inversePrimary: c.primarioTexto,
  );

  OutlineInputBorder borde(Color color, [double ancho = 1]) =>
      OutlineInputBorder(borderRadius: Redondeo.rSm, borderSide: BorderSide(color: color, width: ancho));

  ButtonStyle base(Color fondo, Color encima, Color contenido) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, Quiebre.toque)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Espacio.x4)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Redondeo.rSm)),
        textStyle: const WidgetStatePropertyAll(Tipografia.boton),
        iconSize: const WidgetStatePropertyAll(20),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.disabled)
            ? c.superficieHundida
            : e.contains(WidgetState.hovered) || e.contains(WidgetState.pressed)
                ? encima
                : fondo),
        foregroundColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.disabled) ? c.textoDeshabilitado : contenido),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brillo,
    colorScheme: esquema,
    scaffoldBackgroundColor: c.fondo,
    canvasColor: c.superficie,
    dividerColor: c.borde,
    fontFamily: Fuente.ui,
    textTheme: texto,
    primaryTextTheme: texto,
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    extensions: [TmTema(c)],
    iconTheme: IconThemeData(color: c.textoSecundario, size: 20),
    primaryIconTheme: IconThemeData(color: c.texto, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: c.fondo,
      foregroundColor: c.texto,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Tipografia.h2.copyWith(color: c.texto, fontFamily: Fuente.ui),
      iconTheme: IconThemeData(color: c.textoSecundario, size: 22),
      shape: Border(bottom: BorderSide(color: c.borde)),
      systemOverlayStyle: brillo == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: c.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: Redondeo.rLg, side: BorderSide(color: c.borde)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.superficieElevada,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Redondeo.rLg, side: BorderSide(color: c.borde)),
      titleTextStyle: Tipografia.h2.copyWith(color: c.texto, fontFamily: Fuente.ui),
      contentTextStyle: Tipografia.cuerpo.copyWith(color: c.textoSecundario, fontFamily: Fuente.ui),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.superficieElevada,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Redondeo.lg))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.superficie,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: Espacio.x3, vertical: Espacio.x3),
      border: borde(c.bordeFuerte),
      enabledBorder: borde(c.bordeFuerte),
      focusedBorder: borde(c.foco, 2),
      errorBorder: borde(c.errorRelleno),
      focusedErrorBorder: borde(c.errorRelleno, 2),
      disabledBorder: borde(c.borde),
      labelStyle: Tipografia.chicoFuerte.copyWith(color: c.textoSecundario),
      floatingLabelStyle: Tipografia.chicoFuerte.copyWith(color: c.textoSecundario),
      hintStyle: Tipografia.cuerpo.copyWith(color: c.textoTenue),
      helperStyle: Tipografia.chico.copyWith(color: c.textoTenue),
      errorStyle: Tipografia.chicoFuerte.copyWith(color: c.error),
      prefixIconColor: c.textoTenue,
      suffixIconColor: c.textoTenue,
    ),
    filledButtonTheme: FilledButtonThemeData(style: base(c.primario, c.primarioEncima, c.sobrePrimario)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: base(c.secundario, c.secundarioEncima, c.sobreSecundario)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base(c.superficie, c.superficie2, c.texto).copyWith(
        side: WidgetStateProperty.resolveWith((e) => BorderSide(
            color: e.contains(WidgetState.disabled)
                ? c.borde
                : e.contains(WidgetState.hovered)
                    ? c.textoSecundario
                    : c.bordeFuerte)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: base(Colors.transparent, c.superficieHundida, c.textoSecundario)),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(Quiebre.toque, Quiebre.toque)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Redondeo.rSm)),
        foregroundColor: WidgetStatePropertyAll(c.textoSecundario),
        iconSize: const WidgetStatePropertyAll(22),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.primario,
      foregroundColor: c.sobrePrimario,
      elevation: 2,
      extendedTextStyle: Tipografia.boton,
      shape: const RoundedRectangleBorder(borderRadius: Redondeo.rMd),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.superficie,
      selectedColor: c.secundario,
      checkmarkColor: c.sobreSecundario,
      side: BorderSide(color: c.borde),
      labelStyle: Tipografia.chicoFuerte.copyWith(color: c.textoSecundario),
      secondaryLabelStyle: Tipografia.chicoFuerte.copyWith(color: c.sobreSecundario),
      padding: const EdgeInsets.symmetric(horizontal: Espacio.x2, vertical: Espacio.x2),
      shape: const RoundedRectangleBorder(borderRadius: Redondeo.rPastilla),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.textoSecundario,
      textColor: c.texto,
      titleTextStyle: Tipografia.cuerpoFuerte.copyWith(color: c.texto),
      subtitleTextStyle: Tipografia.chico.copyWith(color: c.textoTenue),
      minVerticalPadding: 10,
      shape: const RoundedRectangleBorder(borderRadius: Redondeo.rSm),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.texto,
      unselectedLabelColor: c.textoTenue,
      labelStyle: Tipografia.cuerpoFuerte,
      unselectedLabelStyle: Tipografia.cuerpoFuerte,
      indicatorColor: c.primario,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: c.borde,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.nav,
      contentTextStyle: Tipografia.cuerpo.copyWith(color: const Color(0xFFF1F2F4)),
      actionTextColor: const Color(0xFF8EC0FF),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: Redondeo.rMd),
      insetPadding: const EdgeInsets.all(Espacio.x4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.nav, borderRadius: Redondeo.rXs2),
      textStyle: Tipografia.chico.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: Espacio.x2, vertical: Espacio.x1),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primario, linearTrackColor: c.superficieHundida, circularTrackColor: c.superficieHundida),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: c.bordeFuerte, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? c.primario : Colors.transparent),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Redondeo.xs))),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? c.primario : c.bordeFuerte)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? c.sobrePrimario : c.superficie),
      trackColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? c.primario : c.superficieHundida),
      trackOutlineColor: WidgetStatePropertyAll(c.bordeFuerte),
    ),
    dividerTheme: DividerThemeData(color: c.borde, space: 1, thickness: 1),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(c.bordeFuerte), radius: const Radius.circular(Redondeo.xs)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.nav,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
          (e) => Tipografia.chico.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: e.contains(WidgetState.selected) ? c.navTextoFuerte : c.navTexto)),
      iconTheme: WidgetStateProperty.resolveWith(
          (e) => IconThemeData(size: 24, color: e.contains(WidgetState.selected) ? c.primario : c.navTexto)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.nav,
      selectedIconTheme: IconThemeData(color: c.navTextoFuerte, size: 22),
      unselectedIconTheme: IconThemeData(color: c.navTexto, size: 22),
      selectedLabelTextStyle: Tipografia.chicoFuerte.copyWith(color: c.navTextoFuerte),
      unselectedLabelTextStyle: Tipografia.chico.copyWith(color: c.navTexto),
      indicatorColor: c.nav2,
      useIndicator: true,
    ),
  );
}
