import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/gate.dart';
import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../datos/repositorio.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/propuestas.dart';
import '../../util/texto.dart';
import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/formularios.dart';

/// Fase 11. Lo que propone la selección de robótica:
/// el responsable acepta o descarta; quien propone ve cómo va lo suyo.
class PropuestasPantalla extends ConsumerWidget {
  const PropuestasPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).value;
    final revisa = sesion?.administra ?? false;
    final propuestas = ref.watch(propuestasProvider);
    final fotos = ref.watch(fotosPorVerificarProvider);

    return TmArmazon(
      ruta: '/propuestas',
      titulo: revisa ? 'Propuestas' : 'Mis propuestas',
      child: Centrado(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(propuestasProvider);
            ref.invalidate(fotosPorVerificarProvider);
          },
          child: Cargando<List<Propuesta>>(
            valor: propuestas,
            alReintentar: () => ref.invalidate(propuestasProvider),
            datos: (lista) {
              final porVerificar = fotos.value ?? const <FotoPorVerificar>[];
              if (lista.isEmpty && porVerificar.isEmpty) {
                return ListView(children: [
                  TmVacio(
                    icono: Ico.revisar,
                    titulo: revisa ? 'No hay nada por revisar' : 'Todavía no has propuesto nada',
                    texto: revisa
                        ? 'Aquí llegan los artículos, las correcciones y las fotos que propone la selección de robótica.'
                        : 'Desde una ficha puedes agregar fotos o proponer una corrección, y desde el tablero, un artículo nuevo. Aquí verás cómo va cada cosa.',
                    acciones: [
                      if (!revisa)
                        TmBoton('Proponer un artículo', tipo: TipoBoton.primario, icono: Ico.articuloNuevo,
                            onTap: () => context.push('/articulo/nuevo')),
                    ],
                  ),
                ]);
              }
              return ListView(padding: const EdgeInsets.all(Espacio.x3), children: [
                if (porVerificar.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.x2),
                    child: Text(revisa ? 'FOTOS POR VERIFICAR (${porVerificar.length})' : 'MIS FOTOS, ESPERANDO VISTO BUENO (${porVerificar.length})',
                        style: Tipografia.etiqueta.copyWith(color: context.tm.textoTenue)),
                  ),
                  for (final f in porVerificar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espacio.x3),
                      child: _TarjetaFoto(foto: f, revisa: revisa),
                    ),
                ],
                if (lista.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.x2),
                    child: Text('PROPUESTAS (${lista.length})', style: Tipografia.etiqueta.copyWith(color: context.tm.textoTenue)),
                  ),
                  for (final p in lista)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espacio.x3),
                      child: _TarjetaPropuesta(propuesta: p, revisa: revisa),
                    ),
                ],
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _TarjetaPropuesta extends ConsumerWidget {
  const _TarjetaPropuesta({required this.propuesta, required this.revisa});

  final Propuesta propuesta;
  final bool revisa;

  Future<void> _aprobar(BuildContext context, WidgetRef ref) async {
    final hecho = await conAcceso<bool>(
      context,
      ref,
      descripcion: 'aceptar "${propuesta.nombre}"',
      requisito: Requisito.administracionConfirmada,
      accion: () async {
        await ref.read(repositorioProvider).aprobarPropuesta(propuesta.id);
        return true;
      },
    );
    if (hecho == true && context.mounted) {
      ref.invalidate(propuestasProvider);
      ref.invalidate(articulosProvider);
      avisar(context, propuesta.esAlta ? 'Listo: el artículo entró al inventario.' : 'Listo: los cambios quedaron guardados.');
    }
  }

  Future<void> _descartar(BuildContext context, WidgetRef ref) async {
    final motivo = await pedirTexto(context,
        titulo: 'No procede', etiqueta: 'Por qué no procede *', boton: 'Descartar');
    if (motivo == null || !context.mounted) return;
    try {
      await ref.read(repositorioProvider).descartarPropuesta(propuesta.id, motivo);
      if (!context.mounted) return;
      ref.invalidate(propuestasProvider);
      avisar(context, 'Descartada. Se le avisó a quien la propuso.');
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tm;
    final tema = Theme.of(context);
    final datos = propuesta.datos;
    final categoria = datos['categoria'] as String?;

    return TmTarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(propuesta.nombre, style: tema.textTheme.titleMedium),
              Text(
                '${propuesta.esAlta ? 'Artículo nuevo' : 'Corrección de ${propuesta.codigo ?? ''}'}'
                ' · ${propuesta.creadaPor} · ${fechaHora(propuesta.creadaEn)}',
                style: tema.textTheme.bodySmall,
              ),
            ]),
          ),
          TmInsignia(
            switch (propuesta.estado) { 'APROBADA' => 'Aceptada', 'DESCARTADA' => 'No procedió', _ => 'Pendiente' },
            tono: switch (propuesta.estado) { 'APROBADA' => Tono.ok, 'DESCARTADA' => Tono.error, _ => Tono.aviso },
            icono: switch (propuesta.estado) { 'APROBADA' => Ico.ok, 'DESCARTADA' => Ico.error, _ => Ico.enEspera },
          ),
        ]),
        const SizedBox(height: Espacio.x2),
        if (propuesta.fotos.isNotEmpty)
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: propuesta.fotos.length,
              separatorBuilder: (_, _) => const SizedBox(width: Espacio.x2),
              itemBuilder: (_, i) => Miniatura(ruta: propuesta.fotos[i], tamano: 88),
            ),
          ),
        const SizedBox(height: Espacio.x2),
        // Qué propone, campo por campo, para poder compararlo de un vistazo.
        Wrap(spacing: Espacio.x2, runSpacing: Espacio.x1, children: [
          if (categoria != null) TmCategoria(Categoria.desde(categoria)),
          if (propuesta.cantidad != null) TmInsignia('${propuesta.cantidad} ${datos['unidad'] ?? 'pieza(s)'}', tono: Tono.neutro),
          for (final campo in datos.keys.where((k) => k != 'nombre' && k != 'categoria' && k != 'unidad'))
            if ('${datos[campo]}'.trim().isNotEmpty) TmInsignia('${_nombreCampo(campo)}: ${datos[campo]}', tono: Tono.neutro),
        ]),
        if (propuesta.nota != null) ...[
          const SizedBox(height: Espacio.x2),
          Text(propuesta.nota!, style: tema.textTheme.bodySmall),
        ],
        if (propuesta.motivo != null) ...[
          const SizedBox(height: Espacio.x2),
          Text('No procedió: ${propuesta.motivo}', style: tema.textTheme.bodySmall?.copyWith(color: c.error)),
        ],
        if (revisa && propuesta.estado == 'PENDIENTE') ...[
          const SizedBox(height: Espacio.x3),
          Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
            TmBoton('Aceptar', tipo: TipoBoton.primario, tamano: TamanoBoton.chico, icono: Ico.ok,
                onTap: () => _aprobar(context, ref)),
            TmBoton('No procede', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.error,
                onTap: () => _descartar(context, ref)),
            if (propuesta.articuloId != null)
              TmBoton('Ver la ficha', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.avanzar,
                  onTap: () => context.push('/articulo/${propuesta.articuloId}')),
          ]),
        ],
      ]),
    );
  }
}

