import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../acceso/hoja_acceso.dart';
import '../acceso/sesion.dart';
import '../datos/local.dart';
import '../datos/proveedores.dart';
import '../modelos/catalogos.dart';
import '../sin_conexion/cola.dart';
import '../util/texto.dart';
import 'componentes/componentes.dart';
import 'diseno/iconos.dart';
import 'diseno/tipografia.dart';
import 'diseno/tokens.dart';
import 'widgets/comunes.dart';

/// El armazón de todas las pantallas: navegación según el rol, barra superior con
/// avisos y sesión, y el aviso de "sin conexión". Fase 7b.
class TmArmazon extends ConsumerWidget {
  const TmArmazon({
    super.key,
    required this.ruta,
    required this.titulo,
    required this.child,
    this.subtitulo,
    this.acciones = const [],
    this.fab,
    this.migas = const [],
    this.conRegresar = false,
    this.anchoContenido = 1560.0,
  });

  /// La ruta de esta pantalla, para marcar dónde estás.
  final String ruta;
  final String titulo;
  final String? subtitulo;
  final Widget child;
  final List<Widget> acciones;
  final Widget? fab;

  /// Migas: [('Inventario', '/inventario')] antes del título.
  final List<(String, String)> migas;
  final bool conRegresar;
  final double anchoContenido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tm;
    final sesion = ref.watch(sesionProvider).value;
    final administra = sesion?.administra ?? false;
    final subadmin = sesion?.rol == Rol.subadmin;
    final vencidos = ref.watch(vencidosProvider).value ?? 0;
    final porRevisar = ref.watch(porRevisarProvider).value ?? 0;
    final solicitudes = ref.watch(solicitudesContarProvider).value ?? 0;
    final pendientes = ref.watch(pendientesAbiertosProvider).value?.length ?? 0;

    final grupos = <TmGrupoNav>[
      TmGrupoNav('Operación', [
        TmDestino('/', sesion == null ? 'Catálogo' : 'Tablero', Ico.tablero),
        if (sesion != null) TmDestino('/inventario', 'Inventario', Ico.inventario),
        TmDestino('/escanear', 'Escanear', Ico.escanear),
        if (sesion == null) TmDestino('/solicitud', 'Mi solicitud', Ico.solicitudes, conteo: ref.watch(carritoProvider).length),
        if (sesion != null && !administra) TmDestino('/mis-prestamos', 'Mis préstamos', Ico.prestamos),
        if (administra) TmDestino('/prestamos-abiertos', 'Préstamos', Ico.prestamos, conteo: vencidos, urgente: vencidos > 0),
        if (administra) TmDestino('/solicitudes', 'Solicitudes', Ico.solicitudes, conteo: solicitudes),
        if (sesion == null) TmDestino('/mis-solicitudes', 'Mis solicitudes', Ico.solicitudes),
      ]),
      if (sesion != null)
        TmGrupoNav('Control', [
          TmDestino('/pendientes', 'Pendientes', Ico.pendientes, conteo: pendientes),
          TmDestino('/conteos', 'Conteos', Ico.contar),
          TmDestino('/inventarios', 'Inventarios', Ico.kits),
          TmDestino('/contenedores', 'Contenedores', Ico.contenedores),
          if (administra) TmDestino('/por-revisar', 'Por revisar', Ico.aviso, conteo: porRevisar, urgente: porRevisar > 0),
          if (administra) TmDestino('/conflictos', 'Conflictos', Ico.sinConexion),
        ]),
      if (administra)
        TmGrupoNav('Administración', [
          TmDestino('/reportes', 'Reportes', Ico.reportes),
          TmDestino('/revisiones-kit', 'Revisiones de kits', Ico.kits),
          TmDestino('/adeudos', 'Adeudos', Ico.adeudos),
          TmDestino('/etiquetas', 'Etiquetas', Ico.qr),
          TmDestino('/cuentas', 'Cuentas', Ico.cuentas),
          if (subadmin) TmDestino('/bitacora', 'Bitácora', Ico.bitacora),
          if (subadmin) TmDestino('/ajustes', 'Ajustes', Ico.ajustes),
        ]),
    ];

