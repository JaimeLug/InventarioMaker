import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../datos/errores.dart';
import '../../datos/local.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/solicitudes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';
import 'prestamo_pantalla.dart' show BuscarArticulo;

const _avisoPrivacidad =
    'Tus datos (nombre, matrícula o clave, grupo, correo y teléfono) solo los usa el Laboratorio Maker para prestarte '
    'material y saber quién lo tiene. Al recoger, el responsable toma foto de una identificación con foto: solo la ven '
    'el responsable del laboratorio y sub administración, no sale del sistema y se borra al terminar el ciclo escolar '
    'si no debes nada.';

/// "Mi solicitud" (F-04, F-05): carrito, datos de quien pide y envío. Sin cuenta.
class SolicitudPantalla extends ConsumerStatefulWidget {
  const SolicitudPantalla({super.key});

  @override
  ConsumerState<SolicitudPantalla> createState() => _SolicitudPantallaState();
}

class _SolicitudPantallaState extends ConsumerState<SolicitudPantalla> {
  final _form = GlobalKey<FormState>();
  final _matricula = TextEditingController();
  final _nombre = TextEditingController();
  final _grupo = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  final _quien = TextEditingController();
  final _detalle = TextEditingController();
  TipoSolicitante _tipo = TipoSolicitante.alumno;
  String? _motivo;
  DateTime? _fecha;
  bool _privacidad = false;
  bool _compromiso = false;
  bool _guardarAqui = true;
  bool _enviando = false;

  @override
  void dispose() {
    for (final c in [_matricula, _nombre, _grupo, _correo, _telefono, _quien, _detalle]) {
      c.dispose();
    }
    super.dispose();
  }

  int _plazoMaximo(Map<String, dynamic>? config) =>
      (config?[_tipo == TipoSolicitante.maestro ? 'plazo_max_maestro_dias' : 'plazo_max_alumno_dias'] as int?) ??
      (_tipo == TipoSolicitante.maestro ? 30 : 14);

  int _plazoDefault(Map<String, dynamic>? config) => (config?['plazo_default_dias'] as int?) ?? 7;

