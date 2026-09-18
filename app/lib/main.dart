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
import 'sin_conexion/cola.dart';
import 'ui/diseno/modo_tema.dart';
import 'ui/rutas.dart';
import 'ui/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await initializeDateFormatting('es_MX');
  await Supabase.initialize(url: Configuracion.supabaseUrl, publishableKey: Configuracion.supabaseLlavePublica);
  await AvisosCelular.iniciar();
  final contenedor = ProviderContainer();
  // En el celular: cola de lo capturado sin señal y copia de lo necesario para trabajar sin ella (F-17).
  await ColaSinConexion.iniciar(descargarDatos: () => contenedor.read(repositorioProvider).descargarParaSinConexion());
  runApp(UncontrolledProviderScope(container: contenedor, child: const InventarioApp()));
}

class InventarioApp extends ConsumerStatefulWidget {
  const InventarioApp({super.key});

  @override
  ConsumerState<InventarioApp> createState() => _InventarioAppState();
}

class _InventarioAppState extends ConsumerState<InventarioApp> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _cambiosDeSesion;
  Timer? _inactividad;
  String? _registradoPara;
  final _mensajes = GlobalKey<ScaffoldMessengerState>();
  int _porEnviar = ColaSinConexion.instancia?.porEnviar.length ?? 0;
  int _porResolver = ColaSinConexion.instancia?.porResolver.length ?? 0;
  int _enviados = ColaSinConexion.instancia?.enviados.length ?? 0;

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
    WidgetsBinding.instance.addObserver(this);
    ColaSinConexion.instancia?.addListener(_alCambiarCola);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) ColaSinConexion.instancia?.alReanudar();
  }

  /// Avisos de la cola: lo que se guardó sin señal, lo que se envió con conflicto y lo que no se pudo aplicar.
  void _alCambiarCola() {
    final cola = ColaSinConexion.instancia!;
    final mensajes = _mensajes.currentState;
    if (cola.porEnviar.length > _porEnviar) {
      mensajes?.showSnackBar(const SnackBar(
          content: Text('Sin señal: quedó guardado en este celular y se enviará solo al volver la conexión.'), duration: Duration(seconds: 6)));
    }
    if (cola.porResolver.length > _porResolver) {
      mensajes?.showSnackBar(SnackBar(
        content: const Text('Algo capturado sin señal no se pudo aplicar. Revísalo.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Ver', onPressed: () => ref.read(rutasProvider).push('/sin-conexion')),
      ));
    }
    if (cola.enviados.length > _enviados) {
      final nuevos = cola.enviados.take(cola.enviados.length - _enviados).toList();
      final conflictos = nuevos.where((e) => e.conflicto != null).length;
      mensajes?.showSnackBar(SnackBar(
        content: Text(conflictos == 0
            ? 'Se envió lo capturado sin señal (${nuevos.length}).'
            : 'Se envió lo capturado sin señal. $conflictos con conflicto: el responsable va a revisar el conteo.'),
        duration: const Duration(seconds: 6),
      ));
      ref.invalidate(articulosProvider);
      ref.invalidate(pendientesAbiertosProvider);
    }
    _porEnviar = cola.porEnviar.length;
    _porResolver = cola.porResolver.length;
    _enviados = cola.enviados.length;
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
    WidgetsBinding.instance.removeObserver(this);
    ColaSinConexion.instancia?.removeListener(_alCambiarCola);
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
        darkTheme: temaOscuro(),
        themeMode: ref.watch(modoTemaProvider),
        routerConfig: ref.watch(rutasProvider),
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