    final barra = <TmDestino>[
      TmDestino('/', sesion == null ? 'Catálogo' : 'Inicio', Ico.tablero),
      if (sesion != null)
        TmDestino('/inventario', 'Inventario', Ico.inventario)
      else
        TmDestino('/mis-solicitudes', 'Mis solicitudes', Ico.solicitudes),
      TmDestino('/escanear', 'Escanear', Ico.escanear),
      if (administra)
        TmDestino('/prestamos-abiertos', 'Préstamos', Ico.prestamos, conteo: vencidos, urgente: vencidos > 0)
      else if (sesion != null)
        TmDestino('/mis-prestamos', 'Préstamos', Ico.prestamos)
      else
        TmDestino('/solicitud', 'Mi solicitud', Ico.solicitudes, conteo: ref.watch(carritoProvider).length),
      const TmDestino('mas', 'Más', Ico.menu),
    ];

    void ir(String r) {
      if (r == 'mas') {
        _abrirMenu(context, ref, grupos, sesion);
        return;
      }
      if (r == ruta) return;
      r == '/' ? context.go(r) : context.push(r);
    }

    return TmShell(
      grupos: grupos,
      enBarraInferior: barra,
      rutaActual: ruta,
      onIr: ir,
      usuario: sesion?.nombre,
      rolUsuario: sesion == null ? null : '${sesion.rol.nombre} · ${sesion.nivel == NivelSesion.pin ? 'PIN' : 'Contraseña'}',
      estadoConexion: const _EstadoConexion(),
      fab: fab,
      appBar: AppBar(
        leading: conRegresar ? const _Regresar() : null,
        automaticallyImplyLeading: false,
        titleSpacing: conRegresar ? 0 : Espacio.x4,
        title: Row(children: [
          for (final (texto, r) in migas) ...[
            InkWell(
              onTap: () => context.go(r),
              child: Text(texto, style: Tipografia.chico.copyWith(color: c.textoTenue)),
            ),
            Icon(Ico.avanzar, size: 16, color: c.textoTenue),
          ],
          Flexible(child: Text(titulo, style: Tipografia.h3.copyWith(color: c.texto), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          ...acciones,
          const _BotonAvisos(),
          const BarraSesion(),
          const SizedBox(width: Espacio.x2),
        ],
      ),
      child: Column(children: [
        const _FranjaSinConexion(),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: anchoContenido), child: child),
          ),
        ),
      ]),
    );
  }

  void _abrirMenu(BuildContext context, WidgetRef ref, List<TmGrupoNav> grupos, Sesion? sesion) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: Espacio.x6), children: [
          for (final g in grupos) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.x5, Espacio.x4, Espacio.x5, Espacio.x1),
              child: Text(g.titulo.toUpperCase(), style: Tipografia.etiqueta.copyWith(color: context.tm.textoTenue)),
            ),
            for (final d in g.destinos)
              ListTile(
                leading: Icon(d.icono),
                title: Text(d.texto),
                trailing: (d.conteo ?? 0) > 0
                    ? TmInsignia('${d.conteo}', tono: d.urgente ? Tono.error : Tono.neutro)
                    : const Icon(Ico.avanzar, size: 18),
                onTap: () {
                  Navigator.pop(context);
                  d.ruta == '/' ? context.go(d.ruta) : context.push(d.ruta);
                },
              ),
          ],
          const Divider(),
          ListTile(leading: const Icon(Ico.diseno), title: const Text('Sistema de diseño'), onTap: () {
            Navigator.pop(context);
            context.push('/diseno');
          }),
          ListTile(leading: const Icon(Ico.persona), title: const Text('Mi cuenta'), onTap: () {
            Navigator.pop(context);
            context.push('/mi-cuenta');
          }),
          if (sesion == null)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Entrar'),
              onTap: () async {
                Navigator.pop(context);
                if (await pedirAcceso(context, descripcion: 'entrar al inventario')) ref.invalidate(sesionProvider);
              },
            ),
        ]),
      ),
    );
  }
}

