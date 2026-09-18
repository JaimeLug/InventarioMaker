import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/hoja_acceso.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../modelos/catalogos.dart';
import '../../sin_conexion/cola.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

/// En la barra superior del celular: verde en línea, gris sin señal, naranja por enviar, rojo por resolver.
class IndicadorConexion extends StatelessWidget {
  const IndicadorConexion({super.key});

  @override
  Widget build(BuildContext context) {
    final cola = ColaSinConexion.instancia;
    if (cola == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: cola,
      builder: (context, _) {
        final porEnviar = cola.porEnviar.length;
        final porResolver = cola.porResolver.length;
        final (icono, color, texto) = switch (true) {
          _ when porResolver > 0 => (Icons.error_outline, Theme.of(context).colorScheme.error, '$porResolver por resolver'),
          _ when cola.hayAtrasados => (Icons.cloud_off, Theme.of(context).colorScheme.error, '$porEnviar sin enviar desde hace más de 24 h'),
          _ when cola.sinSenal => (Icons.cloud_off, Colors.grey.shade600, porEnviar == 0 ? 'Sin conexión' : 'Sin conexión · $porEnviar por enviar'),
          _ when porEnviar > 0 => (Icons.cloud_upload_outlined, Avisos.pendiente, '$porEnviar por enviar'),
          _ => (Icons.cloud_done_outlined, Colors.green.shade700, 'En línea'),
        };
        return IconButton(
          tooltip: texto,
          onPressed: () => context.push('/sin-conexion'),
          icon: Badge(
            isLabelVisible: porEnviar + porResolver > 0,
            label: Text('${porEnviar + porResolver}'),
            child: Icon(icono, color: color),
          ),
        );
      },
    );
  }
}

/// Por enviar, por resolver y lo último enviado.
class SinConexionPantalla extends ConsumerWidget {
  const SinConexionPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cola = ColaSinConexion.instancia;
    if (cola == null) {
      return const TmArmazon(
        ruta: '/sin-conexion',
        titulo: 'Sin conexión',
        conRegresar: true,
        child: TmVacio(
          icono: Ico.enLinea,
          titulo: 'En la computadora no hace falta',
          texto: 'El trabajo sin señal es del celular: ahí se guarda lo capturado y se envía solo al volver la conexión.',
        ),
      );
    }
    return ListenableBuilder(
      listenable: cola,
      builder: (context, _) {
        final tema = Theme.of(context);
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Sin conexión'),
              actions: const [BarraSesion()],
              bottom: TabBar(tabs: [
                Tab(text: 'Por enviar (${cola.porEnviar.length})'),
                Tab(text: 'Por resolver (${cola.porResolver.length})'),
                const Tab(text: 'Enviados'),
              ]),
            ),
            body: Centrado(
              child: Column(children: [
                if (cola.enviando || cola.actualizando) const LinearProgressIndicator(),
                ListTile(
                  leading: Icon(cola.sinSenal ? Icons.cloud_off : Icons.cloud_done_outlined),
                  title: Text(cola.sinSenal ? 'Sin conexión' : 'En línea'),
                  subtitle: Text(cola.datosDe == null
                      ? 'Todavía no hay datos guardados para trabajar sin señal.'
                      : 'Datos guardados: ${fechaHora(cola.datosDe!)}'),
                  trailing: TextButton(
                    onPressed: cola.enviando || cola.actualizando
                        ? null
                        : () async {
                            await cola.enviar();
                            await cola.actualizarDatos();
                            ref.invalidate(articulosProvider);
                          },
                    child: const Text('Actualizar'),
                  ),
                ),
                if (cola.horaMal != null)
                  _Aviso(
                    color: tema.colorScheme.errorContainer,
                    texto: 'La hora de este celular está mal por ${cola.horaMal!.inMinutes.abs()} minutos. '
                        'Corrígela en los ajustes del celular para que lo capturado sin señal quede en orden.',
                  ),
                if (cola.hayAtrasados)
                  _Aviso(
                    color: tema.colorScheme.errorContainer,
                    texto: 'Hay registros sin enviar desde hace más de 24 horas. Conéctate a internet para que se envíen.',
                  ),
                if (cola.esperandoA != null)
                  _Aviso(
                    color: tema.colorScheme.secondaryContainer,
                    texto: 'Para enviar lo pendiente tiene que entrar ${cola.esperandoA}: se envía a nombre de quien lo capturó.',
                    boton: TextButton(
                      onPressed: () async {
                        if (await pedirAcceso(context, descripcion: 'enviar lo capturado sin señal')) {
                          ref.invalidate(sesionProvider);
                          await cola.enviar();
                        }
                      },
                      child: Text('Entrar como ${cola.esperandoA}'),
                    ),
                  ),
                Expanded(
                  child: TabBarView(children: [
                    _Lista(
                      vacio: 'Nada por enviar.',
                      hijos: [
                        for (final c in cola.porEnviar)
                          ListTile(
                            leading: const Icon(Icons.schedule),
                            title: Text(c.resumen),
                            subtitle: Text('${fechaHora(c.capturado)} · ${c.usuarioNombre}'
                                '${c.fotos.isEmpty ? '' : ' · ${c.fotos.where((f) => f.subida).length} de ${c.fotos.length} fotos subidas'}'),
                          ),
                      ],
                    ),
                    _Lista(
                      vacio: 'Nada por resolver.',
                      hijos: [
                        for (final c in cola.porResolver)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c.resumen, style: tema.textTheme.titleSmall),
                                Text('${fechaHora(c.capturado)} · ${c.usuarioNombre}', style: tema.textTheme.bodySmall),
                                const SizedBox(height: 6),
                                Text(c.error ?? 'No se pudo aplicar.', style: TextStyle(color: tema.colorScheme.error)),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, children: [
                                  OutlinedButton(onPressed: () => cola.reintentar(c.id), child: const Text('Reintentar')),
                                  TextButton(
                                    onPressed: () async {
                                      final motivo = await pedirTexto(context,
                                          titulo: 'Descartar',
                                          etiqueta: '¿Por qué se descarta?',
                                          ayuda: 'Ejemplo: ya se había registrado con otro celular',
                                          minimo: 5,
                                          boton: 'Descartar');
                                      if (motivo != null) await cola.quitar(c.id);
                                    },
                                    child: const Text('Descartar'),
                                  ),
                                ]),
                              ]),
                            ),
                          ),
                      ],
                    ),
                    _Lista(
                      vacio: 'Todavía no se ha enviado nada desde este celular.',
                      hijos: [
                        for (final e in cola.enviados.take(40))
                          ListTile(
                            leading: Icon(e.conflicto == null ? Icons.check_circle_outline : Icons.warning_amber, color: e.conflicto == null ? Colors.green.shade700 : Avisos.pendiente),
                            title: Text(e.resumen),
                            subtitle: Text([
                              'Enviado: ${fechaHora(e.enviado)}',
                              if (e.tarde) 'Registrado tarde (más de 72 h)',
                              if (e.conflicto != null) 'Conflicto: ${e.conflicto}. El responsable va a revisar el conteo.',
                            ].join('\n')),
                          ),
                      ],
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.color, required this.texto, this.boton});

