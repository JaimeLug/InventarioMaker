import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';
import 'insignia.dart';

class TmDestino {
  const TmDestino(this.ruta, this.texto, this.icono, {this.conteo, this.urgente = false});

  final String ruta;
  final String texto;
  final IconData icono;

  /// Cuántas cosas esperan en esa pantalla (préstamos vencidos, pendientes…).
  final int? conteo;

  /// El contador se pinta en rojo.
  final bool urgente;
}

class TmGrupoNav {
  const TmGrupoNav(this.titulo, this.destinos);

  final String titulo;
  final List<TmDestino> destinos;
}

/// El armazón de la app: barra lateral en computadora, rieles de iconos en tablet
/// y barra inferior con "Escanear" al centro en el celular.
class TmShell extends StatelessWidget {
  const TmShell({
    super.key,
    required this.grupos,
    required this.rutaActual,
    required this.onIr,
    required this.child,
    this.enBarraInferior = const [],
    this.usuario,
    this.rolUsuario,
    this.estadoConexion,
    this.appBar,
    this.fab,
    this.lateralPlegada,
    this.alPlegar,
  });

  final List<TmGrupoNav> grupos;
  final String rutaActual;
  final void Function(String ruta) onIr;
  final Widget child;

  /// Las cinco de la barra inferior del celular (la de en medio es Escanear).
  final List<TmDestino> enBarraInferior;
  final String? usuario;
  final String? rolUsuario;

  /// "En línea · datos de hace 2 min" o "Sin conexión · 3 por enviar".
  final Widget? estadoConexion;
  final PreferredSizeWidget? appBar;
  final Widget? fab;