class _Regresar extends StatelessWidget {
  const _Regresar();

  @override
  Widget build(BuildContext context) => TmBotonIcono(
        Ico.regresar,
        etiqueta: 'Regresar',
        onTap: () => context.canPop() ? context.pop() : context.go('/'),
      );
}

/// "En línea · datos de hace 2 min" o "Sin conexión · 3 por enviar", en la barra lateral.
class _EstadoConexion extends StatelessWidget {
  const _EstadoConexion();

  @override
  Widget build(BuildContext context) {
    final cola = ColaSinConexion.instancia;
    final c = context.tm;
    if (cola == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: cola,
      builder: (context, _) {
        final porEnviar = cola.porEnviar.length;
        final porResolver = cola.porResolver.length;
        final (icono, color, texto) = porResolver > 0
            ? (Ico.alerta, c.primario, '$porResolver por resolver')
            : cola.sinSenal
                ? (Ico.sinConexion, c.navTexto, porEnviar == 0 ? 'Sin conexión' : 'Sin conexión · $porEnviar por enviar')
                : porEnviar > 0
                    ? (Ico.porEnviar, c.avisoRelleno, '$porEnviar por enviar')
                    : (Ico.enLinea, c.exitoRelleno, 'En línea');
        return InkWell(
          onTap: () => context.push('/sin-conexion'),
          borderRadius: Redondeo.rSm,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Espacio.x2, vertical: Espacio.x2),
            decoration: BoxDecoration(color: c.nav2, borderRadius: Redondeo.rSm),
            child: Row(children: [
              Icon(icono, size: 16, color: color),
              const SizedBox(width: Espacio.x2),
              Expanded(child: Text(texto, style: Tipografia.chico.copyWith(fontSize: 12.5, color: c.navTexto), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        );
      },
    );
  }
}

/// Franja de "sin conexión" arriba del contenido, con la hora de los datos guardados.
class _FranjaSinConexion extends StatelessWidget {
  const _FranjaSinConexion();

  @override
  Widget build(BuildContext context) {
    final cola = ColaSinConexion.instancia;
    if (cola == null) return const SizedBox.shrink();
    final c = context.tm;
    return ListenableBuilder(
      listenable: cola,
      builder: (context, _) {
        if (!cola.sinSenal) return const SizedBox.shrink();
        return Material(
          color: c.superficieHundida,
          child: InkWell(
            onTap: () => context.push('/sin-conexion'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.x4, vertical: Espacio.x2),
              child: Row(children: [
                Icon(Ico.sinConexion, size: 18, color: c.textoSecundario),
                const SizedBox(width: Espacio.x2),
                Expanded(
                  child: Text(
                    cola.datosDe == null
                        ? 'Sin conexión. Todavía no hay datos guardados en este celular.'
                        : 'Sin conexión. Datos de ${fechaHora(cola.datosDe!)}: las cantidades pueden haber cambiado.',
                    style: Tipografia.chico.copyWith(color: c.textoSecundario),
                  ),
                ),
                if (cola.porEnviar.isNotEmpty) TmInsignia('${cola.porEnviar.length} por enviar', tono: Tono.aviso, icono: Ico.porEnviar),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _BotonAvisos extends ConsumerWidget {
  const _BotonAvisos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(avisosSinLeerProvider).value ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: Espacio.x1),
      child: IconButton(
        tooltip: '$n aviso${n == 1 ? '' : 's'} sin leer',
        onPressed: () => context.push('/avisos'),
        icon: Badge(label: Text('$n'), child: const Icon(Ico.campana)),
      ),
    );
  }
}
