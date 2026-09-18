import 'package:flutter/material.dart';

import '../../modelos/catalogos.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';

enum Tono { ok, aviso, error, info, neutro, contorno }

/// Insignia de estado: color + icono + texto (el color nunca va solo).
class TmInsignia extends StatelessWidget {
  const TmInsignia(this.texto, {super.key, this.tono = Tono.neutro, this.icono});

  final String texto;
  final Tono tono;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final (fondo, frente) = switch (tono) {
      Tono.ok => (c.exitoSuave, c.exito),
      Tono.aviso => (c.avisoSuave, c.aviso),
      Tono.error => (c.errorSuave, c.error),
      Tono.info => (c.infoSuave, c.info),
      Tono.neutro => (c.superficieHundida, c.textoSecundario),
      Tono.contorno => (Colors.transparent, c.textoSecundario),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.x2, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: Redondeo.rXs2,
        border: tono == Tono.contorno ? Border.all(color: c.bordeFuerte) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icono != null) ...[Icon(icono, size: 14, color: frente), const SizedBox(width: 5)],
        Flexible(child: Text(texto, style: Tipografia.chicoFuerte.copyWith(color: frente, fontSize: 13), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// La categoría: franja de color, icono y nombre. Nunca solo el color.
class TmCategoria extends StatelessWidget {
  const TmCategoria(this.categoria, {super.key, this.corto = false});

  final Categoria categoria;

  /// En tablas: "H. eléctricas" en vez de "Herramientas eléctricas".
  final bool corto;

  static const _cortos = {
    Categoria.herramientasElectricas: 'H. eléctricas',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final color = c.deCategoria(categoria);
    final nombre = corto ? (_cortos[categoria] ?? categoria.nombre) : categoria.nombre;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // "Sin clasificar" lleva franja punteada: se distingue aunque no se vea el color.
      SizedBox(
        width: 4,
        height: 18,
        child: CustomPaint(painter: _Franja(color, punteada: categoria == Categoria.sinClasificar)),
      ),
      const SizedBox(width: 6),
      Icon(Ico.deCategoria(categoria), size: 15, color: color),
      const SizedBox(width: 5),
      Flexible(child: Text(nombre, style: Tipografia.chicoFuerte.copyWith(color: c.textoSecundario), overflow: TextOverflow.ellipsis)),
    ]);
  }
}

class _Franja extends CustomPainter {
  _Franja(this.color, {this.punteada = false});

  final Color color;
  final bool punteada;

  @override
  void paint(Canvas lienzo, Size tamano) {
    final pincel = Paint()..color = color;
    if (!punteada) {
      lienzo.drawRRect(RRect.fromRectAndRadius(Offset.zero & tamano, const Radius.circular(2)), pincel);
      return;
    }
    for (var y = 0.0; y < tamano.height; y += 5) {
      lienzo.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y, tamano.width, 3), const Radius.circular(1)), pincel);
    }
  }

  @override
  bool shouldRepaint(_Franja anterior) => anterior.color != color || anterior.punteada != punteada;
}

/// Chip de filtro: se puede prender y apagar y dice cuántos hay.
class TmChip extends StatelessWidget {
  const TmChip(this.texto, {super.key, this.seleccionado = false, this.onTap, this.conteo, this.color, this.icono});

  final String texto;
  final bool seleccionado;
  final VoidCallback? onTap;
  final int? conteo;
  final Color? color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Semantics(
      button: true,
      selected: seleccionado,
      child: InkWell(
        onTap: onTap,
        borderRadius: Redondeo.rPastilla,
        child: Container(
          height: Quiebre.toque - 8,
          padding: const EdgeInsets.symmetric(horizontal: Espacio.x3),
          decoration: BoxDecoration(
            color: seleccionado ? c.secundario : c.superficie,
            borderRadius: Redondeo.rPastilla,
            border: Border.all(color: seleccionado ? c.secundario : c.borde),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (color != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
            ] else if (icono != null) ...[
              Icon(icono, size: 16, color: seleccionado ? c.sobreSecundario : c.textoSecundario),
              const SizedBox(width: 6),
            ],
            Text(texto,
                style: Tipografia.chicoFuerte.copyWith(fontSize: 15, color: seleccionado ? c.sobreSecundario : c.textoSecundario)),
            if (conteo != null) ...[
              const SizedBox(width: 6),
              Text('$conteo',
                  style: Tipografia.codigo.copyWith(
                      fontSize: 12, color: (seleccionado ? c.sobreSecundario : c.textoTenue).withValues(alpha: .8))),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Iniciales de una persona. Nunca fotos de identificación.
class TmAvatar extends StatelessWidget {
  const TmAvatar(this.nombre, {super.key, this.tamano = 36, this.enNavegacion = false});

  final String nombre;
  final double tamano;
  final bool enNavegacion;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final partes = nombre.replaceAll(RegExp(r'^(Mtra?\.|Ing\.|Prof\.)\s*'), '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final iniciales = partes.take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: enNavegacion ? c.nav2 : c.acentoSuave, shape: BoxShape.circle),
      child: Text(iniciales.isEmpty ? '?' : iniciales,
          style: Tipografia.chicoFuerte.copyWith(color: enNavegacion ? c.navTextoFuerte : c.acento, fontSize: tamano * .34)),
    );
  }
}
