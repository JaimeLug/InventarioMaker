import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../datos/proveedores.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../util/texto.dart';
import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';

/// Herramientas como un tablero de taller: cada una tiene su lugar y se ve de un vistazo
/// cuál está fuera. Es la misma información del inventario, vista como el tablero del taller.
class HerramientasPantalla extends ConsumerWidget {
  const HerramientasPantalla({super.key});

  static const _grupos = <String, (String, IconData)>{
    'Mano': ('Herramienta de mano', Ico.herramientas),
    'Medición': ('Medición', Ico.contar),
    'Soldadura': ('Soldadura y electrónica', Ico.reportar),
    'Impresión 3D': ('Fabricación', Ico.imprimir),
    'Corte': ('Corte y taladro', Ico.escanear),
    'Seguridad': ('Seguridad', Ico.verificado),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articulos = ref.watch(articulosProvider);
    return TmArmazon(
      ruta: '/herramientas',
      titulo: 'Herramientas',
      acciones: [
        Padding(
          padding: const EdgeInsets.only(right: Espacio.x2),
          child: TmBoton('Ver como lista', icono: Ico.inventario, tamano: TamanoBoton.chico, onTap: () => context.push('/inventario')),
        ),
      ],
      child: articulos.when(
        loading: () => ListView(padding: const EdgeInsets.all(Espacio.x4), children: const [TmCargandoLista()]),
        error: (e, _) =>
            TmErrorCarga(mensaje: 'No se pudo leer el taller. Revisa la conexión.', onReintentar: () => ref.invalidate(articulosProvider)),
        data: (todos) {
          final herramientas = todos.where((a) => a.categoria == Categoria.herramientas || a.categoria == Categoria.herramientasElectricas).toList()
            ..sort((x, y) => x.nombre.compareTo(y.nombre));
          if (herramientas.isEmpty) {
            return const TmVacio(
              titulo: 'Todavía no hay herramientas',
              texto: 'Las que estén en las categorías Herramientas y Herramientas eléctricas aparecen aquí.',
              icono: Ico.herramientas,
            );
          }

          final enSuLugar = herramientas.where((a) => !a.noSePresta && a.disponible > 0).length;
          final prestadas = herramientas.fold<int>(0, (s, a) => s + a.prestado);
          final fuera = herramientas.fold<int>(0, (s, a) => s + a.fueraServicio);
          final fijas = herramientas.where((a) => a.noSePresta).length;

          // Se agrupan por subcategoría; lo que no cae en un grupo conocido queda en "Otras".
          final porGrupo = <String, List<Articulo>>{};
          for (final a in herramientas) {
            final clave = _grupos.keys.firstWhere(
              (k) =>
                  (a.subcategoria ?? '').toLowerCase().contains(k.toLowerCase()) ||
                  (k == 'Mano' && (a.subcategoria ?? '').toLowerCase().contains('manual')),
              orElse: () => 'Otras',
            );
            (porGrupo[clave] ??= []).add(a);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(articulosProvider);
              await ref.read(articulosProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(Espacio.x4),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width < Quiebre.compacto ? 2 : 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Espacio.x3,
                  crossAxisSpacing: Espacio.x3,
                  childAspectRatio: MediaQuery.sizeOf(context).width < Quiebre.compacto ? 2.1 : 2.3,
                  children: [
                    TmKpi(etiqueta: 'En su lugar', valor: '$enSuLugar', pie: 'listas para usarse', iconoPie: Ico.ok),
                    TmKpi(
                      etiqueta: 'Prestadas',
                      valor: '$prestadas',
                      pie: 'fuera del taller',
                      iconoPie: Ico.prestamos,
                      tono: prestadas > 0 ? TonoKpi.atencion : TonoKpi.normal,
                    ),
                    TmKpi(
                      etiqueta: 'Fuera de servicio',
                      valor: '$fuera',
                      pie: 'esperan reparación',
                      iconoPie: Ico.aviso,
                      tono: fuera > 0 ? TonoKpi.critico : TonoKpi.normal,
                    ),
                    TmKpi(etiqueta: 'Equipo fijo', valor: '$fijas', pie: 'no sale del taller', iconoPie: Ico.noSePresta),
                  ],
                ),
                const SizedBox(height: Espacio.x4),
                const _Leyenda(),
                const SizedBox(height: Espacio.x4),
                for (final clave in [..._grupos.keys.where(porGrupo.containsKey), if (porGrupo.containsKey('Otras')) 'Otras'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.x4),
                    child: _Tablero(
                      titulo: _grupos[clave]?.$1 ?? 'Otras herramientas',
                      icono: _grupos[clave]?.$2 ?? Ico.herramientas,
                      herramientas: porGrupo[clave]!,
                    ),
                  ),
                const SizedBox(height: Espacio.x10),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    Widget punto(Color borde, Color fondo, String texto, {bool punteado = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 12,
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: borde, width: 1.5),
          ),
          child: punteado ? CustomPaint(painter: _Rayas(borde)) : null,
        ),
        const SizedBox(width: 5),
        Text(texto, style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoSecundario)),
      ],
    );
    return Wrap(
      spacing: Espacio.x4,
      runSpacing: Espacio.x2,
      children: [
        punto(c.deCategoria(Categoria.herramientas), c.avisoSuave, 'En su lugar'),
        punto(c.infoRelleno, c.infoSuave, 'Prestada', punteado: true),
        punto(c.bordeFuerte, c.superficieHundida, 'Fuera de servicio'),
        punto(c.bordeFuerte, c.superficie, 'Equipo fijo'),
      ],
    );
  }
}

