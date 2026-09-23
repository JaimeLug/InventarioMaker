import '../armazon.dart';
import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/errores.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/otros.dart';
import '../../util/texto.dart';
import '../tema.dart';
import 'mi_cuenta_pantalla.dart';

/// Administración de cuentas: solo responsable (cuentas de docentes) y sub administración (todas).
class CuentasPantalla extends ConsumerStatefulWidget {
  const CuentasPantalla({super.key});

  @override
  ConsumerState<CuentasPantalla> createState() => _CuentasPantallaState();
}

class _CuentasPantallaState extends ConsumerState<CuentasPantalla> {
  List<Cuenta>? _cuentas;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final cuentas = await conAcceso(
        context,
        ref,
        descripcion: 'ver las cuentas',
        requisito: Requisito.administracion,
        accion: () => ref.read(repositorioProvider).cuentas(),
      );
      if (mounted) setState(() => cuentas == null ? _error = 'Se necesita identificarse para ver las cuentas.' : _cuentas = cuentas);
    } on Object catch (e) {
      if (mounted) setState(() => _error = traducir(e).mensaje);
    }
  }

  Future<void> _administrar(String descripcion, Map<String, dynamic> solicitud, String exito) async {
    try {
      final hecho = await conAcceso<bool>(
        context,
        ref,
        descripcion: descripcion,
        requisito: Requisito.administracionConfirmada,
        accion: () async {
          await ref.read(repositorioProvider).administrarCuenta(solicitud);
          return true;
        },
      );
      if (hecho == true && mounted) {
        avisar(context, exito);
        await _cargar();
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _nueva(Sesion yo) async {
    final datos = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DialogoNuevaCuenta(yo: yo));
    if (datos == null) return;
    await _administrar('crear la cuenta de ${datos['nombre']}', {'accion': 'CREAR', ...datos}, 'Cuenta creada. Asígnale un PIN para que entre en el taller.');
  }

  Future<void> _contrasena(Cuenta c) async {
    final controlador = TextEditingController();
    final nueva = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Contraseña nueva para ${c.nombre}'),
        content: TextField(controller: controlador, decoration: const InputDecoration(labelText: 'Al menos 8 caracteres')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controlador.text), child: const Text('Continuar')),
        ],
      ),
    );
    controlador.dispose();
    if (nueva == null || nueva.length < 8) {
      if (nueva != null && mounted) avisar(context, 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    await _administrar('cambiar la contraseña de ${c.nombre}', {'accion': 'CONTRASENA', 'usuario_id': c.id, 'contrasena': nueva},
        'Contraseña cambiada. Entrégasela en persona.');
  }

  @override
  Widget build(BuildContext context) {
    final yo = ref.watch(sesionProvider).value;
    return TmArmazon(
      ruta: '/cuentas',
      titulo: 'Cuentas',
      fab: yo != null && yo.administra && _cuentas != null
          ? FloatingActionButton.extended(onPressed: () => _nueva(yo), icon: const Icon(Ico.cuentas), label: const Text('Nueva cuenta'))
          : null,
      child: Centrado(
        child: _cuentas == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
                      ]),
              )
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                  for (final c in _cuentas!)
                    ListTile(
                      leading: CircleAvatar(child: Icon(c.activo ? Ico.persona : Ico.personaInactiva)),
                      title: Text(c.nombre, style: c.activo ? null : const TextStyle(decoration: TextDecoration.lineThrough)),
                      subtitle: Text([
                        c.rol.nombre,
                        c.correo ?? 'Sin correo: solo PIN',
                        if (!c.activo) 'Desactivada',
                        if (c.pinBloqueadoHasta != null && c.pinBloqueadoHasta!.isAfter(DateTime.now()))
                          'PIN bloqueado hasta las ${hora(c.pinBloqueadoHasta!)}'
                        else
                          c.tienePin ? 'Con PIN' : 'Sin PIN',
                      ].join(' · ')),
                      trailing: yo == null || c.id == yo.id || (yo.rol == Rol.responsable && c.rol != Rol.docente && c.rol != Rol.seleccion)
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (opcion) => switch (opcion) {
                                'pin' => cambiarPin(context, ref, usuarioId: c.id, nombre: c.nombre).then((_) => _cargar()),
                                'contrasena' => _contrasena(c),
                                'desactivar' => _administrar('desactivar la cuenta de ${c.nombre}',
                                    {'accion': 'DESACTIVAR', 'usuario_id': c.id}, 'Cuenta desactivada.'),
                                _ => _administrar('reactivar la cuenta de ${c.nombre}',
                                    {'accion': 'REACTIVAR', 'usuario_id': c.id}, 'Cuenta reactivada.'),
                              },
                              itemBuilder: (_) => [
                                if (c.activo && c.rol != Rol.seleccion) const PopupMenuItem(value: 'pin', child: Text('Asignar PIN')),
                                if (c.activo && c.correo != null) const PopupMenuItem(value: 'contrasena', child: Text('Cambiar contraseña')),
                                PopupMenuItem(value: c.activo ? 'desactivar' : 'reactivar', child: Text(c.activo ? 'Desactivar' : 'Reactivar')),
                              ],
                            ),
                    ),
                ]),
              ),
      ),
    );
  }
}

