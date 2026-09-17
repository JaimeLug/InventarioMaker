import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/errores.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

enum _ParaQuien { yo, persona }

/// Préstamo directo (F-07). Ruta corta: para mí, hoy al final de la jornada → Prestar.
class PrestamoPantalla extends ConsumerStatefulWidget {
  const PrestamoPantalla({super.key, this.articuloId, this.lineas = const {}});

  final String? articuloId;

  /// Varios artículos con su cantidad (al prestar desde un contenedor).
  final Map<String, int> lineas;

  @override
  ConsumerState<PrestamoPantalla> createState() => _PrestamoPantallaState();
}

class _Linea {
  _Linea(this.articulo);

  final Articulo articulo;
  int cantidad = 1;
}

class _PrestamoPantallaState extends ConsumerState<PrestamoPantalla> {
  final _comando = const Uuid().v4();   // reintentar no duplica
  final _lineas = <_Linea>[];
  final _nota = TextEditingController();
  _ParaQuien _para = _ParaQuien.yo;
  SolicitanteEncontrado? _persona;
  bool _hoy = true;
  DateTime? _fecha;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    ref.read(articulosProvider.future).then((todos) {
      if (!mounted) return;
      final pedidos = {if (widget.articuloId != null) widget.articuloId!: 1, ...widget.lineas};
      setState(() {
        for (final a in todos.where((x) => pedidos.containsKey(x.id) && x.prestable && x.disponible > 0)) {
          _lineas.add(_Linea(a)..cantidad = pedidos[a.id]!.clamp(1, a.disponible));
        }
      });
    });
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _agregarArticulo() async {
    final todos = await ref.read(articulosProvider.future);
    if (!mounted) return;
    final ya = _lineas.map((l) => l.articulo.id).toSet();
    final elegido = await showModalBottomSheet<Articulo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BuscarArticulo(opciones: todos.where((a) => a.prestable && a.disponible > 0 && !ya.contains(a.id)).toList()),
    );
    if (elegido != null) setState(() => _lineas.add(_Linea(elegido)));
  }

  Future<void> _prestar() async {
    if (_lineas.isEmpty) return;
    if (_para == _ParaQuien.persona && _persona == null) {
      avisar(context, 'Busca a la persona por su matrícula.');
      return;
    }
    if (_persona?.bloqueado ?? false) {
      avisar(context, '${_persona!.nombre} tiene material pendiente de devolver.');
      return;
    }
    if (!_hoy && _fecha == null) {
      avisar(context, 'Elige la fecha de devolución.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final contenedor = ProviderScope.containerOf(context);
    final repo = ref.read(repositorioProvider);
    final piezas = _lineas.fold<int>(0, (s, l) => s + l.cantidad);
    setState(() => _guardando = true);
    try {
      final grupo = await conAcceso<String>(
        context,
        ref,
        descripcion: 'prestar ${_lineas.length == 1 ? '"${_lineas.first.articulo.nombre}"' : '${_lineas.length} artículos'}',
        requisito: Requisito.docente,
        accion: () async {
          final sesion = await ref.read(sesionProvider.future);
          return repo.prestar(
            lineas: [for (final l in _lineas) (articuloId: l.articulo.id, cantidad: l.cantidad)],
            comando: _comando,
            responsableUsuario: _para == _ParaQuien.yo ? sesion!.id : null,
            responsableSolicitante: _persona?.id,
            fechaCompromiso: _hoy ? null : _fecha,
            nota: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
          );
        },
      );
      if (grupo == null || !mounted) return;
      for (final l in _lineas) {
        refrescarArticuloEn(contenedor, l.articulo.id);
      }
      context.pop();
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('Préstamo registrado: $piezas pieza${piezas == 1 ? '' : 's'}'
            '${_persona == null ? '' : ' a nombre de ${_persona!.nombre}'}.'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            try {
              await repo.deshacerPrestamo(grupo);
              for (final l in _lineas) {
                refrescarArticuloEn(contenedor, l.articulo.id);
              }
              messenger.showSnackBar(const SnackBar(content: Text('Préstamo deshecho.')));
            } on Object catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(traducir(e).mensaje)));
            }
          },
        ),
      ));
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Prestar'), actions: const [BarraSesion()]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _guardando || _lineas.isEmpty ? null : _prestar,
            icon: _guardando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.outbox),
            label: const Text('Prestar'),
          ),
        ),
      ),
      body: Centrado(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Qué se lleva', style: tema.textTheme.titleMedium),
          if (_lineas.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          for (final l in _lineas)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Miniatura(ruta: l.articulo.fotoPrincipal, tamano: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.articulo.nombre, style: tema.textTheme.titleSmall),
                      Text('${l.articulo.codigo} · ${l.articulo.disponibilidad}', style: tema.textTheme.bodySmall),
                    ]),
                  ),
                  SelectorCantidad(
                    valor: l.cantidad,
                    minimo: 1,
                    maximo: l.articulo.disponible,
                    alCambiar: (v) => setState(() => l.cantidad = v),
                  ),
                  if (_lineas.length > 1)
                    IconButton(icon: const Icon(Icons.close), tooltip: 'Quitar', onPressed: () => setState(() => _lineas.remove(l))),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _agregarArticulo, icon: const Icon(Icons.add), label: const Text('Agregar otro artículo')),
          ),
          const SizedBox(height: 16),
          Text('Para quién', style: tema.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<_ParaQuien>(
            segments: const [
              ButtonSegment(value: _ParaQuien.yo, icon: Icon(Icons.person), label: Text('Para mí')),
              ButtonSegment(value: _ParaQuien.persona, icon: Icon(Icons.school_outlined), label: Text('Alumno o maestro')),
            ],
            selected: {_para},
            onSelectionChanged: (s) => setState(() {
              _para = s.first;
              if (_para == _ParaQuien.yo) _persona = null;
            }),
          ),
          if (_para == _ParaQuien.persona)
            _BuscarPersona(elegida: _persona, alElegir: (p) => setState(() => _persona = p)),
          const SizedBox(height: 16),
          Text('Hasta cuándo', style: tema.textTheme.titleMedium),
          RadioListTile<bool>(
            value: true,
            groupValue: _hoy,
            onChanged: (_) => setState(() => _hoy = true),
            title: const Text('Hoy, al final de la jornada'),
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<bool>(
            value: false,
            groupValue: _hoy,
            onChanged: (_) async {
              final f = await elegirFechaDevolucion(context);
              if (f != null) setState(() => [_hoy = false, _fecha = f]);
            },
            title: Text(_fecha == null || _hoy ? 'Otra fecha' : 'El ${fecha(_fecha!)}'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nota,
            decoration: const InputDecoration(labelText: 'Para qué (opcional)', hintText: 'Ej. Práctica de electrónica 5°B'),
            textCapitalization: TextCapitalization.sentences,
          ),
        ]),
      ),
    );
  }
}

