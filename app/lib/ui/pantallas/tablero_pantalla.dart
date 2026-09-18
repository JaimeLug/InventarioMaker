import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../acceso/sesion.dart';
import '../../datos/proveedores.dart';
import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../../modelos/movimientos.dart';
import '../../sin_conexion/cola.dart';
import '../../util/texto.dart';
import '../armazon.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';
import 'inventario_pantalla.dart';

/// Lo primero que se ve al abrir la app.
///
/// Con sesión: el tablero del taller (lo que hay que atender hoy y las cifras).
/// Sin sesión: el catálogo, como siempre (F-01: consultar no necesita cuenta).
class TableroPantalla extends ConsumerWidget {
  const TableroPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).value;
    if (sesion == null) {
      return const TmArmazon(ruta: '/', titulo: 'Catálogo del taller', child: InventarioPantalla(enTablero: true));
    }
    return TmArmazon(
      ruta: '/',
      titulo: 'Tablero',
      acciones: [
        if (MediaQuery.sizeOf(context).width >= Quiebre.compacto)
          Padding(
            padding: const EdgeInsets.only(right: Espacio.x2),
            child: TmBoton('Escanear', icono: Ico.escanear, tamano: TamanoBoton.chico, onTap: () => context.push('/escanear')),
          ),
      ],
      child: _Tablero(sesion: sesion),
    );
  }
}

class _Tablero extends ConsumerWidget {
  const _Tablero({required this.sesion});

