import '../diseno/iconos.dart';
import '../armazon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/errores.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/solicitudes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

const _grupos = [
  ('POR_REVISAR', 'Por revisar'),
  ('POR_ENTREGAR', 'Por entregar'),
  ('EN_PRESTAMO', 'En préstamo'),
  ('SIN_CONFIRMAR', 'Sin confirmar'),
  ('CERRADAS', 'Cerradas'),
];

/// Bandeja de solicitudes (F-06): responsable y sub administración.
class BandejaPantalla extends StatelessWidget {
  const BandejaPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _grupos.length,
      child: TmArmazon(
        ruta: '/solicitudes',
        titulo: 'Solicitudes',
        bajoTitulo: TabBar(isScrollable: true, tabs: [for (final g in _grupos) Tab(text: g.$2)]),
        child: TabBarView(children: [
          for (final g in _grupos)
            Centrado(
              child: CargaConAcceso<List<SolicitudResumen>>(
                descripcion: 'ver las solicitudes',
                requisito: Requisito.administracion,
                cargar: (repo) => repo.solicitudes(g.$1),
                construir: (context, lista, recargar) => _Lista(lista: lista, grupo: g.$1),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.lista, required this.grupo});

  final List<SolicitudResumen> lista;
  final String grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    if (lista.isEmpty) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
              child: Text(grupo == 'SIN_CONFIRMAR'
                  ? 'No hay solicitudes esperando confirmación por correo.'
                  : 'No hay solicitudes aquí.')),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lista.length + (grupo == 'SIN_CONFIRMAR' ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (grupo == 'SIN_CONFIRMAR' && i == 0) {
          return const ListTile(
            leading: Icon(Ico.info),
            title: Text('Quien pidió todavía no abre el enlace de su correo. Si está aquí en persona, abre su solicitud y confírmala.'),
          );
        }
        final s = lista[grupo == 'SIN_CONFIRMAR' ? i - 1 : i];
        return ListTile(
          onTap: () async {
            await context.push('/solicitudes/${s.id}');
            ref.invalidate(solicitudesContarProvider);
          },
          leading: CircleAvatar(
            backgroundColor: s.vencida ? tema.colorScheme.errorContainer : tema.colorScheme.secondaryContainer,
            child: Icon(s.verificada ? Ico.conContrasena : Ico.persona),
          ),
          title: Text('${s.folio} · ${s.solicitante}'),
          subtitle: Text([
            '${s.articulos} artículo${s.articulos == 1 ? '' : 's'}, ${s.piezas} pieza${s.piezas == 1 ? '' : 's'}',
            switch (s.estado) {
              EstadoSolicitud.pendiente => 'pedida ${fechaHora(s.confirmadaEn ?? s.creadaEn)}',
              EstadoSolicitud.aprobada => 'recoger antes del ${fechaHora(s.recogerHasta!)}',
              EstadoSolicitud.entregado || EstadoSolicitud.vencida => '${s.vencida ? 'VENCIDA desde' : 'devolver'} ${fechaHora(s.fechaDevolucion)}',
              _ => s.estado.nombre,
            },
            if (!s.verificada && s.estado.abierta) 'ficha sin verificar',
          ].join(' · ')),
          trailing: s.alerta == null ? const Icon(Ico.avanzar) : Icon(Ico.aviso, color: tema.colorScheme.error),
        );
      },
    );
  }
}

/// Detalle de una solicitud: aprobar, rechazar, cancelar, entregar y su historia.
class SolicitudDetallePantalla extends StatelessWidget {
  const SolicitudDetallePantalla({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return TmArmazon(
      ruta: '/solicitudes',
      titulo: 'Solicitud',
      migas: const [('Solicitudes', '/solicitudes')],
      conRegresar: true,
      child: Centrado(
        child: CargaConAcceso<SolicitudDetalle>(
          descripcion: 'ver la solicitud',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.solicitudDetalle(id),
          construir: (context, s, recargar) => _Detalle(s: s, recargar: recargar),
        ),
      ),
    );
  }
}

class _Detalle extends ConsumerWidget {
  const _Detalle({required this.s, required this.recargar});