class _TarjetaFoto extends ConsumerWidget {
  const _TarjetaFoto({required this.foto, required this.revisa});

  final FotoPorVerificar foto;
  final bool revisa;

  Future<void> _resolver(BuildContext context, WidgetRef ref, {required bool aceptar}) async {
    String? motivo;
    if (!aceptar) {
      motivo = await pedirTexto(context, titulo: 'Descartar la foto', etiqueta: 'Por qué se descarta *', boton: 'Descartar');
      if (motivo == null) return;
    }
    if (!context.mounted) return;
    try {
      await ref.read(repositorioProvider).verificarFoto(foto.id, aceptar: aceptar, motivo: motivo);
      if (!context.mounted) return;
      ref.invalidate(fotosPorVerificarProvider);
      refrescarArticulo(ref, foto.articuloId);
      avisar(context, aceptar ? 'Foto verificada.' : 'Foto descartada.');
    } on Object catch (e) {
      if (context.mounted) avisarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    return TmTarjeta(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Miniatura(ruta: foto.url, tamano: 72),
        const SizedBox(width: Espacio.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(foto.nombre, style: tema.textTheme.titleSmall),
            Text('${foto.codigo} · ${foto.tomadaPor} · ${fechaHora(foto.tomadaEn)}', style: tema.textTheme.bodySmall),
            const SizedBox(height: Espacio.x2),
            Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
              if (!revisa) const TmInsignia('Sin verificar', tono: Tono.aviso, icono: Ico.enEspera),
              if (revisa)
                TmBoton('Verificar', tipo: TipoBoton.primario, tamano: TamanoBoton.chico, icono: Ico.ok,
                    onTap: () => _resolver(context, ref, aceptar: true)),
              if (revisa)
                TmBoton('Descartar', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.error,
                    onTap: () => _resolver(context, ref, aceptar: false)),
              TmBoton('Ver la ficha', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, icono: Ico.avanzar,
                  onTap: () => context.push('/articulo/${foto.articuloId}')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

String _nombreCampo(String campo) => switch (campo) {
      'marca_modelo' => 'Marca',
      'subcategoria' => 'Subcategoría',
      'num_serie' => 'Serie',
      'num_resguardo' => 'Resguardo',
      'estado_fisico' => 'Estado',
      'observaciones' => 'Nota',
      'ubicacion' => 'Dónde está',
      'etiquetado' => 'Etiqueta',
      'es_consumible' => 'Consumible',
      'minimo_reposicion' => 'Mínimo',
      _ => campo,
    };