  Future<void> _agregar() async {
    final todos = await ref.read(articulosProvider.future);
    if (!mounted) return;
    final ya = ref.read(carritoProvider).map((l) => l.articuloId).toSet();
    final elegido = await showModalBottomSheet<Articulo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BuscarArticulo(
          opciones: todos.where((a) => a.prestable && a.disponible > 0 && !a.esConsumible && !ya.contains(a.id)).toList()),
    );
    if (elegido != null) ref.read(carritoProvider.notifier).agregar(elegido);
  }

  Map<String, dynamic> _datos({bool otroCorreo = false}) => {
        'tipo': _tipo.codigo,
        'matricula': _matricula.text.trim(),
        'nombre': _nombre.text.trim(),
        'grupo': _grupo.text.trim(),
        'correo': _correo.text.trim().toLowerCase(),
        'telefono': _telefono.text.trim(),
        'quien': _quien.text.trim(),
        'motivo': _motivo,
        'detalle': _detalle.text.trim(),
        if (_fecha != null) 'fecha': '${_fecha!.year}-${_fecha!.month.toString().padLeft(2, '0')}-${_fecha!.day.toString().padLeft(2, '0')}',
        'lineas': [for (final l in ref.read(carritoProvider)) {'articulo_id': l.articuloId, 'cantidad': l.cantidad}],
        'otro_correo': otroCorreo,
      };

  Future<void> _enviar({bool otroCorreo = false}) async {
    if (!_form.currentState!.validate()) return;
    if (ref.read(carritoProvider).isEmpty) {
      avisar(context, 'Agrega al menos un artículo.');
      return;
    }
    if (!_privacidad || !_compromiso) {
      avisar(context, 'Para enviar, acepta el aviso de privacidad y el compromiso.');
      return;
    }
    setState(() => _enviando = true);
    final repo = ref.read(repositorioProvider);
    try {
      final r = await repo.enviarSolicitud(_datos(otroCorreo: otroCorreo), await AlmacenLocal.dispositivo());
      if (_guardarAqui) {
        await AlmacenLocal.guardarSolicitud(SolicitudGuardada(folio: r.folio, token: r.token, enviadaEn: DateTime.now()));
        ref.invalidate(solicitudesGuardadasProvider);
      }
      if (!mounted) return;
      final otra = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _DialogoEnviada(r, permitirOtroCorreo: !otroCorreo));
      if (!mounted) return;
      if (otra == true) {
        // "Ese no es mi correo": se manda otra vez con los mismos datos, como posible duplicado.
        await _enviar(otroCorreo: true);
        return;
      }
      ref.read(carritoProvider.notifier).vaciar();
      context.go('/s/${r.token}');
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final carrito = ref.watch(carritoProvider);
    final disponibles = {for (final a in ref.watch(articulosProvider).value ?? const <Articulo>[]) a.id: a.disponible};
    final config = ref.watch(configuracionProvider).value;
    final dominio = (config?['dominio_correo_alumnos'] as String?) ?? dominioCorreoAlumnos;
    final alumno = _tipo == TipoSolicitante.alumno;
    final vence = _fecha ?? DateTime.now().add(Duration(days: _plazoDefault(config)));

    return Scaffold(
      appBar: AppBar(title: const Text('Mi solicitud')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _enviando || carrito.isEmpty ? null : _enviar,
            icon: _enviando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Enviar solicitud'),
          ),
        ),
      ),
      body: Centrado(
        child: Form(
          key: _form,
          // Columna y no lista: así se validan también los campos que no están a la vista.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Qué necesitas', style: tema.textTheme.titleMedium),
            if (carrito.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Todavía no agregas nada. Busca en el inventario y toca "Pedir prestado".'),
              ),
            for (final l in carrito)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Miniatura(ruta: l.foto, tamano: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.nombre, style: tema.textTheme.titleSmall),
                        Text('${l.codigo} · ${disponibles[l.articuloId] ?? '…'} disponibles', style: tema.textTheme.bodySmall),
                      ]),
                    ),
                    SelectorCantidad(
                      valor: l.cantidad,
                      minimo: 1,
                      maximo: (disponibles[l.articuloId] ?? l.cantidad).clamp(1, 999),
                      alCambiar: (v) => ref.read(carritoProvider.notifier).cambiarCantidad(l.articuloId, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Quitar',
                      onPressed: () => ref.read(carritoProvider.notifier).quitar(l.articuloId),
                    ),
                  ]),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _agregar, icon: const Icon(Icons.add), label: const Text('Agregar otro artículo')),
            ),
            const SizedBox(height: 16),
            Text('Tus datos', style: tema.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<TipoSolicitante>(
              segments: const [
                ButtonSegment(value: TipoSolicitante.alumno, icon: Icon(Icons.school_outlined), label: Text('Alumno')),
                ButtonSegment(value: TipoSolicitante.maestro, icon: Icon(Icons.co_present_outlined), label: Text('Maestro')),
                ButtonSegment(value: TipoSolicitante.otro, label: Text('Otro')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() {
                _tipo = s.first;
                _fecha = null;
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _matricula,
              decoration: InputDecoration(
                  labelText: alumno ? 'Matrícula *' : (_tipo == TipoSolicitante.maestro ? 'Clave de empleado *' : 'Un dato que te identifique *')),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre completo *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().split(RegExp(r'\s+')).length < 2 ? 'Escribe tu nombre completo.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _grupo,
              decoration: InputDecoration(labelText: alumno ? 'Grupo (ej. 5°B)' : 'Área o academia'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _correo,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: alumno ? 'Correo institucional *' : 'Correo *',
                hintText: alumno ? 'nombre@$dominio' : null,
                helperText: 'Te llega un enlace para confirmar la solicitud.',
              ),
              validator: (v) {
                final c = (v ?? '').trim().toLowerCase();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(c)) return 'Escribe un correo válido.';
                if (alumno && !c.endsWith('@$dominio')) return 'Usa tu correo institucional (@$dominio).';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _telefono, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
            if (_tipo == TipoSolicitante.otro) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _quien,
                decoration: const InputDecoration(labelText: '¿Quién eres? *', hintText: 'Ej. personal de intendencia, visitante'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio.' : null,
              ),
            ],
            const SizedBox(height: 16),
            Text('Para qué y hasta cuándo', style: tema.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _motivo,
              decoration: const InputDecoration(labelText: 'Para qué lo necesitas *'),
              items: [for (final m in motivosSolicitud) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (m) => setState(() => _motivo = m),
              validator: (m) => m == null ? 'Elige una opción.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _detalle,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _motivo == 'Otro' ? 'Cuéntanos para qué *' : 'Detalle (opcional)',
                hintText: _tipo == TipoSolicitante.maestro ? 'Ej. práctica con el grupo 3°A' : 'Ej. robot seguidor de línea',
              ),
              validator: (v) => _motivo == 'Otro' && (v ?? '').trim().isEmpty ? 'Obligatorio.' : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Devolver a más tardar el ${fecha(vence)}'),
              subtitle: Text('Puede ser hasta ${_plazoMaximo(config)} días. El responsable puede ajustarla.'),
              trailing: TextButton(
                onPressed: () async {
                  final f = await elegirFechaDevolucion(context, maxDias: _plazoMaximo(config));
                  if (f != null) setState(() => _fecha = f);
                },
                child: const Text('Cambiar'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: tema.colorScheme.surfaceContainerHighest,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_avisoPrivacidad, style: tema.textTheme.bodySmall)),
            ),
            CheckboxListTile(
              value: _privacidad,
              onChanged: (v) => setState(() => _privacidad = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Leí y acepto el aviso de privacidad.'),
            ),
            CheckboxListTile(
              value: _compromiso,
              onChanged: (v) => setState(() => _compromiso = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Me hago responsable del material. Si se pierde o se daña, queda registrado a mi nombre.'),
            ),
            CheckboxListTile(
              value: _guardarAqui,
              onChanged: (v) => setState(() => _guardarAqui = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Es mi celular: guardar aquí el enlace a mi solicitud.'),
              subtitle: const Text('Desmárcalo en una computadora compartida. El enlace también te llega por correo.'),
            ),
            const SizedBox(height: 80),
          ]),
          ),
        ),
      ),
    );
  }
}