class _Rayas extends CustomPainter {
  _Rayas(this.color);

  final Color color;

  @override
  void paint(Canvas lienzo, Size t) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var x = -t.height; x < t.width; x += 4) {
      lienzo.drawLine(Offset(x, t.height), Offset(x + t.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_Rayas anterior) => anterior.color != color;
}

/// Un tablero perforado con las herramientas de un tipo.
class _Tablero extends StatelessWidget {
  const _Tablero({required this.titulo, required this.icono, required this.herramientas});

  final String titulo;
  final IconData icono;
  final List<Articulo> herramientas;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    return Container(
      padding: const EdgeInsets.all(Espacio.x4),
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: Redondeo.rLg,
        border: Border.all(color: c.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 20, color: c.textoSecundario),
              const SizedBox(width: Espacio.x2),
              Text(titulo.toUpperCase(), style: Tipografia.etiqueta.copyWith(fontSize: 14, color: c.texto)),
              const SizedBox(width: Espacio.x2),
              Text('${herramientas.length}', style: Tipografia.codigo.copyWith(color: c.textoTenue)),
            ],
          ),
          const SizedBox(height: Espacio.x3),
          Wrap(
            spacing: Espacio.x3,
            runSpacing: Espacio.x3,
            children: [for (final h in herramientas) SizedBox(width: 196, child: _Hueco(articulo: h))],
          ),
        ],
      ),
    );
  }
}

/// El "hueco" de una herramienta: contorno punteado cuando no está en su lugar.
class _Hueco extends StatelessWidget {
  const _Hueco({required this.articulo});

  final Articulo articulo;

  @override
  Widget build(BuildContext context) {
    final a = articulo;
    final c = context.tm;
    final situacion = SituacionStock.de(a);
    final enTaller = a.existencia - a.prestado - a.fueraServicio;
    final (borde, fondo, punteado, detalle, tono) = switch (situacion) {
      SituacionStock.noSePresta => (c.bordeFuerte, c.superficie, false, 'Equipo fijo: no sale del taller', c.textoSecundario),
      SituacionStock.agotado || SituacionStock.ningunoDisponible when a.prestado > 0 => (
        c.infoRelleno,
        c.infoSuave,
        true,
        a.prestadoHasta == null ? 'Prestada' : 'Prestada · regresa ${fecha(a.prestadoHasta!)}',
        c.info,
      ),
      SituacionStock.agotado || SituacionStock.ningunoDisponible => (c.bordeFuerte, c.superficieHundida, false, 'Fuera de servicio', c.textoTenue),
      SituacionStock.sinContar => (c.bordeFuerte, c.superficie, false, 'Sin contar', c.textoTenue),
      _ => (
        c.deCategoria(Categoria.herramientas),
        Color.alphaBlend(c.avisoSuave.withValues(alpha: .6), c.superficie),
        false,
        [
          '$enTaller en su lugar',
          if (a.prestado > 0) '${a.prestado} prestada${a.prestado == 1 ? '' : 's'}',
          if (a.fueraServicio > 0) '${a.fueraServicio} fuera',
        ].join(' · '),
        c.exito,
      ),
    };

    return Semantics(
      button: true,
      label: '${a.nombre}. $detalle',
      child: InkWell(
        onTap: () => context.push('/articulo/${a.id}'),
        borderRadius: Redondeo.rMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 76,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fondo, borderRadius: Redondeo.rMd),
              foregroundDecoration: BoxDecoration(
                borderRadius: Redondeo.rMd,
                border: punteado ? null : Border.all(color: borde, width: 1.5),
              ),
              child: CustomPaint(
                painter: punteado ? _Punteado(borde) : null,
                child: Center(child: Icon(Ico.deSubcategoria(a.subcategoria), size: 30, color: tono)),
              ),
            ),
            const SizedBox(height: Espacio.x2),
            Text(
              a.nombre,
              style: Tipografia.chicoFuerte.copyWith(color: c.texto),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (a.marcaModelo != null)
              Text(
                a.marcaModelo!,
                style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoTenue),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(situacion.icono, size: 14, color: tono),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    detalle,
                    style: Tipografia.chicoFuerte.copyWith(fontSize: 12.5, color: tono),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Contorno punteado: la herramienta no está en su hueco.
class _Punteado extends CustomPainter {
  _Punteado(this.color);

  final Color color;

  @override
  void paint(Canvas lienzo, Size t) {
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rect = RRect.fromRectAndRadius(Offset.zero & t, const Radius.circular(Redondeo.md));
    final camino = Path()..addRRect(rect);
    for (final metrica in camino.computeMetrics()) {
      for (var d = 0.0; d < metrica.length; d += 10) {
        lienzo.drawPath(metrica.extractPath(d, d + 5), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_Punteado anterior) => anterior.color != color;
}
