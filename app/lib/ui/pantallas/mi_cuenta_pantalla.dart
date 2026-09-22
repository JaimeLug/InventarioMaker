import '../diseno/iconos.dart';
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
                  ListTile(leading: const Icon(Ico.persona), title: Text(s.nombre), subtitle: Text(s.rol.nombre)),
                  ListTile(
                    leading: const Icon(Ico.diseno),
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
                    leading: Icon(s.nivel == NivelSesion.pin ? Ico.pin : Ico.conContrasena),
                    title: Text(s.nivel == NivelSesion.pin ? 'Entraste con PIN' : 'Entraste con contraseña'),
                    subtitle: Text(s.nivel == NivelSesion.pin
                        ? 'Puedes hacer acciones de docente. Para acciones de administración entra con contraseña.'
                        : 'Puedes hacer todo lo que permite tu cuenta.'),
                  ),
                  if (s.expiraEn != null)
                    ListTile(leading: const Icon(Ico.reloj), title: Text('La sesión termina a las ${hora(s.expiraEn!)}')),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Ico.conteo),
                    title: Text(s.tienePin ? 'Cambiar mi PIN' : 'Crear mi PIN'),
                    subtitle: const Text('Para entrar rápido en el taller.'),
                    onTap: () => cambiarPin(context, ref, usuarioId: s.id, nombre: 'tu'),
                  ),
                  ListTile(
                    leading: const Icon(Ico.contrasena),
                    title: const Text('Cambiar mi contraseña'),
                    subtitle: const Text('La contraseña es para los movimientos mayores: dar de baja, ajustar conteos, aprobar solicitudes y entregas.'),
                    isThreeLine: true,
                    onTap: () => cambiarMiContrasena(context, ref),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Ico.salir),
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

/// Cambiar la propia contraseña: se pide la actual y la nueva dos veces.
Future<void> cambiarMiContrasena(BuildContext context, WidgetRef ref) async {
  final datos = await showDialog<(String, String)>(context: context, builder: (_) => const _DialogoContrasena());
  if (datos == null || !context.mounted) return;
  try {
    await ref.read(repositorioProvider).cambiarMiContrasena(datos.$1, datos.$2);
    if (context.mounted) avisar(context, 'Contraseña cambiada. Úsala la próxima vez que entres.');
  } on Object catch (e) {
    if (context.mounted) avisarError(context, e);
  }
}

class _DialogoContrasena extends StatefulWidget {
  const _DialogoContrasena();

  @override
  State<_DialogoContrasena> createState() => _DialogoContrasenaState();
}

class _DialogoContrasenaState extends State<_DialogoContrasena> {
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_actual, _nueva, _repetir]) {
      c.dispose();
    }
    super.dispose();
  }

  void _aceptar() {
    final nueva = _nueva.text;
    if (_actual.text.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña actual.');
    } else if (nueva.length < 8) {
      setState(() => _error = 'La contraseña nueva debe tener al menos 8 letras o números.');
    } else if (nueva != _repetir.text) {
      setState(() => _error = 'Las dos contraseñas nuevas no coinciden.');
    } else {
      Navigator.pop(context, (_actual.text, nueva));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cambiar mi contraseña'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Con la contraseña se hacen los movimientos mayores: dar de baja, ajustar conteos, '
              'aprobar solicitudes y entregar material. El PIN es solo para el día a día en el taller.'),
          const SizedBox(height: 16),
          TextField(controller: _actual, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
          const SizedBox(height: 12),
          TextField(
            controller: _nueva,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña nueva', helperText: 'Al menos 8 letras o números'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _repetir, obscureText: true, decoration: const InputDecoration(labelText: 'Repite la nueva')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _aceptar, child: const Text('Guardar')),
        ],
      );
}
