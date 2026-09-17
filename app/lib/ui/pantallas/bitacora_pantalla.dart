import 'package:flutter/material.dart';

import '../../acceso/sesion.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';

const _eventos = {
  'EDICION': 'Edición de datos',
  'ACCESO_PIN': 'Entró con PIN',
  'PIN_FALLIDO': 'PIN incorrecto',
  'PIN_BLOQUEADO': 'PIN bloqueado por intentos',
  'PIN_ESTABLECIDO': 'PIN asignado',
  'CONTRASENA_FALLIDA': 'Contraseña incorrecta al confirmar',
  'CUENTA_CREADA': 'Cuenta creada',
  'CUENTA_DESACTIVADA': 'Cuenta desactivada',
  'CUENTA_REACTIVADA': 'Cuenta reactivada',
  'SOLICITANTE_CREADO': 'Alumno o maestro registrado',
  'CONTEO': 'Conteo físico',
  'BAJA_TOTAL': 'Baja total',
  'BAJA_PARCIAL': 'Baja parcial',
  'REACTIVACION': 'Artículo reactivado',
};

/// Bitácora completa (solo sub administración).
class BitacoraPantalla extends StatelessWidget {
  const BitacoraPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bitácora')),
      body: Centrado(
        child: CargaConAcceso<List<EventoBitacora>>(
          descripcion: 'ver la bitácora',
          requisito: Requisito.subadministracion,
          cargar: (repo) => repo.bitacora(),
          construir: (context, lista, _) => ListView.separated(
            itemCount: lista.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == lista.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Se muestran los últimos ${lista.length} eventos.', textAlign: TextAlign.center),
                );
              }
              final e = lista[i];
              final nombre = _eventos[e.evento] ??
                  (e.evento.startsWith('CUENTA_') ? 'Autorización de cuenta' : e.evento.replaceAll('_', ' ').toLowerCase());
              final justificacion = e.datos?['justificacion'];
              return ListTile(
                title: Text([nombre, if (e.referencia != null) e.referencia!].join(' · ')),
                subtitle: Text([
                  '${fechaHora(e.en)} · ${e.usuario ?? 'Sistema'}',
                  if (justificacion is String) 'Justificación: $justificacion',
                  if (e.evento == 'EDICION' && e.datos?['cambios'] is Map)
                    'Cambió: ${(e.datos!['cambios'] as Map).keys.join(', ')}',
                ].join('\n')),
              );
            },
          ),
        ),
      ),
    );
  }
}
