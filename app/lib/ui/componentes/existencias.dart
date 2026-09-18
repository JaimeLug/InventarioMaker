import 'package:flutter/material.dart';

import '../../modelos/articulo.dart';
import '../../util/texto.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';

/// Cómo está un artículo de existencias, con su icono y su texto (nunca solo color).
enum SituacionStock {
  disponible('Disponible'),
  enMinimo('En su mínimo'),
  ningunoDisponible('Ninguno disponible'),
  agotado('Agotado'),
  sinContar('Sin contar'),
  noSePresta('No se presta');

  const SituacionStock(this.texto);
  final String texto;

  IconData get icono => switch (this) {
        SituacionStock.disponible => Ico.ok,
        SituacionStock.enMinimo => Ico.aviso,
        SituacionStock.ningunoDisponible || SituacionStock.agotado => Ico.error,
        SituacionStock.sinContar => Ico.porVerificar,
        SituacionStock.noSePresta => Ico.noSePresta,
      };

  Color color(TmColores c) => switch (this) {
        SituacionStock.disponible => c.exito,
        SituacionStock.enMinimo => c.aviso,
        SituacionStock.ningunoDisponible || SituacionStock.agotado => c.error,
        SituacionStock.sinContar || SituacionStock.noSePresta => c.textoTenue,
      };

  static SituacionStock de(Articulo a) {
    if (a.conteoDesconocido) return SituacionStock.sinContar;
    if (a.noSePresta) return SituacionStock.noSePresta;
    if (a.disponible <= 0) return a.existencia > 0 ? SituacionStock.ningunoDisponible : SituacionStock.agotado;
    if (a.esConsumible && a.minimoReposicion != null && a.disponible <= a.minimoReposicion!) return SituacionStock.enMinimo;
    return SituacionStock.disponible;
  }
}

/// El indicador de existencias: cifra grande, barra segmentada y situación con icono.
///
/// La barra es apoyo visual; la cifra y el texto siempre están, y los segmentos
/// llevan trama (rayas o líneas) para que se distingan sin depender del color.
class TmExistencias extends StatelessWidget {
  const TmExistencias(this.articulo, {super.key, this.compacto = false, this.conLeyenda = false});

  final Articulo articulo;

  /// En tablas y tarjetas: sin la línea de situación.
  final bool compacto;
  final bool conLeyenda;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final a = articulo;
    final s = SituacionStock.de(a);
    final disponible = a.disponible < 0 ? 0 : a.disponible;
    final total = a.existencia <= 0 ? 1 : a.existencia;
    final unidad = a.cantidadEstimada ? '~' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(a.conteoDesconocido ? '?' : '$unidad$disponible', style: Tipografia.cifraChica.copyWith(color: c.texto)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              a.conteoDesconocido ? 'sin contar' : 'de ${conUnidad(a.existencia, a.unidad)}',
              style: Tipografia.chico.copyWith(color: c.textoTenue),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: Espacio.x1),
        Semantics(
          label: '$disponible disponibles de ${a.existencia}, ${a.prestado} prestados, ${a.fueraServicio} fuera de servicio',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                _seg(disponible / total, c.exitoRelleno, Trama.lleno),
                _seg(a.prestado / total, c.infoRelleno, Trama.rayas),
                _seg(a.apartado / total, c.avisoRelleno, Trama.lleno),
                _seg(a.fueraServicio / total, c.errorRelleno, Trama.lineas),
                if (disponible + a.prestado + a.apartado + a.fueraServicio == 0) _seg(1, c.superficieHundida, Trama.lleno),
              ]),
            ),
          ),
        ),
        if (!compacto) ...[
          const SizedBox(height: Espacio.x1),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.icono, size: 14, color: s.color(c)),
            const SizedBox(width: 4),
            Text(s.texto, style: Tipografia.chicoFuerte.copyWith(fontSize: 13, color: s.color(c))),
          ]),
        ],
        if (conLeyenda) ...[
          const SizedBox(height: Espacio.x2),
          const TmLeyendaExistencias(),
        ],
      ],
    );
  }

  Widget _seg(double parte, Color color, Trama trama) =>
      parte <= 0 ? const SizedBox.shrink() : Expanded(flex: (parte * 1000).round(), child: CustomPaint(painter: _Segmento(color, trama)));
}

enum Trama { lleno, rayas, lineas }

class _Segmento extends CustomPainter {
  _Segmento(this.color, this.trama);

  final Color color;
  final Trama trama;

  @override
  void paint(Canvas lienzo, Size t) {
    lienzo.drawRect(Offset.zero & t, Paint()..color = color);
    if (trama == Trama.lleno) return;
    final pincel = Paint()
      ..color = const Color(0x59000000)
      ..strokeWidth = 1.6;
    if (trama == Trama.rayas) {
      for (var x = -t.height; x < t.width; x += 5) {
        lienzo.drawLine(Offset(x, t.height), Offset(x + t.height, 0), pincel);
      }
    } else {
      for (var x = 1.0; x < t.width; x += 4) {
        lienzo.drawLine(Offset(x, 0), Offset(x, t.height), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_Segmento anterior) => anterior.color != color || anterior.trama != trama;
}

class TmLeyendaExistencias extends StatelessWidget {
  const TmLeyendaExistencias({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    Widget punto(Color color, Trama trama, String texto) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 14, height: 10, child: CustomPaint(painter: _Segmento(color, trama))),
          const SizedBox(width: 5),
          Text(texto, style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoSecundario)),
        ]);
    return Wrap(spacing: Espacio.x3, runSpacing: Espacio.x1, children: [
      punto(c.exitoRelleno, Trama.lleno, 'Disponible'),
      punto(c.infoRelleno, Trama.rayas, 'Prestado'),
      punto(c.avisoRelleno, Trama.lleno, 'Apartado'),
      punto(c.errorRelleno, Trama.lineas, 'Fuera de servicio'),
    ]);
  }
}
