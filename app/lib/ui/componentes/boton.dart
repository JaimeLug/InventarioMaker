import 'package:flutter/material.dart';

import '../diseno/tokens.dart';

enum TipoBoton {
  /// La acción principal de la pantalla: una sola por vista.
  primario,

  /// Crear algo de uso frecuente.
  secundario,

  /// Acciones alternativas junto a la principal.
  contorno,

  /// Cancelar, ver más, acciones dentro de listas.
  fantasma,

  /// Solo dentro de una confirmación de algo irreversible.
  peligro,
}

enum TamanoBoton { chico, normal, grande }

/// Botón del sistema. El tamaño mínimo siempre respeta el toque cómodo del taller.
class TmBoton extends StatelessWidget {
  const TmBoton(
    this.texto, {
    super.key,
    this.onTap,
    this.icono,
    this.tipo = TipoBoton.contorno,
    this.tamano = TamanoBoton.normal,
    this.expandido = false,
    this.cargando = false,
    this.tooltip,
  });

  final String texto;
  final VoidCallback? onTap;
  final IconData? icono;
  final TipoBoton tipo;
  final TamanoBoton tamano;
  final bool expandido;
  final bool cargando;
  final String? tooltip;

  double get _alto => switch (tamano) {
        TamanoBoton.chico => 36,
        TamanoBoton.normal => Quiebre.toque,
        TamanoBoton.grande => 52,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final (fondo, encima, contenido, borde) = switch (tipo) {
      TipoBoton.primario => (c.primario, c.primarioEncima, c.sobrePrimario, null),
      TipoBoton.secundario => (c.secundario, c.secundarioEncima, c.sobreSecundario, null),
      TipoBoton.contorno => (c.superficie, c.superficie2, c.texto, c.bordeFuerte),
      TipoBoton.fantasma => (Colors.transparent, c.superficieHundida, c.textoSecundario, null),
      TipoBoton.peligro => (c.errorRelleno, c.error, Colors.white, null),
    };
    final estilo = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(expandido ? double.infinity : 64, _alto)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: tamano == TamanoBoton.chico ? Espacio.x3 : Espacio.x4)),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Redondeo.rSm)),
      textStyle: WidgetStatePropertyAll(tamano == TamanoBoton.chico ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600) : null),
      backgroundColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.disabled)
          ? (tipo == TipoBoton.fantasma ? Colors.transparent : c.superficieHundida)
          : e.contains(WidgetState.hovered) || e.contains(WidgetState.pressed)
              ? encima
              : fondo),
      foregroundColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.disabled) ? c.textoDeshabilitado : contenido),
      side: borde == null
          ? null
          : WidgetStateProperty.resolveWith(
              (e) => BorderSide(color: e.contains(WidgetState.disabled) ? c.borde : (e.contains(WidgetState.hovered) ? c.textoSecundario : borde))),
      iconSize: WidgetStatePropertyAll(tamano == TamanoBoton.chico ? 18 : 20),
      elevation: const WidgetStatePropertyAll(0),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );
    final etiqueta = Text(texto, overflow: TextOverflow.ellipsis);
    final icono = cargando
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: tipo == TipoBoton.primario ? c.sobrePrimario : c.textoSecundario))
        : (this.icono == null ? null : Icon(this.icono));
    final boton = icono == null
        ? TextButton(style: estilo, onPressed: cargando ? null : onTap, child: etiqueta)
        : TextButton.icon(style: estilo, onPressed: cargando ? null : onTap, icon: icono, label: etiqueta);
    return tooltip == null ? boton : Tooltip(message: tooltip!, child: boton);
  }
}

/// Botón de solo icono. Siempre lleva nombre para lectores de pantalla y tooltip.
class TmBotonIcono extends StatelessWidget {
  const TmBotonIcono(this.icono, {super.key, required this.etiqueta, this.onTap, this.tono, this.tamano = TamanoBoton.normal});

  final IconData icono;
  final String etiqueta;
  final VoidCallback? onTap;
  final Color? tono;
  final TamanoBoton tamano;

  @override
  Widget build(BuildContext context) {
    final lado = tamano == TamanoBoton.chico ? 36.0 : Quiebre.toque;
    return Tooltip(
      message: etiqueta,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icono),
        iconSize: tamano == TamanoBoton.chico ? 18 : 22,
        color: tono ?? context.tm.textoSecundario,
        constraints: BoxConstraints.tightFor(width: lado, height: lado),
        style: const ButtonStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Redondeo.rSm))),
        tooltip: null,
        splashRadius: lado / 2,
      ),
    );
  }
}
