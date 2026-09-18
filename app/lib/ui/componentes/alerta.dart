import 'package:flutter/material.dart';

import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';
import 'boton.dart';
import 'insignia.dart';

/// Aviso dentro de la pantalla: qué pasó y qué hacer.
class TmAlerta extends StatelessWidget {
  const TmAlerta({
    super.key,
    required this.titulo,
    this.texto,
    this.tono = Tono.info,
    this.icono,
    this.accion,
    this.cinta = false,
  });

  final String titulo;
  final String? texto;
  final Tono tono;
  final IconData? icono;
  final Widget? accion;

  /// Cinta de seguridad (negro y ámbar): solo para conflictos de existencia.
  final bool cinta;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final (fondo, frente, icoDefecto) = switch (tono) {
      Tono.ok => (c.exitoSuave, c.exito, Ico.ok),
      Tono.aviso => (c.avisoSuave, c.aviso, Ico.aviso),
      Tono.error => (c.errorSuave, c.error, Ico.error),
      _ => (c.infoSuave, c.info, Ico.info),
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: Redondeo.rMd,
        border: Border.all(color: Color.alphaBlend(frente.withValues(alpha: .35), fondo)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cinta) SizedBox(width: 6, child: CustomPaint(painter: _Cinta(c.avisoRelleno, c.nav), child: const SizedBox(height: 64))),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(Espacio.x3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icono ?? icoDefecto, size: 20, color: frente),
              const SizedBox(width: Espacio.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(titulo, style: Tipografia.cuerpoFuerte.copyWith(color: c.texto)),
                  if (texto != null) Text(texto!, style: Tipografia.chico.copyWith(color: c.textoSecundario)),
                ]),
              ),
              if (accion != null) ...[const SizedBox(width: Espacio.x2), accion!],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Cinta extends CustomPainter {
  _Cinta(this.ambar, this.negro);

  final Color ambar, negro;

  @override
  void paint(Canvas lienzo, Size t) {
    lienzo.drawRect(Offset.zero & t, Paint()..color = ambar);
    final pincel = Paint()
      ..color = negro
      ..strokeWidth = 4;
    for (var y = -t.width; y < t.height + t.width; y += 12) {
      lienzo.drawLine(Offset(0, y), Offset(t.width, y - t.width), pincel);
    }
  }

  @override
  bool shouldRepaint(_Cinta anterior) => false;
}

/// Aviso flotante. Con "Deshacer" cuando la acción se puede revertir.
void mostrarAviso(BuildContext context, String texto, {IconData icono = Ico.ok, String? accion, VoidCallback? alAccionar, bool error = false}) {
  final c = context.tm;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: Duration(seconds: error ? 8 : 5),
      backgroundColor: error ? c.errorRelleno : c.nav,
      content: Row(children: [
        Icon(icono, size: 20, color: error ? Colors.white : c.exitoRelleno),
        const SizedBox(width: Espacio.x2),
        Expanded(child: Text(texto, style: Tipografia.cuerpo.copyWith(color: Colors.white))),
      ]),
      action: accion == null ? null : SnackBarAction(label: accion, textColor: const Color(0xFF8EC0FF), onPressed: alAccionar ?? () {}),
    ));
}

/// Confirmación de algo irreversible: dice la consecuencia y el botón repite la acción.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String consecuencia,
  required String botonSi,
  IconData icono = Ico.baja,
  bool peligro = true,
  Widget? extra,
}) async {
  final c = context.tm;
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: peligro ? c.errorSuave : c.primarioSuave, shape: BoxShape.circle),
        child: Icon(icono, color: peligro ? c.error : c.primarioTexto, size: 20),
      ),
      iconPadding: const EdgeInsets.fromLTRB(Espacio.x5, Espacio.x5, Espacio.x5, 0),
      title: Text(titulo),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(consecuencia),
        if (extra != null) ...[const SizedBox(height: Espacio.x3), extra],
      ]),
      actionsPadding: const EdgeInsets.all(Espacio.x3),
      actions: [
        TmBoton('Cancelar', tipo: TipoBoton.fantasma, onTap: () => Navigator.pop(context, false)),
        TmBoton(botonSi, tipo: peligro ? TipoBoton.peligro : TipoBoton.primario, icono: icono, onTap: () => Navigator.pop(context, true)),
      ],
    ),
  );
  return respuesta ?? false;
}
