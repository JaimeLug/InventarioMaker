import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_maker/modelos/articulo.dart';
import 'package:inventario_maker/modelos/catalogos.dart';
import 'package:inventario_maker/ui/componentes/componentes.dart';
import 'package:inventario_maker/ui/diseno/tokens.dart';
import 'package:inventario_maker/ui/tema.dart';

import 'logica_test.dart' show renglon;

/// Contraste según WCAG 2.1: el mismo cálculo que promete el sistema de diseño.
double contraste(Color a, Color b) {
  double luz(Color c) {
    double canal(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
    return .2126 * canal(c.r) + .7152 * canal(c.g) + .0722 * canal(c.b);
  }

  final x = luz(a), y = luz(b);
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

Widget conTema(Widget hijo, {Brightness brillo = Brightness.light}) => MaterialApp(
      theme: brillo == Brightness.dark ? temaOscuro() : temaClaro(),
      home: Scaffold(body: SingleChildScrollView(child: hijo)),
    );

void main() {
  group('Tokens', () {
    test('cada categoría tiene color en los dos temas', () {
      for (final c in Categoria.values) {
        expect(TmColores.claro.categorias[c], isNotNull, reason: '$c en claro');
        expect(TmColores.oscuro.categorias[c], isNotNull, reason: '$c en oscuro');
      }
    });

    test('el texto cumple el contraste mínimo AA en claro y en oscuro', () {
      for (final (nombre, t) in [('claro', TmColores.claro), ('oscuro', TmColores.oscuro)]) {
        expect(contraste(t.texto, t.superficie), greaterThanOrEqualTo(4.5), reason: 'texto en $nombre');
        expect(contraste(t.textoSecundario, t.superficie), greaterThanOrEqualTo(4.5), reason: 'texto secundario en $nombre');
        expect(contraste(t.textoTenue, t.superficie), greaterThanOrEqualTo(4.5), reason: 'texto tenue en $nombre');
        expect(contraste(t.sobrePrimario, t.primario), greaterThanOrEqualTo(4.5), reason: 'botón primario en $nombre');
        expect(contraste(t.sobreSecundario, t.secundario), greaterThanOrEqualTo(4.5), reason: 'botón secundario en $nombre');
        expect(contraste(t.navTexto, t.nav), greaterThanOrEqualTo(4.5), reason: 'navegación en $nombre');
        expect(contraste(t.error, t.errorSuave), greaterThanOrEqualTo(4.5), reason: 'error en $nombre');
        expect(contraste(t.aviso, t.avisoSuave), greaterThanOrEqualTo(4.5), reason: 'aviso en $nombre');
        expect(contraste(t.exito, t.exitoSuave), greaterThanOrEqualTo(4.5), reason: 'éxito en $nombre');
        expect(contraste(t.info, t.infoSuave), greaterThanOrEqualTo(4.5), reason: 'info en $nombre');
      }
    });

    test('los bordes, el foco y las franjas de categoría se distinguen del fondo', () {
      for (final (nombre, t) in [('claro', TmColores.claro), ('oscuro', TmColores.oscuro)]) {
        // Los bordes son decorativos (ningún estado depende de ellos), pero deben verse.
        expect(contraste(t.bordeFuerte, t.superficie), greaterThanOrEqualTo(2), reason: 'borde en $nombre');
        expect(contraste(t.foco, t.superficie), greaterThanOrEqualTo(3), reason: 'foco en $nombre');
        for (final c in Categoria.values) {
          expect(contraste(t.deCategoria(c), t.superficie), greaterThanOrEqualTo(2.4), reason: '$c en $nombre');
        }
      }
    });
  });

  group('Componentes', () {
    testWidgets('el indicador de existencias dice la cifra y la situación', (tester) async {
      await tester.pumpWidget(conTema(TmExistencias(Articulo.desdeMapa(renglon()))));
      expect(find.text('~15'), findsOneWidget);   // la cantidad es estimada
      expect(find.textContaining('de 17 piezas'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
    });

    testWidgets('un consumible en su mínimo se marca con texto, no solo con color', (tester) async {
      final a = Articulo.desdeMapa(renglon({'es_consumible': true, 'minimo_reposicion': 15}));
      await tester.pumpWidget(conTema(TmExistencias(a)));
      expect(find.text('En su mínimo'), findsOneWidget);
      expect(SituacionStock.de(a), SituacionStock.enMinimo);
    });

    test('la situación de existencias se calcula igual que en el servidor', () {
      expect(SituacionStock.de(Articulo.desdeMapa(renglon({'existencia': 2, 'prestado': 2, 'disponible': 0}))), SituacionStock.ningunoDisponible);
      expect(SituacionStock.de(Articulo.desdeMapa(renglon({'existencia': 0, 'prestado': 0, 'disponible': 0}))), SituacionStock.agotado);
      expect(SituacionStock.de(Articulo.desdeMapa(renglon({'conteo_desconocido': true}))), SituacionStock.sinContar);
      expect(SituacionStock.de(Articulo.desdeMapa(renglon({'no_se_presta': true, 'no_se_presta_motivo': 'Empaque vacío'}))), SituacionStock.noSePresta);
    });

    testWidgets('los botones tienen el alto cómodo para tocar con guantes', (tester) async {
      await tester.pumpWidget(conTema(const Row(children: [TmBoton('Prestar', tipo: TipoBoton.primario)])));
      expect(tester.getSize(find.byType(TmBoton)).height, greaterThanOrEqualTo(Quiebre.toque));
    });

    testWidgets('la categoría siempre lleva su nombre escrito, no solo color', (tester) async {
      await tester.pumpWidget(conTema(const TmCategoria(Categoria.herramientasElectricas)));
      expect(find.text('Herramientas eléctricas'), findsOneWidget);
      await tester.pumpWidget(conTema(const TmCategoria(Categoria.herramientasElectricas, corto: true)));
      expect(find.text('H. eléctricas'), findsOneWidget);
    });

    testWidgets('el estado vacío explica qué hacer', (tester) async {
      await tester.pumpWidget(conTema(TmVacio(
        titulo: 'Sin resultados',
        texto: 'Revisa cómo se escribe o quita el filtro.',
        acciones: [TmBoton('Quitar filtros', onTap: () {})],
      )));
      expect(find.text('Sin resultados'), findsOneWidget);
      expect(find.text('Quitar filtros'), findsOneWidget);
    });

    testWidgets('en pantalla angosta la navegación va abajo y en ancha a un lado', (tester) async {
      const grupos = [
        TmGrupoNav('Operación', [TmDestino('/', 'Tablero', Icons.dashboard), TmDestino('/inventario', 'Inventario', Icons.inventory)]),
      ];
      const barra = [
        TmDestino('/', 'Inicio', Icons.home),
        TmDestino('/escanear', 'Escanear', Icons.qr_code),
        TmDestino('/mas', 'Más', Icons.menu),
      ];
      Widget shell(Size tamano) => MaterialApp(
            theme: temaClaro(),
            home: MediaQuery(
              data: MediaQueryData(size: tamano),
              child: TmShell(
                grupos: grupos,
                enBarraInferior: barra,
                rutaActual: '/',
                onIr: (_) {},
                usuario: 'Jaime Lugo',
                child: const Text('contenido'),
              ),
            ),
          );

      await tester.pumpWidget(shell(const Size(390, 800)));
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('OPERACIÓN'), findsNothing);

      await tester.pumpWidget(shell(const Size(1400, 900)));
      await tester.pumpAndSettle();
      expect(find.text('OPERACIÓN'), findsOneWidget);
      expect(find.text('Inventario'), findsOneWidget);
    });
  });
}
