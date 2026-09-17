import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../configuracion.dart';
import 'repositorio.dart';

/// Avisos al celular (solo Android, con Firebase). Si la app se compiló sin los datos de Firebase,
/// todo esto no hace nada y los avisos se ven igual en la campana de la app.
abstract final class AvisosCelular {
  static bool _listo = false;
  static StreamSubscription<String>? _renovacion;

  static bool get disponible => _listo;

  static Future<void> iniciar() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || !Configuracion.hayFirebase) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: Configuracion.firebaseApiKey,
          appId: Configuracion.firebaseAppId,
          messagingSenderId: Configuracion.firebaseSenderId,
          projectId: Configuracion.firebaseProjectId,
        ),
      );
      _listo = true;
    } on Object catch (e) {
      debugPrint('Firebase no se pudo iniciar: $e');
    }
  }

  /// Después de entrar: pide permiso de notificaciones y registra este celular a nombre de la cuenta.
  static Future<void> registrar(Repositorio repo) async {
    if (!_listo) return;
    try {
      final m = FirebaseMessaging.instance;
      final permiso = await m.requestPermission();
      if (permiso.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await m.getToken();
      if (token != null) await repo.registrarDispositivo(token);
      await _renovacion?.cancel();
      _renovacion = m.onTokenRefresh.listen((t) => repo.registrarDispositivo(t).catchError((_) {}));
    } on Object catch (e) {
      debugPrint('No se registró el celular para avisos: $e');
    }
  }

  /// [alTocar] recibe la ruta de la app a la que lleva el aviso; [alLlegar] se llama con la app abierta
  /// (Android no muestra la notificación en ese caso: la app la enseña ella misma).
  static void escuchar({required void Function(String ruta) alTocar, required void Function(String titulo, String? ruta) alLlegar}) {
    if (!_listo) return;
    FirebaseMessaging.onMessage.listen((m) => alLlegar(m.notification?.title ?? 'Aviso nuevo', m.data['ruta'] as String?));
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final ruta = m.data['ruta'];
      if (ruta is String && ruta.startsWith('/')) alTocar(ruta);
    });
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      final ruta = m?.data['ruta'];
      if (ruta is String && ruta.startsWith('/')) alTocar(ruta);
    });
  }
}