  final SolicitudDetalle s;
  final Future<void> Function() recargar;

  Future<void> _accion(BuildContext context, WidgetRef ref, String descripcion, Future<void> Function(Repositorio r) accion, String listo,
      {Requisito requisito = Requisito.administracion}) async {
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: descripcion, requisito: requisito, accion: () async {
        await accion(ref.read(repositorioProvider));
        return true;
      });
      if (hecho != true || !context.mounted) return;
      ref.invalidate(solicitudesContarProvider);
      ref.invalidate(articulosProvider);
      avisar(context, listo);
      await recargar();
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  Future<void> _aprobar(BuildContext context, WidgetRef ref) async {
    final r = await showModalBottomSheet<_Aprobacion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _HojaAprobar(s: s),
    );
    if (r == null || !context.mounted) return;
    await _accion(
      context,
      ref,
      'aprobar la solicitud ${s.folio}',
      (repo) => repo.aprobarSolicitud(s.id, cantidades: r.cantidades, fecha: r.fecha, nota: r.nota, vigencia: r.vigencia),
      'Aprobada. El material quedó apartado.',
    );
  }

  Future<void> _rechazar(BuildContext context, WidgetRef ref) async {
    String? motivo = motivosRechazo.first;
    final detalle = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Rechazar ${s.folio}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: motivo,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [for (final m in motivosRechazo) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (m) => setState(() => motivo = m),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: detalle,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: motivo == 'Otro' ? 'Explica el motivo *' : 'Detalle para el solicitante (opcional)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rechazar')),
          ],
        ),
      ),
    );
    final texto = detalle.text.trim();
    detalle.dispose();
    if (ok != true || !context.mounted) return;
    await _accion(context, ref, 'rechazar la solicitud ${s.folio}',
        (repo) => repo.rechazarSolicitud(s.id, motivo!, texto.isEmpty ? null : texto), 'Solicitud rechazada.');
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    final motivo = await pedirTexto(context,
        titulo: 'Cancelar ${s.folio}', etiqueta: 'Por qué se cancela *', ayuda: 'El solicitante lo verá', boton: 'Cancelar solicitud');
    if (motivo == null || !context.mounted) return;
    await _accion(context, ref, 'cancelar la solicitud ${s.folio}', (repo) => repo.cancelarSolicitud(s.id, motivo), 'Solicitud cancelada.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final p = s.solicitante;
    Widget dato(String etiqueta, String? valor) => valor == null || valor.isEmpty
        ? const SizedBox.shrink()
        : ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(etiqueta), subtitle: SelectableText(valor, style: tema.textTheme.bodyLarge));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text(s.folio, style: tema.textTheme.headlineSmall)),
        Chip(label: Text(s.estado.nombre), backgroundColor: s.estado == EstadoSolicitud.vencida ? colores.errorContainer : colores.secondaryContainer),
      ]),
      if (s.noFuiYoEn != null)
        _Alerta('El dueño del correo dijo "no fui yo" el ${fechaHora(s.noFuiYoEn!)}.', color: colores.errorContainer),
      if (p.posibleDuplicado || s.otroCorreo)
        const _Alerta('Posible duplicado: dijo que el correo registrado con su matrícula no es suyo. Compara la identificación con cuidado.'),
      if (p.impedimento != null && s.estado.abierta) _Alerta('${p.nombre}: ${p.impedimento}', color: colores.errorContainer),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nombre, style: tema.textTheme.titleLarge),
            Text([p.tipo.nombre, p.matricula, if (p.grupo != null) p.grupo!].join(' · ')),
            const SizedBox(height: 4),
            Text(p.historial, style: tema.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (p.verificadaEn != null)
              Text('Ficha verificada en persona por ${p.verificadaPor} el ${fecha(p.verificadaEn!)}', style: tema.textTheme.bodySmall)
            else
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Avisos.pendiente.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: const Text('Ficha sin verificar: al entregar, compara la identificación con el nombre y la matrícula.'),
              ),
            dato('Correo', p.correo == null ? null : '${p.correo}${p.correoConfirmado ? ' (confirmado)' : ''}'),
            dato('Teléfono', p.telefono),
            dato('Nota', p.nota),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => context.push('/persona/SOLICITANTE/${p.id}'), child: const Text('Ver expediente de la persona')),
            ),
          ]),
        ),
      ),
      dato('Para qué', s.motivo),
      dato('Devolver a más tardar', fechaHora(s.fechaDevolucion)),
      dato('Pedida', '${fechaHora(s.creadaEn)}${s.confirmadaEn == null ? ' · sin confirmar' : ' · confirmada ${s.confirmadaComo == 'EN_PERSONA' ? 'en persona' : 'por correo'}'}'),
      if (s.autorizo != null) dato('Aprobó', '${s.autorizo}${s.notaAprobacion == null ? '' : ' · nota: ${s.notaAprobacion}'}'),
      if (s.recogerHasta != null && s.estado == EstadoSolicitud.aprobada) dato('Recoger antes del', fechaHora(s.recogerHasta!)),
      if (s.entregadaEn != null)
        dato('Entregó', '${s.entrego} el ${fechaHora(s.entregadaEn!)} · ${tiposIdentificacion[s.tipoIdentificacion] ?? ''}'),
      dato('Motivo del rechazo', s.motivoRechazo),
      dato('Motivo de la cancelación', s.motivoCancelacion),
      const SizedBox(height: 8),
      Text('Material', style: tema.textTheme.titleMedium),
      for (final l in s.lineas)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Miniatura(ruta: l.foto, tamano: 44),
          title: Text(l.nombre),
          subtitle: Text([
            l.codigo,
            if (s.estado == EstadoSolicitud.pendiente) 'disponible ahora: ${l.disponible}',
            if (l.aprobada != null) 'aprobadas: ${l.aprobada}',
            if (s.estado.conMaterial) 'por devolver: ${l.pendiente}',
          ].join(' · ')),
          trailing: Text('${l.cantidad}',
              style: tema.textTheme.titleMedium?.copyWith(
                  color: s.estado == EstadoSolicitud.pendiente && (l.disponible ?? 0) < l.cantidad ? colores.error : null)),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (s.estado == EstadoSolicitud.pendiente && s.confirmadaEn == null)
          FilledButton.icon(
            onPressed: () => _accion(context, ref, 'confirmar en persona la solicitud ${s.folio}', (r) => r.confirmarEnPersona(s.id),
                'Solicitud confirmada en persona.'),
            icon: const Icon(Ico.aprobar),
            label: const Text('Confirmar en persona'),
          ),
        if (s.estado == EstadoSolicitud.pendiente && s.confirmadaEn != null) ...[
          FilledButton.icon(onPressed: () => _aprobar(context, ref), icon: const Icon(Ico.listo), label: const Text('Aprobar')),
          OutlinedButton.icon(onPressed: () => _rechazar(context, ref), icon: const Icon(Ico.desactivar), label: const Text('Rechazar')),
        ],
        if (s.estado == EstadoSolicitud.aprobada)
          FilledButton.icon(
            onPressed: () async {
              await context.push('/solicitudes/${s.id}/entrega');
              await recargar();
            },
            icon: const Icon(Ico.prestar),
            label: const Text('Entregar'),
          ),
        if (s.estado.abierta) TextButton(onPressed: () => _cancelar(context, ref), child: const Text('Cancelar solicitud')),
      ]),
      if (s.prestamos.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Préstamos', style: tema.textTheme.titleMedium),
        for (final pr in s.prestamos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${pr['cantidad']} × ${pr['articulo']}'),
            subtitle: Text((pr['pendiente'] as int) == 0 ? 'Cerrado' : 'Por devolver: ${pr['pendiente']} · vence ${fechaHora(DateTime.parse(pr['vence_en'] as String))}'),
            trailing: const Icon(Ico.avanzar),
            onTap: () => context.push('/expediente/${pr['prestamo_id']}'),
          ),
      ],
      if (s.hayIdentificacion || s.fotosEntrega.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Evidencia de la entrega', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (s.fotosEntrega.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [for (final f in s.fotosEntrega) FotoPrivada(ruta: f)]),
        const SizedBox(height: 8),
        if (s.identificacionBorrada)
          const Text('La foto de la identificación se borró al terminar el ciclo escolar.')
        else if (s.hayIdentificacion)
          VerIdentificacion(solicitudId: s.id),
      ],
      if (s.codigos.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Códigos de entrega', style: tema.textTheme.titleMedium),
        for (final c in s.codigos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Ico.conteo),
            title: Text(c.nombreEstado),
            subtitle: Text(c.usadoEn == null ? 'Vigencia hasta ${fechaHora(c.expiraEn)}' : 'Usado el ${fechaHora(c.usadoEn!)}'),
          ),
      ],
    ]);
  }
}