class _DialogoEnviada extends StatelessWidget {
  const _DialogoEnviada(this.r, {required this.permitirOtroCorreo});

  final SolicitudEnviada r;
  final bool permitirOtroCorreo;

  @override
  Widget build(BuildContext context) {
    final texto = r.sinCorreo
        ? 'Tu ficha no tiene correo registrado. Pide al responsable del laboratorio que confirme tu solicitud en persona.'
        : '${r.reconocido ? 'Te reconocimos (${r.iniciales}). ' : ''}'
            'Te enviamos un enlace a ${r.correo}. Ábrelo y toca "Sí, yo lo pedí". '
            'Hasta que lo confirmes, tu solicitud no le llega al responsable. Si no lo ves en unos minutos, revisa la carpeta de correo no deseado (spam).';
    return AlertDialog(
      icon: const Icon(Icons.mark_email_unread_outlined, size: 40),
      title: Text('Folio ${r.folio}'),
      content: Text(texto),
      actions: [
        if (r.reconocido && !r.sinCorreo && permitirOtroCorreo)
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ese no es mi correo')),
        FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Entendido')),
      ],
    );
  }
}

/// Estado de una solicitud con su enlace secreto (F-04 pasos 7 a 10). Sin cuenta.
class EstadoSolicitudPantalla extends ConsumerStatefulWidget {
  const EstadoSolicitudPantalla({super.key, required this.token});

  final String token;

  @override
  ConsumerState<EstadoSolicitudPantalla> createState() => _EstadoSolicitudPantallaState();
}

class _EstadoSolicitudPantallaState extends ConsumerState<EstadoSolicitudPantalla> {
  SolicitudPublica? _s;
  String? _error;
  bool _cargando = true;
  bool _trabajando = false;
  bool _guardada = true;
  Timer? _reloj;
  final _codigo = TextEditingController();
  String? _errorCodigo;

