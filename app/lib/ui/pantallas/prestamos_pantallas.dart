import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../armazon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/movimientos.dart';
import '../../util/texto.dart';
import '../tema.dart';
import '../widgets/formularios.dart';

/// Lo que tengo a mi nombre y lo que presté a alumnos o maestros.
class MisPrestamosPantalla extends StatelessWidget {
  const MisPrestamosPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return TmArmazon(
      ruta: '/mis-prestamos',
      titulo: 'Mis préstamos',
      child: Centrado(
        child: CargaConAcceso<List<PrestamoListado>>(
          descripcion: 'ver tus préstamos',
          requisito: Requisito.docente,
          cargar: (repo) => repo.misPrestamos(),
          construir: (context, lista, recargar) => _ListaPrestamos(lista: lista, recargar: recargar, vacio: 'No tienes préstamos abiertos.'),
        ),
      ),
    );
  }
}

/// Todo lo que está fuera del taller (responsable y sub administración).
class PrestamosAbiertosPantalla extends StatelessWidget {
  const PrestamosAbiertosPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return TmArmazon(
      ruta: '/prestamos-abiertos',
      titulo: 'Préstamos abiertos',
      child: Centrado(
        child: CargaConAcceso<List<PrestamoListado>>(
          descripcion: 'ver los préstamos abiertos',
          requisito: Requisito.administracion,
          cargar: (repo) => repo.prestamosAbiertos(),
          construir: (context, lista, recargar) => _ListaPrestamos(lista: lista, recargar: recargar, vacio: 'No hay nada prestado.'),
        ),
      ),
    );
  }
}

class _ListaPrestamos extends ConsumerWidget {
  const _ListaPrestamos({required this.lista, required this.recargar, required this.vacio});

  final List<PrestamoListado> lista;
  final Future<void> Function() recargar;
  final String vacio;

  Future<void> _extender(BuildContext context, WidgetRef ref, PrestamoListado p) async {
    final fechaNueva = await elegirFechaDevolucion(context, desde: p.venceEn.isAfter(DateTime.now()) ? p.venceEn : null);
    if (fechaNueva == null || !context.mounted) return;
    final motivo = await pedirTexto(context, titulo: 'Extender hasta el ${fecha(fechaNueva)}', etiqueta: 'Por qué se extiende *', boton: 'Extender');
    if (motivo == null || !context.mounted) return;
    try {
      final hecho = await conAcceso<bool>(context, ref, descripcion: 'extender el préstamo de "${p.nombre}"', requisito: Requisito.docente,
          accion: () async {
        await ref.read(repositorioProvider).extenderPrestamo(p.id, fechaNueva, motivo);
        return true;
      });
      if (hecho == true && context.mounted) {
        ref.invalidate(vencidosProvider);
        avisar(context, 'Préstamo extendido hasta el ${fecha(fechaNueva)}.');
        await recargar();
      }
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    if (lista.isEmpty) {
      return ListView(children: [
        TmVacio(
          icono: Ico.prestamos,
          titulo: vacio,
          texto: 'Cuando salga material del taller, aparece aquí con su fecha de regreso.',
          acciones: [
            TmBoton('Prestar', tipo: TipoBoton.primario, icono: Ico.prestar, onTap: () => context.push('/prestar')),
            TmBoton('Ir al inventario', icono: Ico.inventario, onTap: () => context.push('/inventario')),
          ],
        ),
      ]);
    }
    final vencidos = lista.where((p) => p.vencido).length;
    return ListView(padding: const EdgeInsets.all(Espacio.x3), children: [
      if (vencidos > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: Espacio.x3),
          child: TmAlerta(
            titulo: '$vencidos préstamo${vencidos == 1 ? '' : 's'} vencido${vencidos == 1 ? '' : 's'}',
            texto: 'Material que ya debió regresar al taller.',
            tono: Tono.error,
            icono: Ico.reloj,
          ),
        ),
      for (final p in lista)
        Padding(
          padding: const EdgeInsets.only(bottom: Espacio.x3),
          child: TmTarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TmAvatar(p.aMiNombre ? 'Tú' : p.aCargo),
                const SizedBox(width: Espacio.x3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${conUnidad(p.pendiente, p.unidad)} · ${p.nombre}', style: tema.textTheme.titleMedium),
                    Text('${p.codigo} · a cargo de ${p.aMiNombre ? 'ti' : p.aCargo}${p.autorizo == null ? '' : ' · prestó ${p.autorizo}'}',
                        style: tema.textTheme.bodySmall),
                  ]),
                ),
              ]),
              const SizedBox(height: Espacio.x2),
              // Una sola vez la fecha, en una insignia debajo del nombre (al lado apretaba el nombre en el celular).
              Wrap(spacing: Espacio.x2, runSpacing: Espacio.x1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                TmInsignia(
                  '${p.vencido ? 'Vencido desde' : 'Vence'} ${fechaHora(p.venceEn)}',
                  tono: p.vencido ? Tono.error : Tono.neutro,
                  icono: p.vencido ? Ico.alerta : Ico.reloj,
                ),
                if (p.extensiones > 0) Text('extendido ${p.extensiones} ${p.extensiones == 1 ? 'vez' : 'veces'}', style: tema.textTheme.bodySmall),
              ]),
              const SizedBox(height: Espacio.x2),
              Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
                TmBoton('Recibir devolución', tamano: TamanoBoton.chico, icono: Ico.devolver, onTap: () async {
                  // Al regresar de la devolución, la lista se vuelve a leer.
                  await context.push('/articulo/${p.articuloId}/devolver');
                  await recargar();
                }),
                TmBoton('Extender', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.reloj, onTap: () => _extender(context, ref, p)),
                if (p.autorizo != null)
                  TmBoton('Expediente', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, onTap: () => context.push('/expediente/${p.id}')),
              ]),
            ]),
          ),
        ),
    ]);
  }
}