class _Alerta extends StatelessWidget {
  const _Alerta(this.texto, {this.color});

  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        color: color ?? Avisos.pendiente.withValues(alpha: 0.15),
        child: ListTile(leading: const Icon(Ico.aviso), title: Text(texto)),
      );
}

/// Muestra la identificación solo al tocar, y cada vez queda en la bitácora con nombre y hora (F-04b).
class VerIdentificacion extends ConsumerStatefulWidget {
  const VerIdentificacion({super.key, required this.solicitudId});

  final String solicitudId;

  @override
  ConsumerState<VerIdentificacion> createState() => _VerIdentificacionState();
}

class _VerIdentificacionState extends ConsumerState<VerIdentificacion> {
  List<String>? _urls;
  bool _cargando = false;

  Future<void> _ver() async {
    setState(() => _cargando = true);
    try {
      final urls = await conAcceso<List<String>>(context, ref,
          descripcion: 'ver la identificación', requisito: Requisito.administracion, accion: () => ref.read(repositorioProvider).verIdentificacion(widget.solicitudId));
      if (mounted) setState(() => _urls = urls);
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_urls == null) {
      return OutlinedButton.icon(
        onPressed: _cargando ? null : _ver,
        icon: const Icon(Ico.credencial),
        label: const Text('Ver identificación (queda registrado)'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Identificación · dato de menor de edad: no la compartas ni la fotografíes.'),
      const SizedBox(height: 8),
      for (final u in _urls!)
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(u, height: 260, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('No se pudo mostrar.')),
        ),
    ]);
  }
}

