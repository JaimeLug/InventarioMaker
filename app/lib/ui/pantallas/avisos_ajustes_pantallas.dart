import '../armazon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/avisos_celular.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/solicitudes.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';

/// La campana: avisos de solicitudes nuevas, cancelaciones, alertas y reportes.
class AvisosPantalla extends ConsumerWidget {
  const AvisosPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TmArmazon(
      ruta: '/avisos',
      titulo: 'Avisos',
      conRegresar: true,
      child: Centrado(
        child: CargaConAcceso<List<Aviso>>(
          descripcion: 'ver tus avisos',
          requisito: Requisito.docente,
          cargar: (repo) async {
            final lista = await repo.avisos();
            if (lista.any((a) => !a.leido)) {
              await repo.marcarAvisosLeidos();
              ref.invalidate(avisosSinLeerProvider);
            }
            return lista;
          },
          construir: (context, lista, recargar) {
            final tema = Theme.of(context);
            return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              if (!AvisosCelular.disponible)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('En este dispositivo los avisos solo se ven aquí.'),
                  subtitle: Text('En la app de Android con avisos activados también llegan al celular.'),
                ),
              if (lista.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No tienes avisos.'))),
              for (final a in lista)
                ListTile(
                  leading: Icon(a.titulo.startsWith('Alerta') ? Icons.warning_amber : Icons.notifications_outlined,
                      color: a.titulo.startsWith('Alerta') ? tema.colorScheme.error : null),
                  title: Text(a.titulo, style: a.leido ? null : const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([if (a.cuerpo != null) a.cuerpo!, fechaHora(a.creadoEn)].join('\n')),
                  trailing: a.ruta == null ? null : const Icon(Icons.chevron_right),
                  onTap: a.ruta == null ? null : () => context.push(a.ruta!),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

const _ajustes = [
  ('fin_ciclo_escolar', 'Fin del ciclo escolar', 'Después de esta fecha se borran las fotos de identificación de quien ya no debe nada.'),
  ('hora_fin_jornada', 'Hora de fin de la jornada', 'Vencimiento de los préstamos "para hoy" y de los códigos "hoy más tarde".'),
  ('plazo_default_dias', 'Días de préstamo que se proponen', 'Lo que ve el alumno al pedir.'),
  ('plazo_max_alumno_dias', 'Máximo de días para alumnos', ''),
  ('plazo_max_maestro_dias', 'Máximo de días para maestros', ''),
  ('url_app', 'Dirección de la app web', 'Los enlaces de los correos apuntan aquí.'),
  ('nombre_escuela', 'Nombre de la escuela', 'Va en el encabezado de los reportes y actas.'),
  ('programa_escuela', 'Programa', 'Segunda línea del encabezado de los reportes.'),
  ('nombre_laboratorio', 'Nombre del laboratorio', ''),
];

/// Ajustes que cambia sub administración (con contraseña reconfirmada).
class AjustesPantalla extends ConsumerWidget {
  const AjustesPantalla({super.key});

  Future<void> _cambiar(BuildContext context, WidgetRef ref, String clave, String titulo, Object? actual) async {
    Object? nuevo;
    if (clave == 'fin_ciclo_escolar') {
      final hoy = DateTime.now();
      final dia = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse('$actual') ?? hoy,
        firstDate: DateTime(hoy.year - 1),
        lastDate: DateTime(hoy.year + 3),
        helpText: titulo,
      );
      if (dia != null) nuevo = '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
    } else if (clave == 'hora_fin_jornada') {
      final partes = '$actual'.split(':');
      final h = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.tryParse(partes.first) ?? 15, minute: int.tryParse(partes.last) ?? 0),
        helpText: titulo,
      );
      if (h != null) nuevo = '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
    } else {
      final texto = await pedirTexto(context, titulo: titulo, etiqueta: clave == 'url_app' ? 'https://…' : (clave.startsWith('nombre_') || clave == 'programa_escuela' ? 'Nombre' : 'Días'), boton: 'Guardar');
      if (texto != null) nuevo = clave == 'url_app' ? texto : int.tryParse(texto) ?? texto;
    }
    if (nuevo == null || !context.mounted) return;
    try {
      final hecho = await conAcceso<bool>(context, ref,
          descripcion: 'cambiar "$titulo"',
          requisito: const Requisito(Nivel.contrasena, roles: {Rol.subadmin}, confirmar: true), accion: () async {
        await ref.read(repositorioProvider).cambiarConfiguracion(clave, nuevo!);
        return true;
      });
      if (hecho == true && context.mounted) {
        ref.invalidate(configuracionProvider);
        avisar(context, 'Guardado.');
      }
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configuracionProvider);
    return TmArmazon(
      ruta: '/ajustes',
      titulo: 'Ajustes',
      child: Centrado(
        child: config.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (c) => ListView(children: [
            for (final a in _ajustes)
              ListTile(
                title: Text(a.$2),
                subtitle: Text([
                  switch (a.$1) {
                    'fin_ciclo_escolar' => DateTime.tryParse('${c[a.$1]}') == null ? '${c[a.$1]}' : fecha(DateTime.parse('${c[a.$1]}')),
                    _ => '${c[a.$1] ?? 'sin definir'}',
                  },
                  if (a.$3.isNotEmpty) a.$3,
                ].join('\n')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _cambiar(context, ref, a.$1, a.$2, c[a.$1]),
              ),
          ]),
        ),
      ),
    );
  }
}
