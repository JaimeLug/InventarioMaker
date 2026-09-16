import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion.dart';
import 'datos/proveedores.dart';
import 'ui/rutas.dart';
import 'ui/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await initializeDateFormatting('es_MX');
  await Supabase.initialize(url: Configuracion.supabaseUrl, publishableKey: Configuracion.supabaseLlavePublica);
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

  @override
  void initState() {
    super.initState();
    _cambiosDeSesion = Supabase.instance.client.auth.onAuthStateChange.listen((cambio) {
      if (cambio.event == AuthChangeEvent.signedIn || cambio.event == AuthChangeEvent.signedOut) {
        ref.invalidate(sesionProvider);
      }
    });
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
