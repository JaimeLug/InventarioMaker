import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion.dart';
import 'datos/avisos_celular.dart';
import 'datos/proveedores.dart';
import 'datos/repositorio.dart';
import 'ui/rutas.dart';
import 'ui/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await initializeDateFormatting('es_MX');
  await Supabase.initialize(url: Configuracion.supabaseUrl, publishableKey: Configuracion.supabaseLlavePublica);
  await AvisosCelular.iniciar();
  runApp(const ProviderScope(child: InventarioApp()));
}

class InventarioApp extends ConsumerStatefulWidget {
  const InventarioApp({super.key});

  @override
  ConsumerState<InventarioApp> createState() => _InventarioAppState();
}

class _InventarioAppState extends ConsumerState<InventarioApp> {
  StreamSubscription<AuthState>? _cambiosDeSesion;
  Timer? _inactividad;
  String? _registradoPara;
  final _mensajes = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _cambiosDeSesion = Supabase.instance.client.auth.onAuthStateChange.listen((cambio) {
      if (cambio.event == AuthChangeEvent.signedIn || cambio.event == AuthChangeEvent.signedOut) {
        ref.invalidate(sesionProvider);
      }
      // Al entrar con PIN la sesión llega como "tokenRefreshed", no como "signedIn": se registra con cualquier
      // evento que traiga sesión, una sola vez por cuenta.
      final usuario = cambio.session?.user.id;
      if (usuario != null && usuario != _registradoPara) {
        _registradoPara = usuario;
        AvisosCelular.registrar(ref.read(repositorioProvider));
      }
      if (cambio.event == AuthChangeEvent.signedOut) _registradoPara = null;
    });
    AvisosCelular.escuchar(
      alTocar: (ruta) => ref.read(rutasProvider).push(ruta),
      alLlegar: (titulo, ruta) {
        _mensajes.currentState?.showSnackBar(SnackBar(
          content: Text(titulo),
          action: ruta == null ? null : SnackBarAction(label: 'Ver', onPressed: () => ref.read(rutasProvider).push(ruta)),
        ));
        ref.invalidate(avisosSinLeerProvider);
        ref.invalidate(solicitudesContarProvider);
        ref.invalidate(porRevisarProvider);
      },
    );
    _reiniciarInactividad();
  }

  /// En web (computadoras compartidas) la sesión se cierra tras un rato sin uso.
  /// En Android dura la jornada completa y la app siempre muestra con qué cuenta se firma.
  void _reiniciarInactividad() {
    if (!kIsWeb) return;
    _inactividad?.cancel();
    _inactividad = Timer(Configuracion.inactividadWeb, () {
      if (Supabase.instance.client.auth.currentSession != null) Supabase.instance.client.auth.signOut();
    });
  }

  @override
  void dispose() {
    _cambiosDeSesion?.cancel();
    _inactividad?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _reiniciarInactividad(),
      child: MaterialApp.router(
        scaffoldMessengerKey: _mensajes,
        title: 'Inventario Maker',
        theme: temaClaro(),
        routerConfig: ref.watch(rutasProvider),
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
