import '../armazon.dart';
import '../componentes/componentes.dart';
import '../componentes/campo.dart';
import '../diseno/modo_tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/hoja_acceso.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../util/texto.dart';
import '../tema.dart';

class MiCuentaPantalla extends ConsumerWidget {
  const MiCuentaPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    return TmArmazon(
      ruta: '/mi-cuenta',
      titulo: 'Mi cuenta',
      conRegresar: true,
      child: Centrado(
        child: sesion.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('No se pudo leer la sesión.')),
          data: (s) => s == null
              ? Center(
                  child: FilledButton(
                    onPressed: () async {
                      if (await pedirAcceso(context, descripcion: 'entrar a tu cuenta')) ref.invalidate(sesionProvider);
                    },
                    child: const Text('Entrar'),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  ListTile(leading: const Icon(Icons.person), title: Text(s.nombre), subtitle: Text(s.rol.nombre)),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Apariencia'),
                    subtitle: Text('Tema: ${ModoTema.nombre(ref.watch(modoTemaProvider))}'),
                    trailing: TmSegmento<ThemeMode>(
                      valor: ref.watch(modoTemaProvider),
                      opciones: const [
                        (ThemeMode.light, 'Claro', null),
                        (ThemeMode.dark, 'Oscuro', null),
                        (ThemeMode.system, 'Auto', null),
                      ],
                      onCambio: (m) => ref.read(modoTemaProvider.notifier).cambiar(m),
                    ),
                  ),
                  ListTile(
                    leading: Icon(s.nivel == NivelSesion.pin ? Icons.dialpad : Icons.verified_user_outlined),
                    title: Text(s.nivel == NivelSesion.pin ? 'Entraste con PIN' : 'Entraste con contraseña'),
                    subtitle: Text(s.nivel == NivelSesion.pin
                        ? 'Puedes hacer acciones de docente. Para acciones de administración entra con contraseña.'
                        : 'Puedes hacer todo lo que permite tu cuenta.'),
                  ),
                  if (s.expiraEn != null)
                    ListTile(leading: const Icon(Icons.schedule), title: Text('La sesión termina a las ${hora(s.expiraEn!)}')),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: Text(s.tienePin ? 'Cambiar mi PIN' : 'Crear mi PIN'),
                    subtitle: const Text('Para entrar rápido en el taller.'),
                    onTap: () => cambiarPin(context, ref, usuarioId: s.id, nombre: 'tu'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Cerrar sesión'),
                    onTap: () async {
                      await ref.read(repositorioProvider).salir();
                      ref.invalidate(sesionProvider);
                      if (context.mounted) context.go('/');
                    },
                  ),
                ]),
        ),
      ),
    );
  }
}

/// Pide un PIN nuevo dos veces y lo guarda con contraseña reconfirmada (N3).
Future<void> cambiarPin(BuildContext context, WidgetRef ref, {required String usuarioId, required String nombre}) async {
  final pin = await showDialog<String>(context: context, builder: (_) => const _DialogoPin());
  if (pin == null || !context.mounted) return;
  try {
    final hecho = await conAcceso<bool>(
      context,
      ref,
      descripcion: nombre == 'tu' ? 'cambiar tu PIN' : 'asignar el PIN de $nombre',
      requisito: nombre == 'tu' ? Requisito.propiaConfirmada : Requisito.administracionConfirmada,
      accion: () async {
        await ref.read(repositorioProvider).establecerPin(usuarioId, pin);
        return true;
      },
    );
    if (hecho == true && context.mounted) {
      ref.invalidate(sesionProvider);
      avisar(context, 'PIN guardado.');
    }
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}

class _DialogoPin extends StatefulWidget {
  const _DialogoPin();

  @override
  State<_DialogoPin> createState() => _DialogoPinState();
}

class _DialogoPinState extends State<_DialogoPin> {
  final _pin = TextEditingController();
  final _repetir = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _repetir.dispose();
    super.dispose();
  }

  void _aceptar() {
    final p = _pin.text;
    String? error;
    if (!RegExp(r'^\d{4,6}$').hasMatch(p)) {
      error = 'El PIN debe tener de 4 a 6 números.';
    } else if (RegExp(r'^(\d)\1+$').hasMatch(p)) {
      error = 'No uses el mismo número repetido.';
    } else if ('01234567890123456'.contains(p) || '98765432109876543'.contains(p)) {
      error = 'No uses una secuencia como 1234.';
    } else if (p != _repetir.text) {
      error = 'Los dos PIN no coinciden.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration campo(String etiqueta) => InputDecoration(labelText: etiqueta, counterText: '');
    return AlertDialog(
      title: const Text('PIN nuevo'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _pin,
          obscureText: true,
          autofocus: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: campo('De 4 a 6 números'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _repetir,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: campo('Repítelo'),
          onSubmitted: (_) => _aceptar(),
        ),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Continuar')),
      ],
    );
  }
}
