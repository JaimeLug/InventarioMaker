import '../armazon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/solicitudes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';
import 'solicitudes_pantallas.dart' show VerIdentificacion;

DateTime? _f(Object? v) => v == null ? null : DateTime.parse(v as String);
List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

/// F-18: quién tiene material fuera del laboratorio. Solo responsable y sub administración.
class AdeudosPantalla extends StatelessWidget {
  const AdeudosPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return TmArmazon(
      ruta: '/adeudos',
      titulo: 'Adeudos',
      child: Centrado(
        child: CargaConAcceso<List<Adeudo>>(
          descripcion: 'ver los adeudos',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.adeudos(),
          construir: (context, lista, recargar) {
            final tema = Theme.of(context);
            if (lista.isEmpty) {
              return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nadie tiene material fuera.')))]);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = lista[i];
                return ListTile(
                  onTap: () => context.push('/persona/${a.personaTipo}/${a.personaId}'),
                  leading: CircleAvatar(
                    backgroundColor: a.vencidos > 0 ? tema.colorScheme.errorContainer : tema.colorScheme.secondaryContainer,
                    child: Text('${a.piezas}'),
                  ),
                  title: Text(a.nombre),
                  subtitle: Text([
                    a.detalle,
                    '${a.piezas} pieza${a.piezas == 1 ? '' : 's'} desde el ${fecha(a.desde)}',
                    if (a.vencidos > 0) '${a.vencidos} vencido${a.vencidos == 1 ? '' : 's'}',
                    if (a.bloqueado) 'bloqueado',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Todo lo de una persona: datos, préstamos, reportes y solicitudes.
class PersonaPantalla extends StatelessWidget {
  const PersonaPantalla({super.key, required this.tipo, required this.id});

  final String tipo;
  final String id;

  @override
  Widget build(BuildContext context) {
    return TmArmazon(
      ruta: '/adeudos',
      titulo: 'Expediente de la persona',
      migas: const [('Adeudos', '/adeudos')],
      conRegresar: true,
      child: Centrado(
        child: CargaConAcceso<Map<String, dynamic>>(
          descripcion: 'ver el expediente',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.personaExpediente(tipo, id),
          construir: (context, p, recargar) => _Persona(p: p, recargar: recargar),
        ),
      ),
    );
  }
}

class _Persona extends ConsumerWidget {
  const _Persona({required this.p, required this.recargar});

  final Map<String, dynamic> p;
  final Future<void> Function() recargar;

  bool get _esSolicitante => p['persona_tipo'] == 'SOLICITANTE';

  Future<void> _bloqueo(BuildContext context, WidgetRef ref, {required bool bloquear}) async {
    final motivo = await pedirTexto(context,
        titulo: bloquear ? 'Bloquear' : 'Desbloquear',
        etiqueta: bloquear ? 'Por qué se bloquea *' : 'Por qué se desbloquea *',
        ayuda: bloquear ? null : 'Si debe algo vencido, podrá pedir solo hasta el fin de la jornada de hoy.',
        minimo: 10,
        boton: bloquear ? 'Bloquear' : 'Desbloquear');
    if (motivo == null || !context.mounted) return;
    try {
      final hecho = await conAcceso<bool>(context, ref,
          descripcion: '${bloquear ? 'bloquear' : 'desbloquear'} a ${p['nombre']}', requisito: Requisito.administracionConfirmada, accion: () async {
        final repo = ref.read(repositorioProvider);
        bloquear ? await repo.bloquearSolicitante(p['persona_id'] as String, motivo) : await repo.desbloquearSolicitante(p['persona_id'] as String, motivo);
        return true;
      });
      if (hecho == true && context.mounted) {
        avisar(context, bloquear ? 'Bloqueado.' : 'Desbloqueado.');
        await recargar();
      }
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  Future<void> _editar(BuildContext context, WidgetRef ref) async {
    final nombre = TextEditingController(text: p['nombre'] as String?);
    final grupo = TextEditingController(text: p['grupo'] as String?);
    final correo = TextEditingController(text: p['correo'] as String?);
    final telefono = TextEditingController(text: p['telefono'] as String?);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corregir datos'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Hazlo con la persona enfrente y su identificación a la vista.'),
            const SizedBox(height: 12),
            TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 12),
            TextField(controller: grupo, decoration: const InputDecoration(labelText: 'Grupo o área')),
            const SizedBox(height: 12),
            TextField(controller: correo, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
            const SizedBox(height: 12),
            TextField(controller: telefono, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    final datos = (nombre.text.trim(), grupo.text.trim(), correo.text.trim(), telefono.text.trim());
    for (final c in [nombre, grupo, correo, telefono]) {
      c.dispose();
    }
    if (ok != true || !context.mounted) return;
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: 'corregir los datos de ${datos.$1}', requisito: Requisito.administracion,
          accion: () async {
        await ref.read(repositorioProvider).editarSolicitante(p['persona_id'] as String,
            nombre: datos.$1, grupo: datos.$2, correo: datos.$3.isEmpty ? null : datos.$3, telefono: datos.$4.isEmpty ? null : datos.$4);
        return true;
      });
      if (hecho == true && context.mounted) await recargar();
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final prestamos = _l(p['prestamos']);
    final abiertos = prestamos.where((x) => (x['pendiente'] as int) > 0).toList();
    final cerrados = prestamos.where((x) => (x['pendiente'] as int) == 0).toList();
    final incidencias = _l(p['incidencias']);
    final solicitudes = _l(p['solicitudes']);
    final tipo = p['tipo'] as String;
    final nombreTipo = _esSolicitante ? TipoSolicitante.desde(tipo).nombre : Rol.desde(tipo).nombre;

    Widget prestamo(Map<String, dynamic> x) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(x['vencido'] == true ? Icons.warning_amber : (x['con_retraso'] == true ? Icons.schedule : Icons.inventory_2_outlined),
              color: x['vencido'] == true ? tema.colorScheme.error : null),
          title: Text('${x['cantidad']} × ${x['nombre']}${x['folio'] == null ? '' : ' · ${x['folio']}'}'),
          subtitle: Text((x['pendiente'] as int) > 0
              ? 'Debe ${x['pendiente']} · ${x['vencido'] == true ? 'VENCIDO desde' : 'vence'} ${fechaHora(_f(x['vence_en'])!)}'
              : 'Prestado ${fecha(_f(x['fecha'])!)} · devuelto ${fecha(_f(x['cerrado_en'])!)}${x['con_retraso'] == true ? ' (con retraso)' : ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/expediente/${x['prestamo_id']}'),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(p['nombre'] as String, style: tema.textTheme.headlineSmall),
      Text([nombreTipo, if (p['matricula'] != null) p['matricula'], if (p['grupo'] != null) p['grupo']].join(' · ')),
      if (p['impedimento'] != null)
        Card(color: tema.colorScheme.errorContainer, child: ListTile(leading: const Icon(Icons.block), title: Text(p['impedimento'] as String))),
      if (_esSolicitante) ...[
        if (p['verificada_en'] != null)
          Text('Ficha verificada por ${p['verificada_por']} el ${fecha(_f(p['verificada_en'])!)}', style: tema.textTheme.bodySmall)
        else
          Text('Ficha sin verificar en persona', style: tema.textTheme.bodySmall?.copyWith(color: Avisos.pendiente)),
        if (p['correo'] != null) Text('${p['correo']}${p['correo_confirmado'] == true ? ' (confirmado)' : ''}'),
        if (p['telefono'] != null) Text(p['telefono'] as String),
        if (p['posible_duplicado'] == true) const Text('Posible duplicado de otra ficha con la misma matrícula.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _editar(context, ref), icon: const Icon(Icons.edit_outlined), label: const Text('Corregir datos')),
          if (p['bloqueo_manual'] == true || p['impedimento'] != null)
            OutlinedButton.icon(
                onPressed: () => _bloqueo(context, ref, bloquear: false), icon: const Icon(Icons.lock_open), label: const Text('Desbloquear'))
          else
            OutlinedButton.icon(onPressed: () => _bloqueo(context, ref, bloquear: true), icon: const Icon(Icons.lock_outline), label: const Text('Bloquear')),
        ]),
      ],
      const SizedBox(height: 16),
      Text('Tiene ahora', style: tema.textTheme.titleMedium),
      if (abiertos.isEmpty) const ListTile(contentPadding: EdgeInsets.zero, title: Text('Nada.')),
      for (final x in abiertos) prestamo(x),
      if (incidencias.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Pérdidas y daños a su nombre', style: tema.textTheme.titleMedium),
        for (final i in incidencias)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text('${i['tipo'] == 'PERDIDA' ? 'Pérdida' : 'Daño'}: ${i['cantidad']} × ${i['articulo']}'),
            subtitle: Text('${switch (i['estado']) {
              'CONFIRMADA' => 'Confirmado',
              'DESCARTADA' => 'Descartado',
              _ => 'En revisión',
            }} · ${fecha(_f(i['reportada_en'])!)} · ${i['nota']}'),
          ),
      ],
      if (solicitudes.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Solicitudes', style: tema.textTheme.titleMedium),
        for (final s in solicitudes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${s['folio']} · ${EstadoSolicitud.desde(s['estado'] as String).nombre}'),
            subtitle: Text('Pedida ${fecha(_f(s['creada_en'])!)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/solicitudes/${s['id']}'),
          ),
      ],
      if (cerrados.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Historial', style: tema.textTheme.titleMedium),
        for (final x in cerrados) prestamo(x),
      ],
    ]);
  }
}

/// F-18: "¿a nombre de quién estaba?" Todo lo de un préstamo en una sola pantalla.
class ExpedientePantalla extends StatelessWidget {
  const ExpedientePantalla({super.key, required this.prestamoId});

  final String prestamoId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expediente del préstamo'), actions: const [BarraSesion()]),
      body: Centrado(
        child: CargaConAcceso<Map<String, dynamic>>(
          descripcion: 'ver el expediente',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.expedientePrestamo(prestamoId),
          construir: (context, e, recargar) => _Expediente(e: e),
        ),
      ),
    );
  }
}

class _Expediente extends StatelessWidget {
  const _Expediente({required this.e});

  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final articulo = Map<String, dynamic>.from(e['articulo'] as Map);
    final sol = e['solicitud'] == null ? null : Map<String, dynamic>.from(e['solicitud'] as Map);
    final pendiente = e['pendiente'] as int;
    Widget fila(String etiqueta, String? valor) => valor == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 150, child: Text(etiqueta, style: tema.textTheme.bodySmall)),
              Expanded(child: SelectableText(valor)),
            ]),
          );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: tema.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'El material está a cargo de ${e['a_cargo']}. ${e['autorizo']} solo autorizó${sol == null ? ' el préstamo' : ' la entrega'}.',
            style: tema.textTheme.titleMedium,
          ),
        ),
      ),
      const SizedBox(height: 8),
      fila('Artículo', '${e['cantidad']} × ${articulo['nombre']} (${articulo['codigo']})'),
      fila('A cargo de', '${e['a_cargo']}${e['a_cargo_matricula'] == null ? '' : ', ${e['a_cargo_matricula']}'}'),
      fila('Prestado', fechaHora(_f(e['fecha'])!)),
      fila('Autorizó', e['autorizo'] as String?),
      if (e['registro'] != e['autorizo']) fila('Registró / entregó', e['registro'] as String?),
      fila(pendiente == 0 ? 'Debía volver' : (e['vencido'] == true ? 'VENCIDO desde' : 'Vence'), fechaHora(_f(e['vence_en'])!)),
      fila('Pendiente', pendiente == 0 ? 'Nada: cerrado' : conUnidad(pendiente, articulo['unidad'] as String)),
      fila('Nota', e['nota'] as String?),
      if (sol != null) ...[
        const Divider(height: 24),
        Text('Solicitud ${sol['folio']}', style: tema.textTheme.titleMedium),
        fila('Pedida', '${fechaHora(_f(sol['creada_en'])!)} · ${sol['motivo']}'),
        fila('Confirmada', sol['confirmada_en'] == null ? null : '${fechaHora(_f(sol['confirmada_en'])!)} (${sol['confirmada_como'] == 'EN_PERSONA' ? 'en persona' : 'por correo'})'),
        fila('Aprobó', sol['autorizada_en'] == null ? null : '${sol['autorizo']} el ${fechaHora(_f(sol['autorizada_en'])!)}'),
        fila('Entregó', sol['entregada_en'] == null ? null : '${sol['entrego']} el ${fechaHora(_f(sol['entregada_en'])!)}'),
        fila('Identificación', tiposIdentificacion[sol['tipo_identificacion']]),
        for (final c in _l(sol['codigos']))
          fila('Código', CodigoEntrega.desdeMapa(c).nombreEstado + (c['usado_en'] == null ? ' (generado ${hora(_f(c['generado_en'])!)})' : ' el ${fechaHora(_f(c['usado_en'])!)}')),
        if (sol['no_fui_yo_en'] != null) fila('Alerta', 'El dueño del correo dijo "no fui yo" el ${fechaHora(_f(sol['no_fui_yo_en'])!)}'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final f in (sol['fotos_entrega'] as List)) FotoPrivada(ruta: f as String)]),
        const SizedBox(height: 8),
        if (sol['identificacion_borrada'] == true)
          const Text('La foto de la identificación se borró al terminar el ciclo escolar.')
        else if (sol['hay_identificacion'] == true)
          VerIdentificacion(solicitudId: sol['id'] as String),
        TextButton(onPressed: () => context.push('/solicitudes/${sol['id']}'), child: const Text('Abrir la solicitud')),
      ],
      if (_l(e['extensiones']).isNotEmpty) ...[
        const Divider(height: 24),
        Text('Extensiones', style: tema.textTheme.titleMedium),
        for (final x in _l(e['extensiones'])) fila(fecha(_f(x['en'])!), 'Hasta ${fecha(_f(x['fecha_nueva'])!)} · ${x['por']} · ${x['motivo']}'),
      ],
      if (_l(e['cierres']).isNotEmpty) ...[
        const Divider(height: 24),
        Text('Devoluciones', style: tema.textTheme.titleMedium),
        for (final x in _l(e['cierres']))
          fila(fechaHora(_f(x['fecha'])!), '${x['tipo'] == 'PERDIDA' ? 'Pérdida confirmada' : 'Regresaron'} ${x['cantidad']} · recibió ${x['recibio']}${x['nota'] == null ? '' : ' · ${x['nota']}'}'),
      ],
      if (_l(e['incidencias']).isNotEmpty) ...[
        const Divider(height: 24),
        Text('Reportes ligados', style: tema.textTheme.titleMedium),
        for (final i in _l(e['incidencias']))
          fila(fecha(_f(i['reportada_en'])!), '${i['tipo'] == 'PERDIDA' ? 'Pérdida' : 'Daño'} de ${i['cantidad']} · ${i['estado']} · ${i['nota']}'),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => context.push('/persona/${e['persona_tipo']}/${e['persona_id']}'),
        icon: const Icon(Icons.person_search_outlined),
        label: const Text('Todo lo de esta persona'),
      ),
    ]);
  }
}
