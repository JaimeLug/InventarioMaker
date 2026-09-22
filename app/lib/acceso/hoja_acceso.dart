import '../ui/diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../datos/errores.dart';
import '../datos/repositorio.dart';
import '../modelos/otros.dart';

const _recientes = 'pin_recientes';

/// Hoja de acceso (F-02). Se abre encima del formulario: lo capturado no se toca.
/// Devuelve true si se abrió sesión.
Future<bool> pedirAcceso(
  BuildContext context, {
  required String descripcion,
  bool soloContrasena = false,
  String? aviso,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HojaAcceso(descripcion: descripcion, soloContrasena: soloContrasena, aviso: aviso),
  );
  return r == true;
}

/// Reconfirmar la contraseña para una acción grave (N3). Devuelve true si quedó confirmada.
Future<bool> pedirConfirmacion(BuildContext context, {required String descripcion}) async {
  final r = await showDialog<bool>(context: context, builder: (_) => _DialogoConfirmar(descripcion: descripcion));
  return r == true;
}

class _HojaAcceso extends StatelessWidget {
  const _HojaAcceso({required this.descripcion, required this.soloContrasena, this.aviso});

  final String descripcion;
  final bool soloContrasena;
  final String? aviso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final encabezado = Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Identifícate para continuar', style: tema.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Vas a $descripcion.', style: tema.textTheme.bodyLarge),
          if (aviso != null) ...[
            const SizedBox(height: 8),
            Text(aviso!, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.primary)),
          ],
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: soloContrasena
            ? SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [encabezado, const _FormularioContrasena()]))
            : DefaultTabController(
                length: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    encabezado,
                    const TabBar(tabs: [Tab(icon: Icon(Ico.pin), text: 'PIN'), Tab(icon: Icon(Ico.contrasena), text: 'Contraseña')]),
                    const Flexible(child: TabBarView(children: [_FormularioPin(), SingleChildScrollView(child: _FormularioContrasena())])),
                  ],
                ),
              ),
      ),
    );
  }
}

// --- PIN: elegir nombre y teclear en un teclado grande ------------------------------------
class _FormularioPin extends ConsumerStatefulWidget {
  const _FormularioPin();

  @override
  ConsumerState<_FormularioPin> createState() => _FormularioPinState();
}

class _FormularioPinState extends ConsumerState<_FormularioPin> {
  late final Future<List<PersonaPin>> _personas = _cargar();
  PersonaPin? _elegida;
  String _pin = '';
  String? _error;
  bool _enviando = false;

  Future<List<PersonaPin>> _cargar() async {
    final personas = await ref.read(repositorioProvider).personasConPin();
    final prefs = await SharedPreferences.getInstance();
    final recientes = prefs.getStringList(_recientes) ?? const [];
    personas.sort((a, b) {
      final ra = recientes.indexOf(a.id), rb = recientes.indexOf(b.id);
      if (ra >= 0 || rb >= 0) return (ra < 0 ? 999 : ra).compareTo(rb < 0 ? 999 : rb);
      return a.nombre.compareTo(b.nombre);
    });
    return personas;
  }

  Future<void> _entrar() async {
    final persona = _elegida;
    if (persona == null || _pin.length < 4) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(repositorioProvider).entrarConPin(persona.id, _pin);
      final prefs = await SharedPreferences.getInstance();
      final recientes = [persona.id, ...(prefs.getStringList(_recientes) ?? const []).where((i) => i != persona.id)];
      await prefs.setStringList(_recientes, recientes.take(8).toList());
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = traducir(e).mensaje;
          _pin = '';
          _enviando = false;
        });
      }
    }
  }

  void _tecla(String t) {
    if (_enviando) return;
    setState(() {
      _error = null;
      if (t == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += t;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return FutureBuilder<List<PersonaPin>>(
      future: _personas,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text(traducir(snap.error!).mensaje));
        final personas = snap.data!;
        if (personas.isEmpty) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Todavía nadie tiene PIN. Entra con contraseña y asígnalo desde "Mi cuenta".', textAlign: TextAlign.center),
          ));
        }

        if (_elegida == null) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 4), child: Text('¿Quién eres?')),
              for (final p in personas)
                ListTile(
                  leading: CircleAvatar(child: Text(p.nombre.characters.first)),
                  title: Text(p.nombre),
                  onTap: () => setState(() => _elegida = p),
                ),
            ],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Row(children: [
                Expanded(child: Text(_elegida!.nombre, style: tema.textTheme.titleMedium)),
                TextButton(onPressed: () => setState(() => [_elegida = null, _pin = '', _error = null]), child: const Text('No soy yo')),
              ]),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 6; i++)
                    Container(
                      margin: const EdgeInsets.all(6),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? tema.colorScheme.primary : null,
                        border: Border.all(color: i < 4 ? tema.colorScheme.outline : tema.colorScheme.outlineVariant),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 48,
                child: Center(
                  child: _enviando
                      ? const CircularProgressIndicator()
                      : Text(_error ?? '', textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.error)),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.6,
                  children: [
                    for (final t in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0'])
                      FilledButton.tonal(
                        onPressed: () => _tecla(t),
                        child: Text(t, style: tema.textTheme.headlineSmall),
                      ),
                    FilledButton(
                      onPressed: _pin.length >= 4 && !_enviando ? _entrar : null,
                      child: const Icon(Ico.avanzarFlecha, size: 32),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Contraseña ----------------------------------------------------------------------------
class _FormularioContrasena extends ConsumerStatefulWidget {
  const _FormularioContrasena();

  @override
  ConsumerState<_FormularioContrasena> createState() => _FormularioContrasenaState();
}

class _FormularioContrasenaState extends ConsumerState<_FormularioContrasena> {
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  String? _error;
  bool _enviando = false;
  bool _ver = false;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_correo.text.trim().isEmpty || _contrasena.text.isEmpty) {
      setState(() => _error = 'Escribe tu correo y tu contraseña.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(repositorioProvider).entrarConContrasena(_correo.text, _contrasena.text);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = traducir(e).mensaje;
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _correo,
              decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Ico.correo)),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contrasena,
              obscureText: !_ver,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Ico.noSePresta),
                suffixIcon: IconButton(
                  tooltip: _ver ? 'Ocultar' : 'Mostrar',
                  icon: Icon(_ver ? Ico.ocultar : Ico.ver),
                  onPressed: () => setState(() => _ver = !_ver),
                ),
              ),
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _entrar(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _enviando ? null : _entrar,
              child: _enviando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Reconfirmar contraseña (N3) ------------------------------------------------------------
class _DialogoConfirmar extends ConsumerStatefulWidget {
  const _DialogoConfirmar({required this.descripcion});

  final String descripcion;

  @override
  ConsumerState<_DialogoConfirmar> createState() => _DialogoConfirmarState();
}

class _DialogoConfirmarState extends ConsumerState<_DialogoConfirmar> {
  final _contrasena = TextEditingController();
  String? _error;
  bool _enviando = false;

  @override
  void dispose() {
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_contrasena.text.isEmpty) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final problema = await ref.read(repositorioProvider).confirmarContrasena(_contrasena.text);
      if (!mounted) return;
      if (problema == null) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = problema;
          _enviando = false;
          _contrasena.clear();
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = traducir(e).mensaje;
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirma tu contraseña'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vas a ${widget.descripcion}. Es una acción que queda firmada con tu nombre.'),
          const SizedBox(height: 16),
          TextField(
            controller: _contrasena,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            onSubmitted: (_) => _confirmar(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _enviando ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _enviando ? null : _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}
