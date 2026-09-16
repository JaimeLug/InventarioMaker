import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/errores.dart';
import '../datos/proveedores.dart';
import '../datos/repositorio.dart';
import 'hoja_acceso.dart';
import 'sesion.dart';

/// Gate de escritura (F-02).
///
/// Quien llama ya capturó todo (el formulario sigue en pantalla, detrás de la hoja de acceso).
/// Si falta sesión, rol, contraseña o confirmación, se pide lo que falte y, al conseguirlo,
/// [accion] se ejecuta sola: el usuario no vuelve a capturar nada ni a tocar "Guardar".
///
/// Devuelve el resultado de [accion], o null si el usuario canceló.
/// Lanza [ErrorApp] con un mensaje presentable si la acción falla por otra causa.
Future<T?> conAcceso<T>(
  BuildContext context,
  WidgetRef ref, {
  required String descripcion,
  required Requisito requisito,
  required Future<T> Function() accion,
}) async {
  var confirmada = false;
  for (var intento = 0; intento < 5; intento++) {
    if (!context.mounted) return null;
    final sesion = await ref.read(sesionProvider.future);
    if (!context.mounted) return null;

    final falta = evaluar(sesion, requisito);
    if (falta != Falta.nada) {
      if (!await _conseguir(context, falta, sesion, descripcion, requisito)) return null;
      ref.invalidate(sesionProvider);
      continue;
    }

    if (requisito.confirmar && !confirmada) {
      if (!await pedirConfirmacion(context, descripcion: descripcion)) return null;
      confirmada = true;
    }

    try {
      return await accion();
    } on Object catch (e) {
      final error = traducir(e);
      if (error.pideAcceso) {
        await ref.read(repositorioProvider).salir();
        ref.invalidate(sesionProvider);
        continue;
      }
      if (error.detalle == 'NIVEL_CONTRASENA') {
        if (!context.mounted ||
            !await pedirAcceso(context,
                descripcion: descripcion, soloContrasena: true, aviso: 'Esta acción necesita que entres con tu contraseña.')) {
          return null;
        }
        ref.invalidate(sesionProvider);
        continue;
      }
      if (error.detalle == 'CONFIRMAR_CONTRASENA') {
        if (!context.mounted || !await pedirConfirmacion(context, descripcion: descripcion)) return null;
        confirmada = true;
        continue;
      }
      if (error.detalle == 'CUENTA_INACTIVA') {
        await ref.read(repositorioProvider).salir();
        ref.invalidate(sesionProvider);
      }
      throw error;
    }
  }
  throw const ErrorApp('No se pudo completar la acción. Intenta de nuevo.');
}

Future<bool> _conseguir(BuildContext context, Falta falta, Sesion? sesion, String descripcion, Requisito requisito) =>
    switch (falta) {
      Falta.sesion => pedirAcceso(context, descripcion: descripcion, soloContrasena: requisito.nivel == Nivel.contrasena),
      Falta.contrasena => pedirAcceso(context,
          descripcion: descripcion, soloContrasena: true, aviso: 'Esta acción necesita que entres con tu contraseña.'),
      Falta.rol => _pedirOtraCuenta(context, sesion!, descripcion, requisito),
      Falta.nada => Future.value(true),
    };

Future<bool> _pedirOtraCuenta(BuildContext context, Sesion sesion, String descripcion, Requisito requisito) async {
  final cambiar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Tu cuenta no puede hacer esto'),
      content: Text('Entraste como ${sesion.nombre} (${sesion.rol.nombre}).\n\n'
          'Para $descripcion se necesita la cuenta del responsable del laboratorio o de sub administración.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Entrar con otra cuenta')),
      ],
    ),
  );
  if (cambiar != true || !context.mounted) return false;
  return pedirAcceso(context, descripcion: descripcion, soloContrasena: requisito.nivel == Nivel.contrasena);
}

/// Muestra un error de [conAcceso] u otra operación como aviso en la parte baja de la pantalla.
void avisarError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(traducir(error).mensaje),
    backgroundColor: Theme.of(context).colorScheme.error,
    duration: const Duration(seconds: 6),
  ));
}

void avisar(BuildContext context, String mensaje) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}
