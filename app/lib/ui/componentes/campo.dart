import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';

/// Campo de texto del sistema: etiqueta arriba, ayuda abajo y error con icono.
class TmCampo extends StatelessWidget {
  const TmCampo({
    super.key,
    required this.etiqueta,
    this.controlador,
    this.ayuda,
    this.error,
    this.pista,
    this.icono,
    this.obligatorio = false,
    this.numerico = false,
    this.mono = false,
    this.lineas = 1,
    this.habilitado = true,
    this.onCambio,
    this.onEnviar,
    this.enfocar = false,
  });

  final String etiqueta;
  final TextEditingController? controlador;
  final String? ayuda;
  final String? error;
  final String? pista;
  final IconData? icono;
  final bool obligatorio;
  final bool numerico;

  /// Para códigos, series y resguardos.
  final bool mono;
  final int lineas;
  final bool habilitado;
  final ValueChanged<String>? onCambio;
  final ValueChanged<String>? onEnviar;
  final bool enfocar;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(
        TextSpan(children: [
          TextSpan(text: etiqueta),
          if (obligatorio) TextSpan(text: ' *', style: TextStyle(color: c.error)),
        ]),
        style: Tipografia.chicoFuerte.copyWith(color: c.texto),
      ),
      const SizedBox(height: Espacio.x1),
      TextField(
        controller: controlador,
        enabled: habilitado,
        autofocus: enfocar,
        minLines: lineas,
        maxLines: lineas,
        onChanged: onCambio,
        onSubmitted: onEnviar,
        keyboardType: numerico ? TextInputType.number : (lineas > 1 ? TextInputType.multiline : TextInputType.text),
        inputFormatters: numerico ? [FilteringTextInputFormatter.digitsOnly] : null,
        textCapitalization: numerico || mono ? TextCapitalization.none : TextCapitalization.sentences,
        style: mono ? Tipografia.codigo.copyWith(fontSize: 15, color: c.texto) : Tipografia.cuerpo.copyWith(color: c.texto),
        decoration: InputDecoration(
          hintText: pista,
          prefixIcon: icono == null ? null : Icon(icono, size: 20),
          errorText: error,
          helperText: ayuda,
          helperMaxLines: 3,
          errorMaxLines: 3,
          error: error == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Ico.alerta, size: 15, color: c.error),
                  const SizedBox(width: 5),
                  Flexible(child: Text(error!, style: Tipografia.chicoFuerte.copyWith(fontSize: 13, color: c.error))),
                ]),
        ),
      ),
    ]);
  }
}

/// Buscador: busca mientras se escribe, sin botón.
class TmBuscador extends StatelessWidget {
  const TmBuscador({super.key, required this.controlador, this.pista = 'Buscar por nombre, código, marca o ubicación', this.onCambio, this.onLimpiar});

  final TextEditingController controlador;
  final String pista;
  final ValueChanged<String>? onCambio;
  final VoidCallback? onLimpiar;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return TextField(
      controller: controlador,
      onChanged: onCambio,
      textInputAction: TextInputAction.search,
      style: Tipografia.cuerpo.copyWith(color: c.texto),
      decoration: InputDecoration(
        hintText: pista,
        prefixIcon: const Icon(Ico.buscar, size: 20),
        suffixIcon: controlador.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Ico.cerrar, size: 18),
                tooltip: 'Limpiar la búsqueda',
                onPressed: () {
                  controlador.clear();
                  onCambio?.call('');
                  onLimpiar?.call();
                },
              ),
      ),
    );
  }
}

/// Selector de una opción de una lista corta.
class TmSelector<T> extends StatelessWidget {
  const TmSelector({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.opciones,
    required this.nombre,
    required this.onCambio,
    this.ayuda,
    this.icono,
  });

  final String etiqueta;
  final T? valor;
  final List<T> opciones;
  final String Function(T) nombre;
  final ValueChanged<T?> onCambio;
  final String? ayuda;
  final IconData Function(T)? icono;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(etiqueta, style: Tipografia.chicoFuerte.copyWith(color: c.texto)),
      const SizedBox(height: Espacio.x1),
      DropdownButtonFormField<T>(
        value: valor,
        isExpanded: true,
        decoration: InputDecoration(helperText: ayuda),
        style: Tipografia.cuerpo.copyWith(color: c.texto),
        items: [
          for (final o in opciones)
            DropdownMenuItem(
              value: o,
              child: Row(children: [
                if (icono != null) ...[Icon(icono!(o), size: 18, color: c.textoSecundario), const SizedBox(width: Espacio.x2)],
                Expanded(child: Text(nombre(o), overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
        onChanged: onCambio,
      ),
    ]);
  }
}

/// Grupo de opciones excluyentes (vista tabla/tarjetas, para mí/para otra persona…).
class TmSegmento<T> extends StatelessWidget {
  const TmSegmento({super.key, required this.valor, required this.opciones, required this.onCambio, this.expandido = false});

  final T valor;

  /// Cada opción: valor, texto y, si ayuda, icono.
  final List<(T, String, IconData?)> opciones;
  final ValueChanged<T> onCambio;
  final bool expandido;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final botones = [
      for (final (v, texto, ico) in opciones)
        Semantics(
          button: true,
          selected: v == valor,
          child: InkWell(
            onTap: () => onCambio(v),
            borderRadius: Redondeo.rSm,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: Espacio.x3),
              decoration: BoxDecoration(
                color: v == valor ? c.superficie : Colors.transparent,
                borderRadius: Redondeo.rSm,
                boxShadow: v == valor ? Sombra.uno(Theme.of(context).brightness) : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (ico != null) ...[Icon(ico, size: 18, color: v == valor ? c.texto : c.textoSecundario), const SizedBox(width: 6)],
                Text(texto, style: Tipografia.chicoFuerte.copyWith(fontSize: 15, color: v == valor ? c.texto : c.textoSecundario)),
              ]),
            ),
          ),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.superficieHundida, borderRadius: Redondeo.rSm),
      child: expandido
          ? Row(children: [for (final b in botones) Expanded(child: b)])
          : Row(mainAxisSize: MainAxisSize.min, children: botones),
    );
  }
}
