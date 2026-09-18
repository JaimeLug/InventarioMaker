import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claro, oscuro o el que use el celular. Se guarda solo en este dispositivo.
class ModoTema extends Notifier<ThemeMode> {
  static const _clave = 'modo_tema';

  @override
  ThemeMode build() {
    _leer();
    return ThemeMode.system;
  }

  Future<void> _leer() async {
    try {
      final guardado = (await SharedPreferences.getInstance()).getString(_clave);
      if (guardado != null) state = ThemeMode.values.firstWhere((m) => m.name == guardado, orElse: () => ThemeMode.system);
    } on Object {
      // Si no se puede leer, se queda con el del celular.
    }
  }

  Future<void> cambiar(ThemeMode modo) async {
    state = modo;
    try {
      await (await SharedPreferences.getInstance()).setString(_clave, modo.name);
    } on Object {
      // No es grave: solo no se recuerda para la próxima vez.
    }
  }

  static String nombre(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Claro',
        ThemeMode.dark => 'Oscuro',
        ThemeMode.system => 'Como el celular',
      };
}

final modoTemaProvider = NotifierProvider<ModoTema, ThemeMode>(ModoTema.new);