  final Sesion sesion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tm;
    final administra = sesion.administra;
    final articulos = ref.watch(articulosProvider);
    final pendientes = ref.watch(pendientesAbiertosProvider).value?.length ?? 0;
    final vencidos = ref.watch(vencidosProvider).value ?? 0;
    final porRevisar = ref.watch(porRevisarProvider).value ?? 0;
    final solicitudes = ref.watch(solicitudesContarProvider).value ?? 0;
    final prestamos = ref.watch(prestamosAbiertosProvider).value ?? const <PrestamoListado>[];
    final mios = ref.watch(misPrestamosProvider).value ?? const <PrestamoListado>[];
    final compacto = MediaQuery.sizeOf(context).width < Quiebre.compacto;
    final anchoKpi = MediaQuery.sizeOf(context).width < Quiebre.rieles ? 2 : 3;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(vencidosProvider);
        ref.invalidate(porRevisarProvider);
        ref.invalidate(solicitudesContarProvider);
        ref.invalidate(avisosSinLeerProvider);
        ref.invalidate(pendientesAbiertosProvider);
        ref.invalidate(prestamosAbiertosProvider);
        ref.invalidate(misPrestamosProvider);
        ref.invalidate(articulosProvider);
        await ref.read(articulosProvider.future);
      },
      child: ListView(padding: const EdgeInsets.all(Espacio.x4), children: [
        Text('Hola, ${sesion.nombreCorto}', style: Tipografia.display.copyWith(color: c.texto)),
        Text('${_saludo()} · la jornada termina a las 15:00', style: Tipografia.cuerpo.copyWith(color: c.textoSecundario)),
        const SizedBox(height: Espacio.x4),

        articulos.when(
          loading: () => const TmCargandoLista(renglones: 3),
          error: (e, _) => TmErrorCarga(
            mensaje: 'No se pudieron leer las cifras del taller. Revisa la conexión.',
            onReintentar: () => ref.invalidate(articulosProvider),
          ),
          data: (todos) {
            final situaciones = {for (final s in SituacionStock.values) s: todos.where((a) => SituacionStock.de(a) == s).length};
            final disponibles = todos.where((a) => a.prestable && a.disponible > 0).length;
            final herramientas = todos.where((a) => a.categoria == Categoria.herramientas || a.categoria == Categoria.herramientasElectricas).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GridView.count(
                crossAxisCount: anchoKpi,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Espacio.x3,
                crossAxisSpacing: Espacio.x3,
                childAspectRatio: compacto ? 1.5 : 1.9,
                children: [
                  TmKpi(etiqueta: 'Artículos', valor: '${todos.length}', pie: 'renglones en 7 categorías', icono: Ico.inventario, onTap: () => context.push('/inventario')),
                  TmKpi(etiqueta: 'Disponibles', valor: '$disponibles', pie: 'listos para prestar', iconoPie: Ico.ok, onTap: () => context.push('/inventario')),
                  TmKpi(
                    etiqueta: 'En su mínimo',
                    valor: '${situaciones[SituacionStock.enMinimo] ?? 0}',
                    pie: 'consumibles por reponer',
                    iconoPie: Ico.aviso,
                    tono: (situaciones[SituacionStock.enMinimo] ?? 0) > 0 ? TonoKpi.atencion : TonoKpi.normal,
                    onTap: () => context.push('/inventario'),
                  ),
                  TmKpi(
                    etiqueta: 'Sin existencias',
                    valor: '${(situaciones[SituacionStock.agotado] ?? 0) + (situaciones[SituacionStock.ningunoDisponible] ?? 0)}',
                    pie: 'agotados o todos prestados',
                    iconoPie: Ico.error,
                    tono: TonoKpi.critico,
                    onTap: () => context.push('/inventario'),
                  ),
                  TmKpi(
                    etiqueta: 'Herramientas',
                    valor: '${herramientas.where((a) => a.disponible > 0).length}',
                    pie: 'de ${herramientas.length} en su lugar',
                    iconoPie: Ico.herramientas,
                    onTap: () => context.push('/inventario'),
                  ),
                  if (administra)
                    TmKpi(
                      etiqueta: 'Préstamos',
                      valor: '${prestamos.isEmpty ? vencidos : prestamos.length}',
                      pie: vencidos > 0 ? '$vencidos vencido${vencidos == 1 ? '' : 's'}' : 'ninguno vencido',
                      iconoPie: Ico.reloj,
                      tono: vencidos > 0 ? TonoKpi.critico : TonoKpi.normal,
                      onTap: () => context.push('/prestamos-abiertos'),
                    )
                  else
                    TmKpi(
                      etiqueta: 'Mis préstamos',
                      valor: '${mios.length}',
                      pie: mios.any((p) => p.vencido) ? 'tienes uno vencido' : 'a tu nombre',
                      iconoPie: Ico.prestamos,
                      tono: mios.any((p) => p.vencido) ? TonoKpi.critico : TonoKpi.normal,
                      onTap: () => context.push('/mis-prestamos'),
                    ),
                ],
              ),
              const SizedBox(height: Espacio.x4),
              _AtenderHoy(
                vencidos: vencidos,
                porRevisar: porRevisar,
                solicitudes: solicitudes,
                pendientes: pendientes,
                bajoMinimo: todos.where((a) => SituacionStock.de(a) == SituacionStock.enMinimo || SituacionStock.de(a) == SituacionStock.agotado).toList(),
                administra: administra,
              ),
              const SizedBox(height: Espacio.x4),
              if (MediaQuery.sizeOf(context).width >= Quiebre.lateral)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _PorCategoria(todos: todos)),
                  const SizedBox(width: Espacio.x4),
                  Expanded(flex: 2, child: Column(children: [_Rapidos(administra: administra), const SizedBox(height: Espacio.x4), _Proximos(prestamos: administra ? prestamos : mios, administra: administra)])),
                ])
              else ...[
                _Rapidos(administra: administra),
                const SizedBox(height: Espacio.x4),
                _PorCategoria(todos: todos),
                const SizedBox(height: Espacio.x4),
                _Proximos(prestamos: administra ? prestamos : mios, administra: administra),
              ],
            ]);
          },
        ),
        const SizedBox(height: Espacio.x10),
      ]),
    );
  }

  String _saludo() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Buenos días' : (h < 19 ? 'Buenas tardes' : 'Buenas noches');
  }
}

class _AtenderHoy extends StatelessWidget {
  const _AtenderHoy({
    required this.vencidos,
    required this.porRevisar,
    required this.solicitudes,
    required this.pendientes,
    required this.bajoMinimo,
    required this.administra,
  });

  final int vencidos, porRevisar, solicitudes, pendientes;
  final List<Articulo> bajoMinimo;
  final bool administra;