class _DialogoNuevaCuenta extends StatefulWidget {
  const _DialogoNuevaCuenta({required this.yo});

  final Sesion yo;

  @override
  State<_DialogoNuevaCuenta> createState() => _DialogoNuevaCuentaState();
}

class _DialogoNuevaCuentaState extends State<_DialogoNuevaCuenta> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  final _matricula = TextEditingController();
  final _nombreAlumno = TextEditingController();
  final _grupo = TextEditingController();
  Rol _rol = Rol.docente;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _contrasena.dispose();
    _matricula.dispose();
    _nombreAlumno.dispose();
    _grupo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.yo.rol == Rol.subadmin ? Rol.values : const [Rol.docente, Rol.seleccion];
    return AlertDialog(
      title: const Text('Nueva cuenta'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre completo *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.trim().length < 3 ? 'Escribe el nombre.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Rol>(
              value: _rol,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r.nombre))],
              onChanged: (r) => setState(() => _rol = r ?? Rol.docente),
            ),
            if (_rol == Rol.seleccion) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _matricula,
                decoration: const InputDecoration(
                  labelText: 'Matrícula del alumno *',
                  helperText: 'Vincula la cuenta a su ficha de alumno para pedir material.',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => _rol == Rol.seleccion && (v == null || v.trim().isEmpty)
                    ? 'Escribe la matrícula del alumno.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreAlumno,
                decoration: const InputDecoration(
                  labelText: 'Nombre del alumno en la ficha',
                  helperText: 'Opcional. Si se deja vacío, se usa el nombre completo de arriba.',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _grupo,
                decoration: const InputDecoration(
                  labelText: 'Grupo / área',
                  helperText: 'Opcional (ej: 4-B, FTC, VEX).',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _correo,
              decoration: InputDecoration(
                labelText: _rol == Rol.seleccion ? 'Correo institucional *' : 'Correo',
                helperText: _rol == Rol.seleccion
                    ? 'La selección de robótica entra solo con su correo y su contraseña, sin PIN.'
                    : 'Opcional. Sin correo, solo entra con PIN.',
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final correo = (v ?? '').trim();
                if (_rol == Rol.seleccion && correo.isEmpty) return 'La selección de robótica necesita su correo.';
                if (correo.isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correo)) return null;
                return 'El correo no parece válido.';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contrasena,
              decoration: const InputDecoration(labelText: 'Contraseña inicial', helperText: 'Al menos 8 caracteres. Entrégala en persona.'),
              validator: (v) {
                final conCorreo = _correo.text.trim().isNotEmpty;
                if (conCorreo && (v == null || v.length < 8)) return 'Con correo, escribe una contraseña de 8 o más.';
                if (!conCorreo && v != null && v.isNotEmpty && v.length < 8) return 'Al menos 8 caracteres.';
                return null;
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'nombre': _nombre.text.trim(),
              'rol': _rol.codigo,
              if (_correo.text.trim().isNotEmpty) 'correo': _correo.text.trim(),
              if (_contrasena.text.isNotEmpty) 'contrasena': _contrasena.text,
              if (_rol == Rol.seleccion) ...{
                'matricula': _matricula.text.trim(),
                if (_nombreAlumno.text.trim().isNotEmpty) 'nombre_alumno': _nombreAlumno.text.trim(),
                if (_grupo.text.trim().isNotEmpty) 'grupo': _grupo.text.trim(),
              },
            });
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