  final Color color;
  final String texto;
  final Widget? boton;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(texto), ?boton]),
      );
}

class _Lista extends StatelessWidget {
  const _Lista({required this.hijos, required this.vacio});

  final List<Widget> hijos;
  final String vacio;

  @override
  Widget build(BuildContext context) => hijos.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(vacio)))
      : ListView(padding: const EdgeInsets.all(8), children: hijos);
}

/// Lo aceptado con conflicto o registrado tarde (responsable y sub administración).
class ConflictosPantalla extends StatelessWidget {
  const ConflictosPantalla({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Conflictos sin conexión'), actions: const [BarraSesion(), SizedBox(width: Espacio.x2)]),
        body: Centrado(
          child: CargaConAcceso<List<Map<String, dynamic>>>(
            descripcion: 'ver los conflictos',
            requisito: Requisito.administracion,
            cargar: (repo) => repo.conflictosSinConexion(),
            construir: (context, lista, _) => ListView(children: [
              const ListTile(
                subtitle: Text('Registros capturados sin señal que rompían una regla (el material sí se movió) o que llegaron más de 72 horas después. '
                    'Cada conflicto deja un pendiente para contar el artículo.'),
              ),
              if (lista.isEmpty) const ListTile(title: Text('No hay conflictos.')),
              for (final c in lista)
                ListTile(
                  leading: Icon(c['conflicto'] == true ? Icons.warning_amber : Icons.history, color: c['conflicto'] == true ? Avisos.pendiente : null),
                  title: Text('${c['articulo']} · ${nombresMovimiento[c['tipo']] ?? c['tipo']} ×${c['cantidad']}'),
                  subtitle: Text([
                    if (c['motivo'] != null) '${c['motivo']}',
                    if (c['tarde'] == true) 'Registrado tarde',
                    'Capturado ${c['capturado_en'] == null ? '' : fechaHora(DateTime.parse('${c['capturado_en']}'))} por ${c['registro'] ?? ''}'
                        '${c['a_cargo'] == null ? '' : ' · a cargo de ${c['a_cargo']}'}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/articulo/${c['articulo_id']}'),
                ),
            ]),
          ),
        ),
      );
}