class _Aprobacion {
  const _Aprobacion({required this.cantidades, required this.vigencia, this.fecha, this.nota});

  final Map<String, int> cantidades;
  final String vigencia;
  final DateTime? fecha;
  final String? nota;
}

class _HojaAprobar extends StatefulWidget {
  const _HojaAprobar({required this.s});

  final SolicitudDetalle s;

  @override
  State<_HojaAprobar> createState() => _HojaAprobarState();
}

class _HojaAprobarState extends State<_HojaAprobar> {
  late final Map<String, int> _cantidades = {
    for (final l in widget.s.lineas) l.articuloId: l.cantidad.clamp(0, (l.disponible ?? 0).clamp(0, l.cantidad)),
  };
  final _nota = TextEditingController();
  DateTime? _fecha;
  String _vigencia = 'RATO';

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  bool get _hayCambios => _fecha != null || widget.s.lineas.any((l) => _cantidades[l.articuloId] != l.cantidad);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final total = _cantidades.values.fold(0, (a, b) => a + b);
    final maxDias = widget.s.solicitante.tipo == TipoSolicitante.maestro ? 30 : 14;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Aprobar ${widget.s.folio}', style: tema.textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final l in widget.s.lineas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.nombre, style: tema.textTheme.titleSmall),
                    Text('Pidió ${l.cantidad} · disponibles ${l.disponible}', style: tema.textTheme.bodySmall),
                  ]),
                ),
                SelectorCantidad(
                  valor: _cantidades[l.articuloId]!,
                  maximo: l.cantidad.clamp(0, (l.disponible ?? 0).clamp(0, l.cantidad)),
                  alCambiar: (v) => setState(() => _cantidades[l.articuloId] = v),
                ),
              ]),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Ico.fecha),
            title: Text('Devolver el ${fecha(_fecha ?? widget.s.fechaDevolucion)}'),
            trailing: TextButton(
              onPressed: () async {
                final f = await elegirFechaDevolucion(context, maxDias: maxDias);
                if (f != null) setState(() => _fecha = f);
              },
              child: const Text('Cambiar'),
            ),
          ),
          Text('¿Cuándo pasa a recoger?', style: tema.textTheme.titleSmall),
          for (final v in vigenciasCodigo.entries)
            RadioListTile<String>(
              value: v.key,
              groupValue: _vigencia,
              onChanged: (x) => setState(() => _vigencia = x!),
              title: Text(v.value),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          TextField(
            controller: _nota,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _hayCambios ? 'Nota para el solicitante *' : 'Nota para el solicitante (opcional)',
              helperText: _hayCambios ? 'Cambiaste cantidades o la fecha: explica por qué.' : null,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: total == 0 || (_hayCambios && _nota.text.trim().isEmpty)
                ? null
                : () => Navigator.pop(
                      context,
                      _Aprobacion(
                        cantidades: Map.of(_cantidades),
                        vigencia: _vigencia,
                        fecha: _fecha,
                        nota: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
                      ),
                    ),
            child: Text(total == 0 ? 'No hay nada que aprobar' : 'Aprobar y apartar $total pieza${total == 1 ? '' : 's'}'),
          ),
        ]),
      ),
    );
  }
}