/// Buscador de artículos disponibles (préstamo directo y "Mi solicitud").
class BuscarArticulo extends StatefulWidget {
  const BuscarArticulo({super.key, required this.opciones});

  final List<Articulo> opciones;

  @override
  State<BuscarArticulo> createState() => _BuscarArticuloState();
}

class _BuscarArticuloState extends State<BuscarArticulo> {
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    final palabras = normalizar(_texto).split(' ').where((p) => p.isNotEmpty);
    final lista = widget.opciones.where((a) => palabras.every(a.textoBusqueda.contains)).take(50).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar artículo disponible'),
              onChanged: (t) => setState(() => _texto = t),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final a in lista)
                ListTile(
                  leading: Miniatura(ruta: a.fotoPrincipal, tamano: 40),
                  title: Text(a.nombre),
                  subtitle: Text('${a.codigo} · ${a.disponibilidad}'),
                  onTap: () => Navigator.pop(context, a),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Búsqueda por matrícula exacta y ficha rápida (F-07, F-04b).
class _BuscarPersona extends ConsumerStatefulWidget {
  const _BuscarPersona({required this.elegida, required this.alElegir});

  final SolicitanteEncontrado? elegida;
  final ValueChanged<SolicitanteEncontrado?> alElegir;

  @override
  ConsumerState<_BuscarPersona> createState() => _BuscarPersonaState();
}

class _BuscarPersonaState extends ConsumerState<_BuscarPersona> {
  final _matricula = TextEditingController();
  List<SolicitanteEncontrado>? _resultados;
  bool _buscando = false;

  @override
  void dispose() {
    _matricula.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final m = _matricula.text.trim();
    if (m.isEmpty) return;
    setState(() => _buscando = true);
    try {
      final r = await conAcceso(
        context,
        ref,
        descripcion: 'buscar a un alumno o maestro',
        requisito: Requisito.docente,
        accion: () => ref.read(repositorioProvider).buscarSolicitante(m),
      );
      if (!mounted || r == null) return;
      setState(() => _resultados = r);
      if (r.length == 1) widget.alElegir(r.first);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _crear() async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoFicha(matricula: _matricula.text.trim()),
    );
    if (datos == null || !mounted) return;
    try {
      final id = await conAcceso(
        context,
        ref,
        descripcion: 'registrar a ${datos['nombre']}',
        requisito: Requisito.docente,
        accion: () => ref.read(repositorioProvider).crearSolicitante(
              nombre: datos['nombre'] as String,
              tipo: datos['tipo'] as TipoSolicitante,
              matricula: datos['matricula'] as String,
              grupo: datos['grupo'] as String,
              correo: datos['correo'] as String,
              telefono: datos['telefono'] as String?,
            ),
      );
      if (id == null || !mounted) return;
      _matricula.text = datos['matricula'] as String;
      await _buscar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final p = widget.elegida;
    if (p != null) {
      return Card(
        margin: const EdgeInsets.only(top: 12),
        color: p.bloqueado ? tema.colorScheme.errorContainer : null,
        child: ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(p.nombre),
          subtitle: Text([
            p.tipo.nombre,
            if (p.grupo != null) p.grupo!,
            if (p.bloqueado) 'Tiene material pendiente: no puede llevarse más',
            if (!p.bloqueado && p.vencidos > 0) '${p.vencidos} préstamo(s) vencido(s)',
          ].join(' · ')),
          trailing: TextButton(onPressed: () => widget.alElegir(null), child: const Text('Cambiar')),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _matricula,
              decoration: const InputDecoration(labelText: 'Matrícula o clave', helperText: 'Se busca por matrícula exacta'),
              onSubmitted: (_) => _buscar(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: _buscando ? null : _buscar, child: const Text('Buscar')),
        ]),
        if (_resultados != null && _resultados!.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No hay nadie registrado con esa matrícula.'),
            trailing: FilledButton(onPressed: _crear, child: const Text('Registrar')),
          ),
        if (_resultados != null && _resultados!.length > 1)
          for (final r in _resultados!)
            ListTile(title: Text(r.nombre), subtitle: Text(r.tipo.nombre), onTap: () => widget.alElegir(r)),
      ]),
    );
  }
}