  @override
  void initState() {
    super.initState();
    _cargar();
    AlmacenLocal.solicitudes().then((l) {
      if (mounted) setState(() => _guardada = l.any((x) => x.token == widget.token));
    });
    // Mientras está en curso, se revisa sola: así el alumno ve "aprobada" o "código aceptado" sin recargar.
    _reloj = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_s != null && (_s!.estado.abierta) && !_trabajando) _cargar(silencioso: true);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    try {
      final s = await ref.read(repositorioProvider).solicitudPublica(widget.token);
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = s == null ? 'Este enlace no es válido. Revisa que lo hayas copiado completo.' : null;
      });
    } on Object catch (e) {
      if (mounted && !silencioso) setState(() => _error = traducir(e).mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _hacer(Future<SolicitudPublica> Function(Repositorio r) accion, String listo) async {
    setState(() => _trabajando = true);
    try {
      final s = await accion(ref.read(repositorioProvider));
      if (!mounted) return;
      setState(() => _s = s);
      avisar(context, listo);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<bool> _seguro(String titulo, String texto, String boton) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(boton)),
          ],
        ),
      ) ==
      true;

  Future<void> _canjear() async {
    final codigo = _codigo.text.trim();
    if (codigo.length != 6) {
      setState(() => _errorCodigo = 'El código tiene 6 números.');
      return;
    }
    setState(() {
      _trabajando = true;
      _errorCodigo = null;
    });
    try {
      final error = await ref.read(repositorioProvider).canjearCodigo(widget.token, codigo);
      if (!mounted) return;
      if (error != null) {
        setState(() => _errorCodigo = error);
      } else {
        _codigo.clear();
        await _cargar(silencioso: true);
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        // Abierta desde el enlace del correo no hay a dónde regresar: se ofrece ir al inventario.
        leading: context.canPop() ? null : IconButton(icon: const Icon(Icons.home_outlined), tooltip: 'Inventario', onPressed: () => context.go('/')),
        title: Text(s == null ? 'Mi solicitud' : 'Solicitud ${s.folio}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: Centrado(
        child: s == null
            ? Center(
                child: _cargando
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error ?? '', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: () => context.go('/mis-solicitudes'), child: const Text('Mis solicitudes')),
                        ]),
                      ),
              )
            : RefreshIndicator(onRefresh: _cargar, child: _contenido(context, s)),
      ),
    );
  }

  Widget _contenido(BuildContext context, SolicitudPublica s) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _LineaDeTiempo(s: s),
      const SizedBox(height: 16),
      if (!s.confirmada && s.estado == EstadoSolicitud.pendiente)
        Card(
          color: colores.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: s.enlaceDeCorreo
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('¿Tú pediste este material?', style: tema.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('A nombre de ${s.nombre}. Si lo confirmas, la solicitud llega al responsable del laboratorio.'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: _trabajando ? null : () => _hacer((r) => r.confirmarSolicitud(widget.token), 'Solicitud confirmada.'),
                        icon: const Icon(Icons.check),
                        label: const Text('Sí, yo lo pedí'),
                      ),
                      OutlinedButton(
                        onPressed: _trabajando
                            ? null
                            : () async {
                                if (await _seguro('No fui yo', 'Se cancela la solicitud y se avisa al responsable del laboratorio.', 'Cancelar y avisar')) {
                                  await _hacer((r) => r.noFuiYo(widget.token), 'Gracias por avisar. Se canceló la solicitud.');
                                }
                              },
                        child: const Text('No fui yo'),
                      ),
                    ]),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Falta confirmar', style: tema.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(s.correo == null
                        ? 'Pide al responsable del laboratorio que confirme tu solicitud en persona.'
                        : 'Te enviamos un enlace a ${s.correo}. Ábrelo desde tu correo y toca "Sí, yo lo pedí". '
                            'Si no lo ves, revisa la carpeta de correo no deseado.'),
                  ]),
          ),
        ),
      if (s.confirmada && s.estado == EstadoSolicitud.pendiente)
        const _Mensaje(icono: Icons.hourglass_top, texto: 'Tu solicitud está en revisión. Aquí verás cuando la aprueben.'),
      if (s.estado == EstadoSolicitud.aprobada) ...[
        _Mensaje(
          icono: Icons.thumb_up_alt_outlined,
          texto: 'Aprobada. Pasa al laboratorio por tu material'
              '${s.recogerHasta == null ? '' : ' antes del ${fechaHora(s.recogerHasta!)}'}. '
              'Lleva una identificación con foto (credencial de transporte, documento escolar con foto u otra).',
        ),
        if (s.notaAprobacion != null) _Mensaje(icono: Icons.sticky_note_2_outlined, texto: 'Nota del laboratorio: ${s.notaAprobacion}'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: s.codigoAceptado
                ? const Row(children: [
                    Icon(Icons.verified, color: Colors.green),
                    SizedBox(width: 12),
                    Expanded(child: Text('Código aceptado. Espera a que el responsable termine la entrega.')),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('¿Ya estás en el laboratorio?', style: tema.textTheme.titleMedium),
                    const Text('Escribe el código de 6 números que te muestra el responsable.'),
                    const SizedBox(height: 12),
                    Row(children: [
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _codigo,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: tema.textTheme.headlineSmall?.copyWith(letterSpacing: 6),
                          decoration: InputDecoration(counterText: '', errorText: _errorCodigo, errorMaxLines: 3),
                          onSubmitted: (_) => _canjear(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(onPressed: _trabajando ? null : _canjear, child: const Text('Validar')),
                    ]),
                  ]),
          ),
        ),
      ],
      if (s.estado.conMaterial || s.estado == EstadoSolicitud.devuelta) _Comprobante(s: s),
      if (s.estado == EstadoSolicitud.rechazada)
        _Mensaje(icono: Icons.block, texto: 'No fue aprobada. Motivo: ${s.motivoRechazo ?? 'sin motivo'}', color: colores.errorContainer),
      if (s.estado == EstadoSolicitud.cancelada)
        _Mensaje(icono: Icons.cancel_outlined, texto: 'Cancelada: ${s.motivoCancelacion ?? ''}', color: colores.surfaceContainerHighest),
      const SizedBox(height: 16),
      Text('Material', style: tema.textTheme.titleMedium),
      for (final l in s.lineas)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.nombre),
          subtitle: Text([
            l.codigo,
            if (l.aprobada != null && l.aprobada != l.cantidad) 'pediste ${l.cantidad}, aprobadas ${l.aprobada}',
            if (s.estado.conMaterial) l.pendiente == 0 ? 'devuelto' : 'por devolver: ${l.pendiente}',
          ].join(' · ')),
          trailing: Text('${l.cantidadFinal}', style: tema.textTheme.titleMedium),
        ),
      const Divider(),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Para qué'), subtitle: Text(s.motivo)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Devolver a más tardar'), subtitle: Text(fechaHora(s.fechaDevolucion))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (s.estado.abierta)
          OutlinedButton.icon(
            onPressed: _trabajando
                ? null
                : () async {
                    if (await _seguro('Cancelar solicitud', 'Se libera el material para que otros lo puedan pedir.', 'Cancelar solicitud')) {
                      await _hacer((r) => r.cancelarSolicitudPublica(widget.token), 'Solicitud cancelada.');
                    }
                  },
            icon: const Icon(Icons.close),
            label: const Text('Cancelar solicitud'),
          ),
        if (!_guardada)
          TextButton.icon(
            onPressed: () async {
              await AlmacenLocal.guardarSolicitud(SolicitudGuardada(folio: s.folio, token: widget.token, enviadaEn: s.creadaEn));
              ref.invalidate(solicitudesGuardadasProvider);
              if (mounted) setState(() => _guardada = true);
            },
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Guardar en este dispositivo'),
          ),
        if (s.enlaceDeCorreo && s.confirmada && (s.estado.conMaterial || s.estado == EstadoSolicitud.devuelta))
          TextButton(
            onPressed: _trabajando
                ? null
                : () async {
                    if (await _seguro('No fui yo', 'Se avisará al responsable del laboratorio que tú no recibiste este material.', 'Avisar')) {
                      await _hacer((r) => r.noFuiYo(widget.token), 'Gracias por avisar. El responsable lo va a revisar.');
                    }
                  },
            child: const Text('Yo no recibí este material'),
          ),
      ]),
    ]);
  }
}