/// Entrega en el laboratorio (F-06 paso 6): código, identificación y foto del material.
class EntregaPantalla extends ConsumerStatefulWidget {
  const EntregaPantalla({super.key, required this.id});

  final String id;

  @override
  ConsumerState<EntregaPantalla> createState() => _EntregaPantallaState();
}

class _EntregaPantallaState extends ConsumerState<EntregaPantalla> {
  SolicitudDetalle? _s;
  String? _error;
  Timer? _reloj;
  bool _trabajando = false;
  String _tipoIdentificacion = 'TRANSPORTE';
  final _identificacion = <FotoNueva>[];
  final _material = <FotoNueva>[];
  DateTime? _nuevaFecha;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar(conAccesoPrimero: true));
    // Mientras el solicitante escribe el código, la pantalla se revisa sola.
    _reloj = Timer.periodic(const Duration(seconds: 3), (_) {
      final c = _s?.codigo;
      if (_s != null && !_trabajando && !(c?.aceptado ?? false)) _cargar();
      if (mounted) setState(() {}); // cuenta regresiva
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool conAccesoPrimero = false}) async {
    try {
      final repo = ref.read(repositorioProvider);
      final SolicitudDetalle? s;
      if (conAccesoPrimero) {
        s = await conAcceso<SolicitudDetalle>(context, ref,
            descripcion: 'entregar la solicitud', requisito: Requisito.administracion, accion: () => repo.solicitudDetalle(widget.id));
      } else {
        s = await repo.solicitudDetalle(widget.id);
      }
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = s == null ? 'Se necesita identificarse para entregar.' : null;
      });
    } on Object catch (e) {
      if (mounted && _s == null) setState(() => _error = traducir(e).mensaje);
    }
  }

  Future<void> _hacer(String descripcion, Future<void> Function(Repositorio r) accion) async {
    setState(() => _trabajando = true);
    try {
      await conAcceso<bool>(context, ref, descripcion: descripcion, requisito: Requisito.administracion, accion: () async {
        await accion(ref.read(repositorioProvider));
        return true;
      });
      await _cargar();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _capturarAqui() async {
    final matricula = TextEditingController();
    final codigo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Que lo escriba el solicitante'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Pásale el dispositivo. Escribe tu matrícula y el código que ves en pantalla.'),
          const SizedBox(height: 12),
          TextField(controller: matricula, decoration: const InputDecoration(labelText: 'Matrícula o clave')),
          const SizedBox(height: 12),
          TextField(
            controller: codigo,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Código', counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Validar')),
        ],
      ),
    );
    final m = matricula.text.trim(), c = codigo.text.trim();
    matricula.dispose();
    codigo.dispose();
    if (ok != true || !mounted) return;
    try {
      final error = await conAcceso<String?>(context, ref,
          descripcion: 'validar el código', requisito: Requisito.administracion, accion: () => ref.read(repositorioProvider).canjearEnLaboratorio(widget.id, m, c));
      if (!mounted) return;
      if (error != null) {
        avisarError(context, ErrorApp(error));
      } else {
        await _cargar();
      }
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    }
  }

  Future<void> _cerrar() async {
    final s = _s!;
    final falta = _identificacion.isEmpty
        ? 'Toma la foto de la identificación.'
        : _material.isEmpty
            ? 'Toma la foto del material que se entrega.'
            : !s.fechaDevolucion.isAfter(DateTime.now()) && _nuevaFecha == null
                ? 'La fecha de devolución ya pasó: elige una nueva.'
                : null;
    if (falta != null) {
      avisar(context, falta);
      return;
    }
    setState(() => _trabajando = true);
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: 'cerrar la entrega de ${s.folio}', requisito: Requisito.administracion,
          accion: () async {
        await ref.read(repositorioProvider).entregarSolicitud(s.id,
            tipoIdentificacion: _tipoIdentificacion, identificacion: _identificacion.first, material: _material, fechaDevolucion: _nuevaFecha);
        return true;
      });
      if (hecho != true || !mounted) return;
      ref.invalidate(articulosProvider);
      ref.invalidate(solicitudesContarProvider);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Ico.ok, size: 40, color: Colors.green),
          title: const Text('Entregado'),
          content: Text('El material quedó a cargo de ${s.solicitante.nombre}. ${s.autorizo} solo autorizó la entrega.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
        ),
      );
      if (mounted) context.pop();
    } on Object catch (e) {
      if (mounted) avisarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return TmArmazon(
             ruta: '/solicitudes',
             titulo: s == null ? 'Entregar' : 'Entregar ${s.folio}',
             conRegresar: true,
             child: Centrado(
        child: s == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: () => _cargar(conAccesoPrimero: true), child: const Text('Reintentar')),
                      ]),
              )
            : _contenido(context, s),
      ),
           );
  }

  Widget _contenido(BuildContext context, SolicitudDetalle s) {
    final tema = Theme.of(context);
    if (s.estado != EstadoSolicitud.aprobada) {
      return Center(child: Text('Esta solicitud ya no está por entregar (${s.estado.nombre.toLowerCase()}).'));
    }
    final c = s.codigo;
    final aceptado = c?.aceptado ?? false;
    final restante = c == null ? Duration.zero : c.expiraEn.difference(DateTime.now());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${s.solicitante.nombre} · ${s.solicitante.matricula}', style: tema.textTheme.titleLarge),
      Text([for (final l in s.lineas.where((l) => l.cantidadFinal > 0)) '${l.cantidadFinal} × ${l.nombre}'].join('\n')),
      const SizedBox(height: 16),
      if (!aceptado)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Text('1. Que el solicitante escriba este código en la página de su solicitud'),
              const SizedBox(height: 12),
              if (c != null && c.vigente) ...[
                Text(c.codigo!, style: tema.textTheme.displayMedium?.copyWith(letterSpacing: 12, fontWeight: FontWeight.w700)),
                Text(restante.inMinutes >= 90
                    ? 'Vigente hasta ${fechaHora(c.expiraEn)}'
                    : 'Vence en ${restante.inMinutes}:${(restante.inSeconds % 60).toString().padLeft(2, '0')}'),
                const SizedBox(height: 8),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Esperando a que lo escriba…'),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: _capturarAqui, icon: const Icon(Ico.enEsteAparato), label: const Text('No trae celular: capturar aquí')),
                ]),
              ] else ...[
                Text(c == null ? 'No hay código todavía.' : 'El código ${c.nombreEstado.toLowerCase()}.'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _trabajando ? null : () => _hacer('generar un código nuevo', (r) => r.codigoNuevo(s.id, 'RATO')),
                  icon: const Icon(Ico.reintentar),
                  label: const Text('Generar código nuevo (1 h 30 min)'),
                ),
              ],
            ]),
          ),
        )
      else ...[
        const Card(child: ListTile(leading: Icon(Ico.verificado, color: Colors.green), title: Text('Código aceptado.'))),
        const SizedBox(height: 8),
        if (s.solicitante.verificadaEn == null)
          Card(
            color: Avisos.pendiente.withValues(alpha: 0.12),
            child: ListTile(
              leading: const Icon(Ico.credencial),
              title: Text('Compara la identificación con: ${s.solicitante.nombre}, ${s.solicitante.matricula}'),
              subtitle: const Text('Al cerrar la entrega, la ficha queda verificada con tu nombre.'),
            ),
          ),
        Text('2. Identificación con foto', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _tipoIdentificacion,
          decoration: const InputDecoration(labelText: 'Qué identificación mostró'),
          items: [for (final t in tiposIdentificacion.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
          onChanged: (t) => setState(() => _tipoIdentificacion = t ?? 'TRANSPORTE'),
        ),
        const SizedBox(height: 8),
        SelectorFotos(fotos: _identificacion, alCambiar: () => setState(() {}), texto: 'Foto de la identificación', maximo: 1),
        const Text('Solo la ven el responsable y sub administración. Se borra al terminar el ciclo escolar si no debe nada.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        Text('3. Foto del material que se entrega', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        SelectorFotos(fotos: _material, alCambiar: () => setState(() {}), texto: 'Foto del material'),
        if (!s.fechaDevolucion.isAfter(DateTime.now())) ...[
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Ico.vence, color: tema.colorScheme.error),
            title: Text(_nuevaFecha == null ? 'La fecha de devolución ya pasó' : 'Nueva fecha: ${fecha(_nuevaFecha!)}'),
            trailing: TextButton(
              onPressed: () async {
                final f = await elegirFechaDevolucion(context, maxDias: s.solicitante.tipo == TipoSolicitante.maestro ? 30 : 14);
                if (f != null) setState(() => _nuevaFecha = f);
              },
              child: const Text('Elegir'),
            ),
          ),
        ] else
          Text('Devolver a más tardar el ${fechaHora(s.fechaDevolucion)}.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _trabajando ? null : _cerrar,
          icon: _trabajando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Ico.todoListo),
          label: const Text('Cerrar entrega'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _trabajando
              ? null
              : () async {
                  final motivo = await pedirTexto(context,
                      titulo: 'No se entrega', etiqueta: 'Por qué', ayuda: 'Ej. no trae identificación con foto', boton: 'Anular entrega');
                  if (motivo == null || !mounted) return;
                  await _hacer('anular la entrega', (r) => r.anularEntrega(s.id, motivo));
                  _identificacion.clear();
                  _material.clear();
                },
          child: const Text('No trae identificación: anular esta entrega'),
        ),
      ],
    ]);
  }
}
