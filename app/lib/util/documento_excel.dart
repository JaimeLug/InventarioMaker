import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'documento.dart';
import 'texto.dart';

/// Mismo acomodo que el Excel que se entregaba a Contraloría: título, subtítulo, una línea libre
/// y el encabezado azul en el renglón 4.
Uint8List documentoAExcel(Documento d) {
  final libro = Excel.createExcel();
  final original = libro.getDefaultSheet()!;
  final e = d.encabezado;
  final lineaEscuela = [e.escuela, e.programa, e.laboratorio, if (e.responsable != null) 'Responsable: ${e.responsable}'].join(' · ');
  final lineaCorte = [
    'Corte: ${fechaHora(e.fechaCorte)}',
    if (d.periodo != null) 'Periodo: ${d.periodo}',
    if (d.folio != null) 'Folio: ${d.folio}',
    'Generado por ${e.generadoPor}',
  ].join(' · ');

  final titulo = CellStyle(bold: true, fontSize: 14);
  final chico = CellStyle(fontSize: 10);
  final gris = CellStyle(fontSize: 10, italic: true, fontColorHex: ExcelColor.fromHexString('#595959'));
  final borde = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#BFBFBF'));
  final cabeza = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#1F4E79'),
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Center,
    leftBorder: borde,
    rightBorder: borde,
    topBorder: borde,
    bottomBorder: borde,
  );
  final celda = CellStyle(textWrapping: TextWrapping.WrapText, verticalAlign: VerticalAlign.Top,
      leftBorder: borde, rightBorder: borde, topBorder: borde, bottomBorder: borde);
  final celdaTotal = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#DDEBF7'),
      leftBorder: borde, rightBorder: borde, topBorder: borde, bottomBorder: borde);

  CellValue? valor(Object? v) => switch (v) {
        null => null,
        int n => IntCellValue(n),
        double n => DoubleCellValue(n),
        bool b => TextCellValue(b ? 'Sí' : 'No'),
        DateTime f => TextCellValue(fechaHora(f)),
        _ => TextCellValue('$v'),
      };

  void poner(Sheet hoja, int col, int renglon, Object? v, CellStyle estilo) {
    final c = hoja.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: renglon));
    c.value = valor(v);
    c.cellStyle = estilo;
  }

  final usadas = <String>{};
  String nombreHoja(String n) {
    var base = n.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
    if (base.length > 31) base = base.substring(0, 31);
    var nombre = base;
    for (var i = 2; usadas.contains(nombre.toLowerCase()); i++) {
      nombre = '${base.substring(0, base.length.clamp(0, 28))} $i';
    }
    usadas.add(nombre.toLowerCase());
    return nombre;
  }

  // Actas: la primera pestaña lleva el texto y las firmas.
  if (d.parrafos.isNotEmpty || d.firmantes.isNotEmpty) {
    final hoja = libro[nombreHoja('Acta')];
    hoja.setColumnWidth(0, 28);
    hoja.setColumnWidth(1, 40);
    hoja.setColumnWidth(2, 40);
    var r = 0;
    poner(hoja, 0, r++, d.titulo.toUpperCase(), titulo);
    poner(hoja, 0, r++, lineaEscuela, chico);
    poner(hoja, 0, r++, lineaCorte, gris);
    r++;
    for (final p in d.parrafos) {
      poner(hoja, 0, r, p, CellStyle(textWrapping: TextWrapping.WrapText, verticalAlign: VerticalAlign.Top));
      hoja.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r));
      hoja.setRowHeight(r, 15.0 * (1 + p.length ~/ 110));
      r++;
    }
    if (d.firmantes.isNotEmpty) {
      r++;
      for (final (i, t) in ['Firma como', 'Nombre', 'Cargo'].indexed) {
        poner(hoja, i, r, t, cabeza);
      }
      r++;
      for (final f in d.firmantes) {
        poner(hoja, 0, r, f.papel, celda);
        poner(hoja, 1, r, f.nombre, celda);
        poner(hoja, 2, r, f.cargo, celda);
        r++;
      }
    }
  }

  for (final t in d.tablas) {
    final hoja = libro[nombreHoja(t.hoja)];
    final ultima = t.columnas.length - 1;
    for (final (i, c) in t.columnas.indexed) {
      hoja.setColumnWidth(i, c.ancho);
    }
    poner(hoja, 0, 0, t.titulo.toUpperCase(), titulo);
    poner(hoja, 0, 1, lineaEscuela, chico);
    poner(hoja, 0, 2, [lineaCorte, if (t.nota != null) t.nota].join('   |   '), gris);
    if (ultima > 0) {
      for (final r in [0, 1, 2]) {
        hoja.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), CellIndex.indexByColumnRow(columnIndex: ultima, rowIndex: r));
      }
    }
    for (final (i, c) in t.columnas.indexed) {
      poner(hoja, i, 3, c.titulo, cabeza);
    }
    var r = 4;
    for (final fila in t.filas) {
      for (var i = 0; i <= ultima; i++) {
        poner(hoja, i, r, i < fila.length ? fila[i] : null, celda);
      }
      r++;
    }
    if (t.filas.isEmpty) {
      poner(hoja, 0, r++, 'Sin renglones.', gris);
    }
    if (t.total != null) {
      for (var i = 0; i <= ultima; i++) {
        poner(hoja, i, r, i < t.total!.length ? t.total![i] : null, celdaTotal);
      }
    }
  }

  libro.delete(original);
  libro.setDefaultSheet(libro.tables.keys.first);
  return Uint8List.fromList(libro.encode()!);
}
