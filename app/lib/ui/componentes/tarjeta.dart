import 'package:flutter/material.dart';

import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';

/// Tarjeta del sistema: borde sutil, sombra ligera y, si hace falta, cabecera con título y acciones.
class TmTarjeta extends StatelessWidget {
  const TmTarjeta({
    super.key,
    required this.child,
    this.titulo,
    this.icono,
    this.acciones = const [],
    this.padding = const EdgeInsets.all(Espacio.x4),
    this.sinPadding = false,
    this.onTap,
    this.tono,
  });

  final Widget child;
  final String? titulo;
  final IconData? icono;
  final List<Widget> acciones;
  final EdgeInsets padding;

  /// Para listas que llegan hasta el borde de la tarjeta.
  final bool sinPadding;
  final VoidCallback? onTap;

  /// Borde de atención (por ejemplo, una cifra crítica).
  final Color? tono;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final cuerpo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (titulo != null)
        Container(
          padding: const EdgeInsets.fromLTRB(Espacio.x5, Espacio.x4, Espacio.x3, Espacio.x4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.borde))),
          child: Row(children: [
            if (icono != null) ...[Icon(icono, size: 20, color: c.textoSecundario), const SizedBox(width: Espacio.x2)],
            Expanded(child: Text(titulo!, style: Tipografia.h3.copyWith(color: c.texto))),
            ...acciones,
          ]),
        ),
      Padding(padding: sinPadding ? EdgeInsets.zero : padding, child: child),
    ]);
    return Material(
      color: c.superficie,
      borderRadius: Redondeo.rLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: Redondeo.rLg,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: Redondeo.rLg,
            border: Border.all(color: tono ?? c.borde),
            boxShadow: Sombra.uno(Theme.of(context).brightness),
          ),
          child: cuerpo,
        ),
      ),
    );
  }
}

enum TonoKpi { normal, atencion, critico }

/// Cifra del tablero. Siempre se puede tocar: lleva a su lista ya filtrada.
class TmKpi extends StatelessWidget {
  const TmKpi({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.pie,
    this.icono,
    this.iconoPie,
    this.tono = TonoKpi.normal,
    this.onTap,
  });

  final String etiqueta;
  final String valor;
  final String? pie;
  final IconData? icono;
  final IconData? iconoPie;
  final TonoKpi tono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final (borde, colorValor) = switch (tono) {
      TonoKpi.normal => (c.borde, c.texto),
      TonoKpi.atencion => (Color.alphaBlend(c.avisoRelleno.withValues(alpha: .6), c.borde), c.aviso),
      TonoKpi.critico => (Color.alphaBlend(c.errorRelleno.withValues(alpha: .55), c.borde), c.error),
    };
    return TmTarjeta(
      onTap: onTap,
      tono: borde,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(etiqueta.toUpperCase(), style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
          const SizedBox(height: Espacio.x1),
          Text(valor, style: Tipografia.cifra.copyWith(color: colorValor)),
          if (pie != null) ...[
            const SizedBox(height: Espacio.x1),
            Row(children: [
              if (iconoPie != null) ...[Icon(iconoPie, size: 14, color: c.textoTenue), const SizedBox(width: 4)],
              Expanded(child: Text(pie!, style: Tipografia.chico.copyWith(fontSize: 13, color: c.textoTenue), overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]),
        if (icono != null) Positioned(top: 0, right: 0, child: Icon(icono, size: 18, color: c.textoTenue)),
      ]),
    );
  }
}

/// Miniatura de un artículo: foto si hay, icono de su categoría si no, con franja de color abajo.
class TmMiniatura extends StatelessWidget {
  const TmMiniatura({super.key, required this.icono, required this.color, this.imagen, this.lado = 44});

  final IconData icono;
  final Color color;
  final Widget? imagen;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Container(
      width: lado,
      height: lado,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.superficieHundida,
        borderRadius: Redondeo.rSm,
        border: Border.all(color: c.borde),
      ),
      child: Stack(fit: StackFit.expand, children: [
        imagen ?? Center(child: Icon(icono, size: lado * .5, color: c.textoTenue)),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 3, color: color)),
      ]),
    );
  }
}