  @override
  Widget build(BuildContext context) {
    final cola = ColaSinConexion.instancia;
    final avisos = <Widget>[
      if (vencidos > 0)
        TmAlerta(
          titulo: '$vencidos préstamo${vencidos == 1 ? '' : 's'} vencido${vencidos == 1 ? '' : 's'}',
          texto: administra ? 'Material que ya debió regresar.' : 'Revisa si alguno es tuyo.',
          tono: Tono.error,
          icono: Ico.reloj,
          accion: TmBoton('Ver', tamano: TamanoBoton.chico, onTap: () => context.push(administra ? '/prestamos-abiertos' : '/mis-prestamos')),
        ),
      if (cola != null && cola.porResolver.isNotEmpty)
        TmAlerta(
          titulo: '${cola.porResolver.length} registro${cola.porResolver.length == 1 ? '' : 's'} sin enviar',
          texto: 'Algo capturado sin señal no se pudo aplicar.',
          tono: Tono.aviso,
          cinta: true,
          icono: Ico.sinConexion,
          accion: TmBoton('Revisar', tamano: TamanoBoton.chico, onTap: () => context.push('/sin-conexion')),
        ),
      if (bajoMinimo.isNotEmpty)
        TmAlerta(
          titulo: '${bajoMinimo.length} artículo${bajoMinimo.length == 1 ? '' : 's'} sin existencias o en su mínimo',
          texto: bajoMinimo.take(3).map((a) => a.nombre).join(', '),
          tono: Tono.aviso,
          icono: Ico.aviso,
          accion: TmBoton('Ver', tamano: TamanoBoton.chico, onTap: () => context.push('/inventario')),
        ),
      if (administra && porRevisar > 0)
        TmAlerta(
          titulo: '$porRevisar reporte${porRevisar == 1 ? '' : 's'} por revisar',
          texto: 'Pérdidas, daños y consumos esperando tu autorización.',
          tono: Tono.info,
          icono: Ico.reportar,
          accion: TmBoton('Revisar', tamano: TamanoBoton.chico, onTap: () => context.push('/por-revisar')),
        ),
      if (administra && solicitudes > 0)
        TmAlerta(
          titulo: '$solicitudes solicitud${solicitudes == 1 ? '' : 'es'} en la bandeja',
          texto: 'Por revisar o por entregar.',
          tono: Tono.info,
          icono: Ico.solicitudes,
          accion: TmBoton('Abrir', tamano: TamanoBoton.chico, onTap: () => context.push('/solicitudes')),
        ),
      if (pendientes > 0)
        TmAlerta(
          titulo: '$pendientes pendiente${pendientes == 1 ? '' : 's'} del levantamiento',
          texto: 'Contar, verificar, registrar series y etiquetar.',
          tono: Tono.info,
          icono: Ico.pendientes,
          accion: TmBoton('Ver', tamano: TamanoBoton.chico, onTap: () => context.push('/pendientes')),
        ),
    ];
    return TmTarjeta(
      titulo: 'Atender hoy',
      icono: Ico.campana,
      acciones: [if (avisos.isNotEmpty) TmInsignia('${avisos.length}', tono: Tono.error, icono: Ico.alerta)],
      child: avisos.isEmpty
          ? const TmVacio(titulo: 'Todo en orden', texto: 'No hay vencidos, ni reportes por revisar, ni consumibles en su mínimo.', icono: Ico.ok)
          : Column(children: [
              for (final (i, a) in avisos.indexed) ...[
                if (i > 0) const SizedBox(height: Espacio.x2),
                a,
              ],
            ]),
    );
  }
}

class _PorCategoria extends StatelessWidget {
  const _PorCategoria({required this.todos});

  final List<Articulo> todos;

