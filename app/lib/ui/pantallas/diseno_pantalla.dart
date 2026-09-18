import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modelos/articulo.dart';
import '../../modelos/catalogos.dart';
import '../componentes/componentes.dart';
import '../diseno/iconos.dart';
import '../diseno/modo_tema.dart';
import '../diseno/tipografia.dart';
import '../diseno/tokens.dart';
import '../tema.dart';

/// Catálogo del sistema de diseño: aquí se revisa cada componente en claro y en oscuro
/// antes de usarlo en una pantalla (Fase 7a).
class DisenoPantalla extends ConsumerWidget {
  const DisenoPantalla({super.key});

  static Articulo _ejemplo({
    String nombre = 'Motor inteligente V5 (11 W)',
    String categoria = 'VEX',
    int existencia = 12,
    int prestado = 4,
    int fuera = 1,
    int apartado = 2,
    bool consumible = false,
    int? minimo,
    bool sinContar = false,
    bool noSePresta = false,
  }) =>
      Articulo.desdeMapa({
        'id': 'x',
        'codigo': 'A-0214',
        'ref_foto': null,
        'nombre': nombre,
        'marca_modelo': 'VEX 276-4840',
        'categoria': categoria,
        'subcategoria': 'Movimiento',
        'unidad': 'pieza',
        'cantidad_texto': null,
        'cantidad_estimada': false,
        'conteo_desconocido': sinContar,
        'estado_inventario': 'VERIFICADO',
        'estado_fisico': 'USADO',
        'estado_fisico_texto': null,
        'etiquetado': 'INDIVIDUAL',
        'ubicacion_ruta': 'Gabinete VEX › Gaveta 2',
        'contenedor_id': null,
        'contenedor_codigo': null,
        'ubicacion_texto': null,
        'num_resguardo': 'P13/0045',
        'num_serie': null,
        'observaciones': null,
        'es_consumible': consumible,
        'minimo_reposicion': minimo,
        'activo': true,
        'existencia': existencia,
        'prestado': prestado,
        'fuera_servicio': fuera,
        'apartado': apartado,
        'retenido': 0,
        'disponible': existencia - prestado - fuera - apartado,
        'prestable': !noSePresta,
        'prestado_hasta': null,
        'pendientes_abiertos': 0,
        'foto_principal_url': null,
        'baja_oficio': null,
        'baja_en_tramite': false,
        'no_se_presta': noSePresta,
        'no_se_presta_motivo': noSePresta ? 'Equipo fijo del área de fabricación' : null,
      });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tm;
    final modo = ref.watch(modoTemaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sistema de diseño'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: Espacio.x3),
          child: TmSegmento<ThemeMode>(
            valor: modo,
            opciones: const [
              (ThemeMode.light, 'Claro', null),
              (ThemeMode.dark, 'Oscuro', null),
              (ThemeMode.system, 'Auto', null),
            ],
            onCambio: (m) => ref.read(modoTemaProvider.notifier).cambiar(m),
          ),
        ),
      ]),
      body: Centrado(
        ancho: 1100,
        child: ListView(padding: const EdgeInsets.all(Espacio.x4), children: [
          Text('TALLER MAKER', style: Tipografia.display.copyWith(color: c.texto)),
          Text('Cada componente aquí es el que usan las pantallas. Si algo se ve mal en esta página, se ve mal en toda la app.',
              style: Tipografia.cuerpo.copyWith(color: c.textoSecundario)),
          const SizedBox(height: Espacio.x6),

          _Seccion('Color', [
            _fila('Marca', [
              _muestra('Primario', c.primario, c.sobrePrimario),
              _muestra('Secundario', c.secundario, c.sobreSecundario),
              _muestra('Acento', c.acento, Colors.white),
              _muestra('Navegación', c.nav, c.navTexto),
            ]),
            _fila('Estados', [
              _muestra('Éxito', c.exitoSuave, c.exito),
              _muestra('Aviso', c.avisoSuave, c.aviso),
              _muestra('Error', c.errorSuave, c.error),
              _muestra('Info', c.infoSuave, c.info),
            ]),
            _fila('Superficies', [
              _muestra('Fondo', c.fondo, c.texto),
              _muestra('Superficie', c.superficie, c.texto),
              _muestra('Hundida', c.superficieHundida, c.textoSecundario),
              _muestra('Borde', c.borde, c.texto),
            ]),
            const SizedBox(height: Espacio.x2),
            Wrap(spacing: Espacio.x3, runSpacing: Espacio.x2, children: [for (final cat in Categoria.values) TmCategoria(cat)]),
          ]),

          _Seccion('Tipografía', [
            Text('Barlow · interfaz', style: Tipografia.cuerpo.copyWith(color: c.texto)),
            Text('BARLOW CONDENSED · TÍTULOS', style: Tipografia.display.copyWith(fontSize: 26, color: c.texto)),
            Text('A-0214 · 0O 1l · 12/2026', style: Tipografia.codigoFuerte.copyWith(fontSize: 18, color: c.texto)),
            const SizedBox(height: Espacio.x2),
            Text('118', style: Tipografia.cifra.copyWith(color: c.texto)),
            Text('CIFRA DE TABLERO', style: Tipografia.etiqueta.copyWith(color: c.textoTenue)),
          ]),

          _Seccion('Botones', [
            Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
              TmBoton('Prestar', tipo: TipoBoton.primario, icono: Ico.prestar, onTap: () => mostrarAviso(context, 'Préstamo registrado: 2 piezas a Luis Canul.', accion: 'Deshacer')),
              TmBoton('Nuevo artículo', tipo: TipoBoton.secundario, icono: Ico.nuevo, onTap: () {}),
              TmBoton('Recibir devolución', icono: Ico.devolver, onTap: () {}),
              TmBoton('Cancelar', tipo: TipoBoton.fantasma, onTap: () {}),
              TmBoton('Dar de baja…', tipo: TipoBoton.peligro, icono: Ico.baja, onTap: () async {
                final si = await confirmar(context,
                    titulo: '¿Dar de baja 2 Baterías V5?',
                    consecuencia: 'Dejarán de contar en el inventario y quedará en la bitácora. No se puede deshacer.',
                    botonSi: 'Dar de baja 2 piezas');
                if (si && context.mounted) mostrarAviso(context, 'Se dieron de baja 2 Baterías V5.');
              }),
              const TmBoton('Prestar', tipo: TipoBoton.primario, icono: Ico.prestar),
              TmBotonIcono(Ico.escanear, etiqueta: 'Escanear etiqueta', onTap: () {}),
            ]),
            const SizedBox(height: Espacio.x3),
            Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
              TmBoton('Chico', tamano: TamanoBoton.chico, onTap: () {}),
              TmBoton('Normal', onTap: () {}),
              TmBoton('Grande', tamano: TamanoBoton.grande, onTap: () {}),
              TmBoton('Guardando…', tipo: TipoBoton.primario, cargando: true, onTap: () {}),
            ]),
          ]),

          _Seccion('Campos', [
            const TmCampo(etiqueta: 'Nombre', obligatorio: true, pista: 'Ejemplo: Motor HD Hex REV', ayuda: 'Qué es, no dónde está.'),
            const SizedBox(height: Espacio.x4),
            const TmCampo(etiqueta: 'Número de resguardo', mono: true, error: 'Usa el formato P13/0045 (cuatro dígitos).'),
            const SizedBox(height: Espacio.x4),
            const TmCampo(etiqueta: 'Mínimo para reponer', habilitado: false, pista: 'Solo consumibles'),
            const SizedBox(height: Espacio.x4),
            TmBuscador(controlador: TextEditingController()),
          ]),

          _Seccion('Insignias y chips', [
            Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
              const TmInsignia('Verificado', tono: Tono.ok, icono: Ico.verificado),
              const TmInsignia('Por verificar', tono: Tono.info, icono: Ico.porVerificar),
              const TmInsignia('Por contar', tono: Tono.aviso, icono: Ico.contar),
              const TmInsignia('Vencido hace 2 días', tono: Tono.error, icono: Ico.alerta),
              const TmInsignia('No se presta', tono: Tono.contorno, icono: Ico.noSePresta),
              TmAvatar('Mariana Pech Chan'),
            ]),
            const SizedBox(height: Espacio.x3),
            Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: [
              TmChip('Todas', seleccionado: true, conteo: 156, onTap: () {}),
              TmChip('VEX', color: c.deCategoria(Categoria.vex), conteo: 27, onTap: () {}),
              TmChip('En su mínimo', icono: Ico.aviso, conteo: 3, onTap: () {}),
            ]),
          ]),

          _Seccion('Existencias', [
            Wrap(spacing: Espacio.x8, runSpacing: Espacio.x4, children: [
              TmExistencias(_ejemplo()),
              TmExistencias(_ejemplo(nombre: 'Cerebro V5', existencia: 3, prestado: 3, fuera: 0, apartado: 0)),
              TmExistencias(_ejemplo(nombre: 'Filamento PLA', categoria: 'CONSUMIBLES', existencia: 2, prestado: 0, fuera: 0, apartado: 0, consumible: true, minimo: 3)),
              TmExistencias(_ejemplo(nombre: 'Soldadura', categoria: 'CONSUMIBLES', existencia: 0, prestado: 0, fuera: 0, apartado: 0, consumible: true, minimo: 1)),
              TmExistencias(_ejemplo(nombre: 'Caja sin rótulo', categoria: 'SIN_CLASIFICAR', existencia: 0, prestado: 0, fuera: 0, apartado: 0, sinContar: true)),
            ]),
            const SizedBox(height: Espacio.x4),
            const TmLeyendaExistencias(),
          ]),

          _Seccion('Tarjetas y cifras', [
            Row(children: [
              Expanded(child: TmKpi(etiqueta: 'Artículos', valor: '156', pie: 'renglones en 7 categorías', icono: Ico.inventario, onTap: () {})),
              const SizedBox(width: Espacio.x3),
              Expanded(child: TmKpi(etiqueta: 'En su mínimo', valor: '3', pie: 'consumibles por reponer', iconoPie: Ico.aviso, tono: TonoKpi.atencion, onTap: () {})),
              const SizedBox(width: Espacio.x3),
              Expanded(child: TmKpi(etiqueta: 'Vencidos', valor: '2', pie: 'préstamos', iconoPie: Ico.reloj, tono: TonoKpi.critico, onTap: () {})),
            ]),
            const SizedBox(height: Espacio.x3),
            TmTarjeta(
              titulo: 'Actividad reciente',
              icono: Ico.bitacora,
              acciones: [TmBoton('Bitácora', tipo: TipoBoton.fantasma, tamano: TamanoBoton.chico, onTap: () {})],
              sinPadding: true,
              child: Column(children: [
                for (final (ico, titulo, detalle) in [
                  (Ico.prestar, 'Préstamo', 'Cable de motor V5 ×2 · Ruth Canché'),
                  (Ico.devolver, 'Devolución', 'Motor HD Hex REV ×2 · Luis Canul'),
                ])
                  ListTile(
                    leading: TmMiniatura(icono: ico, color: c.deCategoria(Categoria.vex)),
                    title: Text(titulo),
                    subtitle: Text(detalle),
                  ),
              ]),
            ),
          ]),

          _Seccion('Alertas y avisos', [
            const TmAlerta(titulo: '2 préstamos vencidos', texto: 'Mariana Pech (5°B) tiene 2 Cerebros V5 desde el 15 sep.', tono: Tono.error),
            const SizedBox(height: Espacio.x2),
            const TmAlerta(
              titulo: 'Conflicto de existencia: Batería V5',
              texto: 'Se prestó sin conexión cuando no había disponibles. Hay que contarla.',
              tono: Tono.aviso,
              cinta: true,
            ),
            const SizedBox(height: Espacio.x2),
            const TmAlerta(titulo: 'Se aplicaron 12 conteos', tono: Tono.ok),
            const SizedBox(height: Espacio.x2),
            TmAlerta(
              titulo: 'Sin conexión',
              texto: 'Lo que registres se guarda y se envía solo al volver la señal.',
              tono: Tono.info,
              icono: Ico.sinSenal,
              accion: TmBoton('Ver', tamano: TamanoBoton.chico, onTap: () {}),
            ),
          ]),

          _Seccion('Estados', [
            TmVacio(
              titulo: 'Sin resultados para “servo 393”',
              texto: 'Revisa cómo se escribe, busca por código o quita el filtro de categoría.',
              icono: Ico.sinResultados,
              acciones: [TmBoton('Quitar filtros', icono: Ico.cerrar, onTap: () {})],
            ),
            const Divider(),
            const TmCargandoLista(renglones: 3),
            const Divider(),
            TmErrorCarga(mensaje: 'El servidor no respondió. No se perdió nada de lo que capturaste.', onReintentar: () {}),
          ]),

          const SizedBox(height: Espacio.x8),
        ]),
      ),
    );
  }

  Widget _fila(String titulo, List<Widget> muestras) => Padding(
        padding: const EdgeInsets.only(bottom: Espacio.x3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo.toUpperCase(), style: Tipografia.etiqueta),
          const SizedBox(height: Espacio.x2),
          Wrap(spacing: Espacio.x2, runSpacing: Espacio.x2, children: muestras),
        ]),
      );

  Widget _muestra(String nombre, Color fondo, Color texto) => Container(
        width: 150,
        height: 56,
        padding: const EdgeInsets.all(Espacio.x2),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(color: fondo, borderRadius: Redondeo.rSm, border: Border.all(color: const Color(0x33808080))),
        child: Text(nombre, style: Tipografia.chicoFuerte.copyWith(color: texto)),
      );
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.hijos);

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Espacio.x8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo.toUpperCase(), style: Tipografia.display.copyWith(fontSize: 22, color: context.tm.texto)),
          const SizedBox(height: Espacio.x3),
          ...hijos,
        ]),
      );
}
