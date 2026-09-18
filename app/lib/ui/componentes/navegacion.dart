import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    if (ancho >= Quiebre.rieles) {
      return Scaffold(
        body: Row(children: [
          _Lateral(
            grupos: grupos,
            rutaActual: rutaActual,
            onIr: onIr,
            compacta: ancho < Quiebre.lateral,
            usuario: usuario,
            rolUsuario: rolUsuario,
            estadoConexion: estadoConexion,
          ),
          Expanded(child: Scaffold(appBar: appBar, body: child, floatingActionButton: fab)),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: child,
      floatingActionButton: fab,
      bottomNavigationBar: enBarraInferior.isEmpty
          ? null
          : _BarraInferior(destinos: enBarraInferior, rutaActual: rutaActual, onIr: onIr),
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
  });

  final List<TmGrupoNav> grupos;
  final String rutaActual;
  final void Function(String) onIr;
  final bool compacta;
  final String? usuario;
  final String? rolUsuario;
  final Widget? estadoConexion;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Container(
      width: compacta ? 76 : 248,
      color: c.nav,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compacta ? 0 : Espacio.x3, Espacio.x4, compacta ? 0 : Espacio.x3, Espacio.x3),
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
                    Text('TALLER MAKER',
                        style: Tipografia.etiqueta.copyWith(fontSize: 17, letterSpacing: .8, color: c.navTextoFuerte)),
                    Text('Prepa 13 · Renacimiento Maya',
                        style: Tipografia.chico.copyWith(fontSize: 11.5, color: c.navTexto), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ],
            ]),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: compacta ? Espacio.x2 : Espacio.x3),
              children: [
                for (final g in grupos) ...[
                  if (!compacta)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.x2, Espacio.x3, Espacio.x2, Espacio.x1),
                      child: Text(g.titulo.toUpperCase(), style: Tipografia.etiqueta.copyWith(fontSize: 11, color: const Color(0xFF7E8691))),
                    )
                  else
                    Divider(color: c.nav2, height: Espacio.x4),
                  for (final d in g.destinos)
                    _ItemLateral(destino: d, activo: rutaActual == d.ruta, compacta: compacta, onTap: () => onIr(d.ruta)),
                ],
              ],
            ),
          ),
          if (estadoConexion != null || usuario != null)
            Container(
              padding: const EdgeInsets.all(Espacio.x3),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.nav2))),
              child: Column(children: [
                if (estadoConexion != null) estadoConexion!,
                if (usuario != null) ...[
                  const SizedBox(height: Espacio.x2),
                  Row(mainAxisAlignment: compacta ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                    TmAvatar(usuario!, tamano: 34, enNavegacion: true),
                    if (!compacta) ...[
                      const SizedBox(width: Espacio.x2),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(usuario!, style: Tipografia.chicoFuerte.copyWith(color: c.navTextoFuerte), overflow: TextOverflow.ellipsis),
                          if (rolUsuario != null)
                            Text(rolUsuario!, style: Tipografia.chico.copyWith(fontSize: 11.5, color: c.navTexto), overflow: TextOverflow.ellipsis),
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

class _ItemLateral extends StatelessWidget {
  const _ItemLateral({required this.destino, required this.activo, required this.compacta, required this.onTap});

  final TmDestino destino;
  final bool activo;
  final bool compacta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final contenido = Container(
      height: Quiebre.toque,
      padding: EdgeInsets.symmetric(horizontal: compacta ? 0 : Espacio.x3),
      decoration: BoxDecoration(color: activo ? c.nav2 : Colors.transparent, borderRadius: Redondeo.rSm),
      child: Row(mainAxisAlignment: compacta ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
        Icon(destino.icono, size: 20, color: activo ? c.navTextoFuerte : c.navTexto),
        if (!compacta) ...[
          const SizedBox(width: Espacio.x3),
          Expanded(
            child: Text(destino.texto,
                style: Tipografia.chicoFuerte.copyWith(fontSize: 15, color: activo ? c.navTextoFuerte : c.navTexto),
                overflow: TextOverflow.ellipsis),
          ),
          if (destino.conteo != null && destino.conteo! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: destino.urgente ? c.primario : c.nav2, borderRadius: Redondeo.rPastilla),
              child: Text('${destino.conteo}',
                  style: Tipografia.codigo.copyWith(fontSize: 12, color: destino.urgente ? c.sobrePrimario : c.navTextoFuerte)),
            ),
        ],
      ]),
    );
    return Semantics(
      selected: activo,
      button: true,
      child: Tooltip(
        message: compacta ? '${destino.texto}${destino.conteo != null && destino.conteo! > 0 ? ' (${destino.conteo})' : ''}' : '',
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: Redondeo.rSm, child: contenido)),
          ),
          if (activo)
            Positioned(left: compacta ? 2 : -Espacio.x2, top: 8, bottom: 8, child: Container(width: 3, color: c.primario)),
          if (compacta && (destino.conteo ?? 0) > 0)
            Positioned(
              right: 8,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: destino.urgente ? c.primario : c.nav2, borderRadius: Redondeo.rPastilla),
                child: Text('${destino.conteo}', style: Tipografia.codigo.copyWith(fontSize: 10, color: c.navTextoFuerte)),
              ),
            ),
        ]),
      ),
    );
  }
}

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
      color: c.nav,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final (i, d) in destinos.indexed)
                Expanded(
                  child: Semantics(
                    selected: rutaActual == d.ruta,
                    button: true,
                    child: InkWell(
                      onTap: () => onIr(d.ruta),
                      child: i == medio
                          ? Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: c.primario, borderRadius: Redondeo.rMd),
                                child: Icon(d.icono, color: c.sobrePrimario, size: 26),
                              ),
                            )
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Badge(
                                isLabelVisible: (d.conteo ?? 0) > 0,
                                label: Text('${d.conteo}'),
                                backgroundColor: d.urgente ? c.primario : c.nav2,
                                child: Icon(d.icono, size: 24, color: rutaActual == d.ruta ? c.primario : c.navTexto),
                              ),
                              const SizedBox(height: 2),
                              Text(d.texto,
                                  style: Tipografia.chico.copyWith(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: rutaActual == d.ruta ? c.navTextoFuerte : c.navTexto)),
                            ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