  @override
  Widget build(BuildContext context) {
    final c = context.tm;
    final datos = [
      for (final cat in Categoria.values)
        (cat, todos.where((a) => a.categoria == cat).length, todos.where((a) => a.categoria == cat && a.estadoInventario == EstadoInventario.verificado).length),
    ].where((d) => d.$2 > 0).toList();
    final maximo = datos.fold<int>(1, (m, d) => d.$2 > m ? d.$2 : m);
    return TmTarjeta(
      titulo: 'Artículos por categoría',
      icono: Ico.inventario,
      child: Column(children: [
        for (final (cat, total, verificados) in datos)
          Padding(
            padding: const EdgeInsets.only(bottom: Espacio.x3),
            child: Row(children: [
              SizedBox(width: 150, child: TmCategoria(cat)),
              Expanded(
                child: Semantics(
                  label: '${cat.nombre}: $verificados de $total verificados',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: total / maximo,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(color: c.superficieHundida, borderRadius: BorderRadius.circular(2)),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: verificados / total,
                            child: Container(decoration: BoxDecoration(color: c.exitoRelleno, borderRadius: BorderRadius.circular(2))),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Espacio.x2),
              SizedBox(
                width: 56,
                child: Text('$verificados/$total', style: Tipografia.codigo.copyWith(color: c.textoSecundario), textAlign: TextAlign.right),
              ),
            ]),
          ),
        Row(children: [
          Container(width: 12, height: 10, decoration: BoxDecoration(color: c.exitoRelleno, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: Espacio.x1),
          Text('Verificados', style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoSecundario)),
          const SizedBox(width: Espacio.x3),
          Container(
            width: 12,
            height: 10,
            decoration: BoxDecoration(color: c.superficieHundida, borderRadius: BorderRadius.circular(2), border: Border.all(color: c.bordeFuerte)),
          ),
          const SizedBox(width: Espacio.x1),
          Text('Falta verificar', style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.textoSecundario)),
        ]),
      ]),
    );
  }
}

class _Rapidos extends StatelessWidget {
  const _Rapidos({required this.administra});

  final bool administra;

  @override
  Widget build(BuildContext context) => TmTarjeta(
        titulo: 'Accesos rápidos',
        icono: Ico.escanear,
        child: Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
          TmBoton('Escanear', icono: Ico.escanear, tamano: TamanoBoton.grande, onTap: () => context.push('/escanear')),
          TmBoton('Contar', icono: Ico.contar, tamano: TamanoBoton.grande, onTap: () => context.push('/conteos')),
          TmBoton('Pendientes', icono: Ico.pendientes, tamano: TamanoBoton.grande, onTap: () => context.push('/pendientes')),
          if (administra) TmBoton('Nuevo artículo', icono: Ico.nuevo, tamano: TamanoBoton.grande, onTap: () => context.push('/articulo/nuevo')),
          if (administra) TmBoton('Reportes', icono: Ico.reportes, tamano: TamanoBoton.grande, onTap: () => context.push('/reportes')),
        ]),
      );
}

class _Proximos extends StatelessWidget {
  const _Proximos({required this.prestamos, required this.administra});

  final List<PrestamoListado> prestamos;
  final bool administra;

  @override
  Widget build(BuildContext context) {
    final orden = [...prestamos]..sort((a, b) => a.venceEn.compareTo(b.venceEn));
    final lista = orden.take(5).toList();
    return TmTarjeta(
      titulo: administra ? 'Próximos a vencer' : 'Mis préstamos',
      icono: Ico.reloj,
      acciones: [
        TmBoton('Ver todos', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, onTap: () => context.push(administra ? '/prestamos-abiertos' : '/mis-prestamos')),
      ],
      sinPadding: true,
      child: lista.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(Espacio.x4),
              child: TmVacio(titulo: 'Nada prestado', texto: 'Cuando salga material, aparece aquí con su fecha de regreso.', icono: Ico.prestamos),
            )
          : Column(children: [
              for (final p in lista)
                ListTile(
                  leading: TmAvatar(p.aCargo),
                  title: Text('${p.nombre} ×${p.pendiente}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${p.aCargo} · ${p.codigo}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: TmInsignia(
                    p.vencido ? 'Vencido' : 'Vence ${fecha(p.venceEn)}',
                    tono: p.vencido ? Tono.error : Tono.neutro,
                    icono: p.vencido ? Ico.alerta : Ico.reloj,
                  ),
                  onTap: () => context.push('/articulo/${p.articuloId}'),
                ),
              const SizedBox(height: Espacio.x2),
            ]),
    );
  }
}
