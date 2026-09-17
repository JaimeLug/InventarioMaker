import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventario_maker/datos/reportes.dart';
import 'package:inventario_maker/modelos/articulo.dart';
import 'package:inventario_maker/modelos/pendientes.dart';
import 'package:inventario_maker/util/documento.dart';
import 'package:inventario_maker/util/documento_excel.dart';
import 'package:inventario_maker/util/documento_pdf.dart';

import 'logica_test.dart' show renglon;

Encabezado encabezado() => Encabezado.desdeMapa({
      'escuela': 'Escuela Preparatoria Número 13',
      'programa': 'Programa Renacimiento Maya',
      'laboratorio': 'Laboratorio Maker',
      'responsable': 'Jaime Lugo',
      'subadministracion': 'Sub Administradora',
      'generado_por': 'Jaime Lugo',
      'fecha_corte': '2026-09-17T16:00:00+00:00',
      'logo_url': null,
    });

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  test('ciclo escolar de agosto a julio', () {
    expect(cicloEscolar(DateTime(2026, 9, 17)), (desde: DateTime(2026, 8, 1), hasta: DateTime(2027, 7, 31)));
    expect(cicloEscolar(DateTime(2027, 7, 31)), (desde: DateTime(2026, 8, 1), hasta: DateTime(2027, 7, 31)));
    expect(cicloEscolar(DateTime(2027, 8, 1)).desde, DateTime(2027, 8, 1));
  });

  test('textos para PDF y nombres de archivo', () {
    expect(latino('Caja › Gaveta 2 — “VEX”'), 'Caja > Gaveta 2 - "VEX"');
    expect(latino('Daño en cautín ñ'), 'Daño en cautín ñ');
    expect(nombreArchivo('Acta entrega-recepción AER-2026-001'), 'Acta entrega-recepcion AER-2026-001');
  });

  test('inventario con las columnas de Contraloría: Código primero y la ruta como ubicación', () {
    final articulos = [
      Articulo.desdeMapa(renglon()),
      Articulo.desdeMapa(renglon({
        'id': 'a2', 'codigo': 'A-0028', 'nombre': 'Caja Driver Hub', 'categoria': 'FTC', 'ubicacion_ruta': 'Gabinete 1 › Gaveta 2',
        'estado_inventario': 'VERIFICADO', 'cantidad_estimada': false, 'prestado': 0, 'existencia': 3, 'unidad': 'caja',
        'no_se_presta': true, 'no_se_presta_motivo': 'Solo las cajas', 'num_resguardo': 'P13/0045',
      })),
    ];
    final tablas = tablasInventario(articulos, {'a1': ['Contar físicamente', 'Contar físicamente']});
    expect(tablas.map((t) => t.hoja), ['Resumen', 'VEX', 'FTC', 'Herramientas', 'Herramientas eléctricas', 'Consumibles', 'Común', 'Sin clasificar']);
    expect(tablas.first.total, [null, 'TOTAL', 2, 1]);

    final herramientas = tablas.firstWhere((t) => t.hoja == 'Herramientas');
    expect(herramientas.columnas.first.titulo, 'Código');
    expect(herramientas.filas.single.sublist(0, 5), ['A-0012', 1, 'Destornilladores surtidos', null, '~17 piezas (2 prestados)']);
    expect(herramientas.filas.single[7], 'Cajón azul');
    expect(herramientas.filas.single[9], 'Contar físicamente');

    final ftc = tablas.firstWhere((t) => t.hoja == 'FTC').filas.single;
    expect(ftc[4], '3 cajas');
    expect(ftc[7], 'Gabinete 1 › Gaveta 2');
    expect(ftc[8], 'Surtidos, mango rojo. Resguardo P13/0045. No se presta: Solo las cajas');
    expect(ftc[10], 'Sí');
  });

  test('faltantes de kits suma lo que falta', () {
    final filas = [
      {'kit': 'REV Control & Power Bundle', 'descripcion': 'Driver Hub', 'esperada': 3, 'encontrada': 0, 'faltante': 3, 'estado': 'Faltante total'},
      {'kit': 'REV Control & Power Bundle', 'descripcion': 'Control Hub', 'esperada': 3, 'encontrada': 1, 'faltante': 2, 'estado': 'Faltante parcial'},
      {'kit': 'REV Control & Power Bundle', 'descripcion': 'Gamepad', 'esperada': 3, 'encontrada': null, 'faltante': null, 'estado': 'No aplica'},
    ];
    expect(tablaFaltantes(filas).total![8], 5);
    expect(tablaFaltantes(filas, soloFaltantes: true).filas, hasLength(2));
  });

  test('consulta rápida: consumibles en su mínimo y sin verificar por categoría', () {
    final articulos = [
      Articulo.desdeMapa(renglon({'es_consumible': true, 'minimo_reposicion': 15})),
      Articulo.desdeMapa(renglon({'id': 'a2', 'categoria': 'VEX', 'estado_inventario': 'VERIFICADO'})),
    ];
    final c = ConsultaRapida.armar(articulos, [{'vencido': true}, {'vencido': false}], [
      PendienteAbierto.desdeMapa({'id': 't', 'articulo_id': 'a1', 'tipo': 'CONTAR', 'descripcion': 'x', 'prioridad': 1, 'creada_en': '2026-09-01T00:00:00Z'}),
    ]);
    expect(c.vencidos, hasLength(1));
    expect(c.bajoMinimo.map((a) => a.id), ['a1']);
    expect(c.totales.values.reduce((a, b) => a + b), 2);
    expect(c.sinVerificar.values.expand((l) => l).map((a) => a.id), ['a1']);
  });

  test('el Excel se puede abrir y trae las pestañas con el encabezado en el renglón 4', () {
    final doc = Documento(
      titulo: 'Inventario físico',
      archivo: 'Inventario',
      encabezado: encabezado(),
      tablas: tablasInventario([Articulo.desdeMapa(renglon())], const {}),
      parrafos: const ['Texto del acta'],
      firmantes: [Firmante(papel: 'Entrega', nombre: 'Jaime Lugo')],
    );
    final libro = Excel.decodeBytes(documentoAExcel(doc));
    expect(libro.tables.keys, ['Acta', 'Resumen', 'VEX', 'FTC', 'Herramientas', 'Herramientas eléctricas', 'Consumibles', 'Común', 'Sin clasificar']);
    final hoja = libro.tables['Herramientas']!;
    expect(hoja.rows[3].first?.value.toString(), 'Código');
    expect(hoja.rows[4].first?.value.toString(), 'A-0012');
    expect(hoja.rows[1].first?.value.toString(), contains('Escuela Preparatoria Número 13'));
  });

  test('el PDF se genera con encabezado, tablas y firmas', () async {
    final doc = Documento(
      titulo: 'Acta de entrega-recepción',
      archivo: 'Acta',
      encabezado: encabezado(),
      folio: 'AER-2026-001',
      parrafos: const ['En Mérida, Yucatán…'],
      tablas: tablasInventario([Articulo.desdeMapa(renglon())], const {}),
      firmantes: [Firmante(papel: 'Entrega', nombre: 'Jaime Lugo'), Firmante(papel: 'Recibe')],
    );
    final bytes = await documentoAPdf(doc);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