class _LineaDeTiempo extends StatelessWidget {
  const _LineaDeTiempo({required this.s});

  final SolicitudPublica s;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final pasos = [
      ('Enviada', true),
      ('Confirmada', s.confirmada),
      ('Aprobada', const [EstadoSolicitud.aprobada, EstadoSolicitud.entregado, EstadoSolicitud.vencida, EstadoSolicitud.devuelta].contains(s.estado)),
      ('Entregada', s.estado.conMaterial || s.estado == EstadoSolicitud.devuelta),
      ('Devuelta', s.estado == EstadoSolicitud.devuelta),
    ];
    final terminada = s.estado == EstadoSolicitud.rechazada || s.estado == EstadoSolicitud.cancelada;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Chip(
          label: Text(s.estado.nombre),
          backgroundColor: s.estado == EstadoSolicitud.vencida || terminada ? colores.errorContainer : colores.secondaryContainer,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('Enviada el ${fechaHora(s.creadaEn)}', style: Theme.of(context).textTheme.bodySmall)),
      ]),
      const SizedBox(height: 8),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var i = 0; i < pasos.length; i++) ...[
          Icon(pasos[i].$2 ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18, color: pasos[i].$2 ? colores.primary : colores.outline),
          Padding(padding: const EdgeInsets.only(left: 4, right: 8), child: Text(pasos[i].$1)),
        ],
      ]),
    ]);
  }
}