class _DialogoFicha extends StatefulWidget {
  const _DialogoFicha({required this.matricula});

  final String matricula;

  @override
  State<_DialogoFicha> createState() => _DialogoFichaState();
}

class _DialogoFichaState extends State<_DialogoFicha> {
  final _form = GlobalKey<FormState>();
  late final _matricula = TextEditingController(text: widget.matricula);
  final _nombre = TextEditingController();
  final _grupo = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  TipoSolicitante _tipo = TipoSolicitante.alumno;

  @override
  void dispose() {
    for (final c in [_matricula, _nombre, _grupo, _correo, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alumno = _tipo == TipoSolicitante.alumno;
    return AlertDialog(
      title: const Text('Registrar alumno o maestro'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Lo tienes enfrente: la ficha queda verificada con tu nombre.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<TipoSolicitante>(
              value: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [for (final t in TipoSolicitante.values) DropdownMenuItem(value: t, child: Text(t.nombre))],
              onChanged: (t) => setState(() => _tipo = t ?? TipoSolicitante.alumno),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre completo *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().length < 5 ? 'Escribe el nombre completo.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _matricula,
              decoration: InputDecoration(labelText: alumno ? 'Matrícula *' : 'Clave de empleado *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoria.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _grupo, decoration: InputDecoration(labelText: alumno ? 'Grupo' : 'Área')),
            const SizedBox(height: 12),
            TextFormField(
              controller: _correo,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: alumno ? 'Correo institucional *' : 'Correo', hintText: alumno ? 'nombre@$dominioCorreoAlumnos' : null),
              validator: (v) {
                final c = (v ?? '').trim().toLowerCase();
                if (alumno && !c.endsWith('@$dominioCorreoAlumnos')) return 'Debe terminar en @$dominioCorreoAlumnos';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _telefono, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'tipo': _tipo,
              'nombre': _nombre.text.trim(),
              'matricula': _matricula.text.trim(),
              'grupo': _grupo.text.trim(),
              'correo': _correo.text.trim(),
              'telefono': _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
            });
          },
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
