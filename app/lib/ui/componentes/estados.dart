import 'package:flutter/material.dart';

import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';
import 'boton.dart';

/// Estado vacío: qué falta y qué se puede hacer.
class TmVacio extends StatelessWidget {
  const TmVacio({super.key, required this.titulo, required this.texto, this.icono = Ico.vacio, this.acciones = const []});

  final String titulo;
  final String texto;
  final IconData icono;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacio.x5, vertical: Espacio.x10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: Redondeo.rLg,
                border: Border.all(color: c.bordeFuerte, width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
              ),
              child: Icon(icono, size: 32, color: c.textoTenue),
            ),
            const SizedBox(height: Espacio.x4),
            Text(titulo, style: Tipografia.h3.copyWith(color: c.texto), textAlign: TextAlign.center),
            const SizedBox(height: Espacio.x2),
            Text(texto, style: Tipografia.cuerpo.copyWith(color: c.textoSecundario), textAlign: TextAlign.center),
            if (acciones.isNotEmpty) ...[
              const SizedBox(height: Espacio.x4),
              Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, alignment: WrapAlignment.center, children: acciones),
            ],
          ]),
        ),
      ),
    );
  }
}

/// No se pudo cargar: se explica y se ofrece reintentar. Nunca una pantalla en blanco.
class TmErrorCarga extends StatelessWidget {
  const TmErrorCarga({super.key, required this.mensaje, this.onReintentar, this.titulo = 'No se pudo cargar'});

  final String mensaje;
  final String titulo;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) => TmVacio(
        icono: Ico.alerta,
        titulo: titulo,
        texto: mensaje,
        acciones: [if (onReintentar != null) TmBoton('Reintentar', icono: Ico.reintentar, onTap: onReintentar)],
      );
}

/// Esqueletos con la forma real de lo que va a llegar.
class TmCargandoLista extends StatefulWidget {
  const TmCargandoLista({super.key, this.renglones = 6});

  final int renglones;

  @override
  State<TmCargandoLista> createState() => _TmCargandoListaState();
}

class _TmCargandoListaState extends State<TmCargandoLista> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final reducido = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: 'Cargando',
      child: Column(children: [
        for (var i = 0; i < widget.renglones; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Espacio.x2, horizontal: Espacio.x1),
            child: Row(children: [
              _Bloque(_c, ancho: 44, alto: 44, reducido: reducido),
              const SizedBox(width: Espacio.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Bloque(_c, ancho: double.infinity, alto: 12, reducido: reducido),
                  const SizedBox(height: Espacio.x2),
                  _Bloque(_c, ancho: 140, alto: 10, reducido: reducido),
                ]),
              ),
              const SizedBox(width: Espacio.x3),
              _Bloque(_c, ancho: 64, alto: 20, reducido: reducido),
            ]),
          ),
        const SizedBox(height: Espacio.x2),
        Text('Cargando…', style: Tipografia.chico.copyWith(color: c.textoTenue)),
      ]),
    );
  }
}

class _Bloque extends StatelessWidget {
  const _Bloque(this.animacion, {required this.ancho, required this.alto, required this.reducido});

  final Animation<double> animacion;
  final double ancho, alto;
  final bool reducido;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return AnimatedBuilder(
      animation: animacion,
      builder: (context, _) => Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Redondeo.xs),
          gradient: reducido
              ? null
              : LinearGradient(
                  colors: [c.superficieHundida, c.superficie2, c.superficieHundida],
                  stops: const [0, .5, 1],
                  begin: Alignment(-1 - 2 * (1 - animacion.value), 0),
                  end: Alignment(1 + 2 * animacion.value, 0),
                ),
          color: reducido ? c.superficieHundida : null,
        ),
      ),
    );
  }
}