  /// null = como quepa (según el ancho). true/false = lo que eligió la persona.
  final bool? lateralPlegada;
  final ValueChanged<bool>? alPlegar;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    if (ancho >= Quiebre.rieles) {
      final compacta = lateralPlegada ?? ancho < Quiebre.lateral;
      return Scaffold(
        body: Row(children: [
          _Lateral(
            grupos: grupos,
            rutaActual: rutaActual,
            onIr: onIr,
            compacta: compacta,
            usuario: usuario,
            rolUsuario: rolUsuario,
            estadoConexion: estadoConexion,
            alPlegar: alPlegar == null ? null : () => alPlegar!(!compacta),
          ),
          Expanded(child: Scaffold(appBar: appBar, body: child, floatingActionButton: fab)),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: child,
      floatingActionButton: fab,
      bottomNavigationBar: enBarraInferior.isEmpty ? null : _BarraInferior(destinos: enBarraInferior, rutaActual: rutaActual, onIr: onIr),
    );
  }
}

class _Lateral extends StatelessWidget {
  const _Lateral({
    required this.grupos,
    required this.rutaActual,
    required this.onIr,
    required this.compacta,
    this.usuario,
    this.rolUsuario,
    this.estadoConexion,
    this.alPlegar,
  });

  final List<TmGrupoNav> grupos;
  final String rutaActual;
  final void Function(String) onIr;
  final bool compacta;
  final String? usuario;
  final String? rolUsuario;
  final Widget? estadoConexion;
  final VoidCallback? alPlegar;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return AnimatedContainer(
      duration: Duracion.base,
      curve: Duracion.curva,
      width: compacta ? 76 : 248,
      decoration: BoxDecoration(
        color: c.nav,
        border: Border(right: BorderSide(color: c.nav2)),
      ),
      child: SafeArea(
        right: false,
        child: Column(children: [
          // Marca y botón para plegar.
          Padding(
            padding: EdgeInsets.fromLTRB(compacta ? Espacio.x2 : Espacio.x3, Espacio.x3, compacta ? Espacio.x2 : Espacio.x2, Espacio.x2),
            child: Row(mainAxisAlignment: compacta ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.primario, borderRadius: Redondeo.rSm),
                child: Icon(Ico.marca, color: c.sobrePrimario, size: 20),
              ),
              if (!compacta) ...[
                const SizedBox(width: Espacio.x2),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('TALLER MAKER', style: Tipografia.etiqueta.copyWith(fontSize: 16, letterSpacing: .8, color: c.navTextoFuerte)),
                    Text('Prepa 13 · Renacimiento Maya',
                        style: Tipografia.chico.copyWith(fontSize: 11, color: c.navTexto), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (alPlegar != null)
                  _IconoNav(
                    icono: Ico.plegar,
                    etiqueta: 'Plegar el menú',
                    onTap: alPlegar!,
                  ),
              ],
            ]),
          ),
          if (compacta && alPlegar != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Espacio.x1),
              child: _IconoNav(icono: Ico.desplegar, etiqueta: 'Abrir el menú', onTap: alPlegar!),
            ),
          Expanded(
            child: Scrollbar(
              child: ListView(
                primary: false,
                padding: EdgeInsets.symmetric(horizontal: compacta ? Espacio.x2 : Espacio.x3, vertical: Espacio.x1),
                children: [
                  for (final g in grupos) ...[
                    if (!compacta)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Espacio.x2, Espacio.x3, Espacio.x2, Espacio.x1),
                        child: Text(g.titulo.toUpperCase(), style: Tipografia.etiqueta.copyWith(fontSize: 10.5, color: const Color(0xFF7E8691))),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Espacio.x2, horizontal: Espacio.x2),
                        child: Divider(color: c.nav2, height: 1),
                      ),
                    for (final d in g.destinos)
                      _ItemLateral(destino: d, activo: rutaActual == d.ruta, compacta: compacta, onTap: () => onIr(d.ruta)),
                  ],
                  const SizedBox(height: Espacio.x2),
                ],
              ),
            ),
          ),
          if (estadoConexion != null || usuario != null)
            Container(
              padding: EdgeInsets.all(compacta ? Espacio.x2 : Espacio.x3),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.nav2))),
              child: Column(children: [
                if (estadoConexion != null) estadoConexion!,
                if (usuario != null) ...[
                  const SizedBox(height: Espacio.x2),
                  Row(mainAxisAlignment: compacta ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                    Tooltip(message: compacta ? '$usuario${rolUsuario == null ? '' : '\n$rolUsuario'}' : '', child: TmAvatar(usuario!, tamano: 34, enNavegacion: true)),
                    if (!compacta) ...[
                      const SizedBox(width: Espacio.x2),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(usuario!, style: Tipografia.chicoFuerte.copyWith(color: c.navTextoFuerte), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (rolUsuario != null)
                            Text(rolUsuario!, style: Tipografia.chico.copyWith(fontSize: 11, color: c.navTexto), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ],
                  ]),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Botón de icono para la barra oscura (respeta el toque cómodo y se ve al enfocar con teclado).
class _IconoNav extends StatelessWidget {
  const _IconoNav({required this.icono, required this.etiqueta, required this.onTap});

  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Tooltip(
      message: etiqueta,
      child: InkWell(
        onTap: onTap,
        borderRadius: Redondeo.rSm,
        hoverColor: c.nav2,
        focusColor: c.nav2,
        child: Padding(padding: const EdgeInsets.all(Espacio.x2), child: Icon(icono, size: 20, color: c.navTexto)),
      ),
    );
  }
}

class _ItemLateral extends StatelessWidget {
  const _ItemLateral({required this.destino, required this.activo, required this.compacta, required this.onTap});

  final TmDestino destino;
  final bool activo;
  final bool compacta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final conteo = destino.conteo ?? 0;
    final contador = conteo <= 0
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: destino.urgente ? c.primario : c.nav2, borderRadius: Redondeo.rPastilla),
            child: Text('$conteo',
                style: Tipografia.codigo.copyWith(fontSize: 11.5, color: destino.urgente ? c.sobrePrimario : c.navTextoFuerte)),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: activo,
        button: true,
        child: Tooltip(
          message: compacta ? '${destino.texto}${conteo > 0 ? ' ($conteo)' : ''}' : '',
          waitDuration: const Duration(milliseconds: 400),
          child: Material(
            color: activo ? c.nav2 : Colors.transparent,
            borderRadius: Redondeo.rSm,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              hoverColor: c.nav2.withValues(alpha: .7),
              focusColor: c.nav2,
              child: SizedBox(
                height: Quiebre.toque,
                child: Stack(children: [
                  // Marca de "estás aquí": una franja roja pegada al borde.
                  if (activo)
                    Positioned(
                      left: 0,
                      top: 6,
                      bottom: 6,
                      child: Container(width: 3, decoration: BoxDecoration(color: c.primario, borderRadius: BorderRadius.circular(2))),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: compacta ? 0 : Espacio.x3),
                    child: Row(mainAxisAlignment: compacta ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                      Icon(destino.icono, size: 20, color: activo ? c.navTextoFuerte : c.navTexto),
                      if (!compacta) ...[
                        const SizedBox(width: Espacio.x3),
                        Expanded(
                          child: Text(destino.texto,
                              style: Tipografia.chicoFuerte.copyWith(fontSize: 14.5, color: activo ? c.navTextoFuerte : c.navTexto),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        ?contador,
                      ],
                    ]),
                  ),
                  if (compacta && conteo > 0)
                    Positioned(
                      right: 10,
                      top: 4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: destino.urgente ? c.primario : c.navTexto, shape: BoxShape.circle),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra inferior del celular, con "Escanear" elevado al centro.
class _BarraInferior extends StatelessWidget {
  const _BarraInferior({required this.destinos, required this.rutaActual, required this.onIr});

  final List<TmDestino> destinos;
  final String rutaActual;
  final void Function(String) onIr;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final medio = destinos.length ~/ 2;
    return Container(
      decoration: BoxDecoration(color: c.nav, boxShadow: Sombra.dos(Brightness.dark)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (final (i, d) in destinos.indexed)
                Expanded(
                  child: i == medio
                      ? _BotonEscanear(destino: d, onTap: () => onIr(d.ruta))
                      : _ItemInferior(destino: d, activo: rutaActual == d.ruta, onTap: () => onIr(d.ruta)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemInferior extends StatelessWidget {
  const _ItemInferior({required this.destino, required this.activo, required this.onTap});

  final TmDestino destino;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Semantics(
      selected: activo,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Barrita de "estás aquí" arriba del icono.
          AnimatedContainer(
            duration: Duracion.rapida,
            height: 3,
            width: activo ? 24 : 0,
            decoration: BoxDecoration(color: c.primario, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 5),
          Badge(
            isLabelVisible: (destino.conteo ?? 0) > 0,
            label: Text('${destino.conteo}'),
            backgroundColor: destino.urgente ? c.primario : c.nav2,
            textColor: Colors.white,
            child: Icon(destino.icono, size: 23, color: activo ? c.navTextoFuerte : c.navTexto),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              destino.texto,
              style: Tipografia.chico.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: activo ? c.navTextoFuerte : c.navTexto),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ),
    );
  }
}

/// El botón del centro: sobresale de la barra para encontrarlo sin ver.
class _BotonEscanear extends StatelessWidget {
  const _BotonEscanear({required this.destino, required this.onTap});

  final TmDestino destino;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Tooltip(
      message: destino.texto,
      child: Semantics(
        button: true,
        label: destino.texto,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Material(
                color: c.primario,
                borderRadius: Redondeo.rLg,
                elevation: 4,
                shadowColor: Colors.black,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onTap();
                  },
                  borderRadius: Redondeo.rLg,
                  child: Container(
                    width: 56,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: Redondeo.rLg,
                      border: Border.all(color: c.nav, width: 3),
                    ),
                    child: Icon(destino.icono, color: c.sobrePrimario, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(destino.texto,
                  style: Tipografia.chico.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.navTextoFuerte),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ),
    );
  }
}
