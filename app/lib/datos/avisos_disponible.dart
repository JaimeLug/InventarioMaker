import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acceso/gate.dart';
import '../modelos/articulo.dart';
import 'local.dart';
import 'repositorio.dart';

/// "Avísame cuando regrese": pide un correo y registra el aviso (sin cuenta).
Future<void> pedirAvisoDisponible(BuildContext context, WidgetRef ref, Articulo a) async {
  final correo = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Avísame cuando regrese'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Te mandamos un correo cuando "${a.nombre}" vuelva a estar disponible. El aviso dura 30 días.'),
        const SizedBox(height: 12),
        TextField(
          controller: correo,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Tu correo'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Avisarme')),
      ],
    ),
  );
  final texto = correo.text.trim();
  correo.dispose();
  if (ok != true || texto.isEmpty || !context.mounted) return;
  try {
    final mensaje = await ref.read(repositorioProvider).avisarmeCuandoRegrese(a.id, texto, await AlmacenLocal.dispositivo());
    if (context.mounted) avisar(context, mensaje);
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}