class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.s});

  final SolicitudPublica s;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vencida = s.estado == EstadoSolicitud.vencida;
    return Card(
      color: vencida ? tema.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Comprobante · ${s.folio}', style: tema.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('A cargo de: ${s.nombre}${s.matricula == null ? '' : ', ${s.matricula}'}${s.grupo == null ? '' : ', ${s.grupo}'}',
              style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          if (s.autorizo != null) Text('Autorizó: ${s.autorizo}'),
          if (s.entregadaEn != null) Text('Entregado el ${fechaHora(s.entregadaEn!)}'),
          Text(s.estado == EstadoSolicitud.devuelta
              ? 'Devuelto por completo. ¡Gracias!'
              : '${vencida ? 'VENCIDO: debía devolverse' : 'Devolver a más tardar'} el ${fechaHora(s.fechaDevolucion)}. '
                  'Faltan ${s.piezasPendientes} de ${s.piezasEntregadas} piezas.'),
          if (vencida) const Text('Mientras no lo devuelvas, no puedes pedir más material.'),
        ]),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        color: color ?? Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(leading: Icon(icono), title: Text(texto)),
      );
}

/// Solicitudes cuyo enlace se guardó en este dispositivo, y recuperar un enlace perdido.
class MisSolicitudesPantalla extends ConsumerWidget {
  const MisSolicitudesPantalla({super.key});

  Future<void> _recuperar(BuildContext context, WidgetRef ref) async {
    final folio = TextEditingController();
    final matricula = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar el enlace'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Te lo mandamos al correo registrado con tu matrícula.'),
          const SizedBox(height: 12),
          TextField(controller: folio, decoration: const InputDecoration(labelText: 'Folio (ej. LM-0057)')),
          const SizedBox(height: 12),
          TextField(controller: matricula, decoration: const InputDecoration(labelText: 'Matrícula o clave')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (enviar != true || !context.mounted) return;
    try {
      final mensaje =
          await ref.read(repositorioProvider).recuperarEnlace(folio.text.trim(), matricula.text.trim(), await AlmacenLocal.dispositivo());
      if (context.mounted) avisar(context, mensaje);
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    } finally {
      folio.dispose();
      matricula.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardadas = ref.watch(solicitudesGuardadasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis solicitudes')),
      body: Centrado(
        child: Cargando<List<SolicitudGuardada>>(
          valor: guardadas,
          datos: (lista) => ListView(padding: const EdgeInsets.all(12), children: [
            if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('En este dispositivo no hay solicitudes guardadas. El enlace a cada solicitud también te llega por correo.'),
              ),
            for (final s in lista)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text('Folio ${s.folio}'),
                  subtitle: Text('Enviada el ${fechaHora(s.enviadaEn)}'),
                  onTap: () => context.push('/s/${s.token}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Quitar de este dispositivo',
                    onPressed: () async {
                      await AlmacenLocal.olvidarSolicitud(s.token);
                      ref.invalidate(solicitudesGuardadasProvider);
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _recuperar(context, ref),
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('¿Perdiste el enlace? Recupéralo por correo'),
            ),
          ]),
        ),
      ),
    );
  }
}
