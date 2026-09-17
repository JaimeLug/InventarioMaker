import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'documento.dart';
import 'texto.dart';

const _azul = PdfColor.fromInt(0xFF1F4E79);

/// Baja una foto y la reduce a miniatura para que el PDF no pese de más. Si falla, va sin foto.
Future<pw.MemoryImage?> _miniatura(String url, {int ancho = 160}) async {
  try {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    final codec = await ui.instantiateImageCodec(r.bodyBytes, targetWidth: ancho);
    final cuadro = await codec.getNextFrame();
    final png = await cuadro.image.toByteData(format: ui.ImageByteFormat.png);
    cuadro.image.dispose();
    return png == null ? null : pw.MemoryImage(png.buffer.asUint8List());
  } on Object {
    return null;
  }
}

/// [urlFoto] convierte la ruta guardada en dirección pública; solo se usa si [conFotos].
Future<Uint8List> documentoAPdf(Documento d,
    {bool conFotos = false, String Function(String ruta)? urlFoto, void Function(int hechas, int total)? progreso}) async {
  final e = d.encabezado;
  final formato = d.horizontal ? PdfPageFormat.letter.landscape : PdfPageFormat.letter;

  pw.MemoryImage? logo;
  if (e.logoUrl != null) logo = await _miniatura(e.logoUrl!, ancho: 240);

  // Miniaturas: de cinco en cinco para no saturar la red.
  final fotos = <String, pw.MemoryImage?>{};
  if (conFotos && urlFoto != null) {
    final rutas = {for (final t in d.tablas) ...?t.fotos?.whereType<String>()}.toList();
    for (var i = 0; i < rutas.length; i += 5) {
      final grupo = rutas.skip(i).take(5).toList();
      final imagenes = await Future.wait(grupo.map((r) => _miniatura(urlFoto(r))));
      for (final (j, r) in grupo.indexed) {
        fotos[r] = imagenes[j];
      }
      progreso?.call((i + grupo.length).clamp(0, rutas.length), rutas.length);
    }
  }

  final doc = pw.Document(title: latino(d.titulo), author: latino(e.generadoPor), creator: 'Inventario Maker');
  final txt = pw.TextStyle(fontSize: 8);
  final negrita = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

  pw.Widget encabezado(pw.Context c) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _azul, width: 1.2))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          // Lugar del logo oficial.
          pw.Container(
            width: 44,
            height: 44,
            alignment: pw.Alignment.center,
            decoration: logo == null ? pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)) : null,
            child: logo == null ? pw.Text('LOGO', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey500)) : pw.Image(logo),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(latino(e.escuela), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(latino('${e.programa} · ${e.laboratorio}'), style: const pw.TextStyle(fontSize: 9)),
              if (e.responsable != null) pw.Text(latino('Responsable: ${e.responsable}'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(latino(d.titulo), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _azul)),
            if (d.folio != null) pw.Text('Folio ${d.folio}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text(latino('Corte: ${fechaHora(e.fechaCorte)}'), style: const pw.TextStyle(fontSize: 8)),
          ]),
        ]),
      );

  pw.Widget pie(pw.Context c) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(latino('Generado por ${e.generadoPor} con Inventario Maker'), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ]),
      );

  String celda(Object? v) => switch (v) {
        null => '',
        bool b => b ? 'Sí' : 'No',
        DateTime f => fechaHora(f),
        _ => latino('$v'),
      };

  pw.Widget tabla(Tabla t) {
    final miniaturas = conFotos && t.fotos != null;
    final anchos = <int, pw.TableColumnWidth>{
      if (miniaturas) 0: const pw.FixedColumnWidth(40),
      // Que el título no se parta a media palabra en las columnas angostas.
      for (final (i, c) in t.columnas.indexed)
        i + (miniaturas ? 1 : 0): pw.FlexColumnWidth(math.max(c.ancho, c.titulo.split(' ').map((p) => p.length).reduce(math.max) * 1.6 + 2)),
    };
    pw.Widget texto(String s, pw.TextStyle estilo, {bool numero = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: pw.Text(s, style: estilo, textAlign: numero ? pw.TextAlign.right : pw.TextAlign.left),
        );
    return pw.Table(
      columnWidths: anchos,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _azul),
          children: [
            if (miniaturas) texto('Foto', negrita.copyWith(color: PdfColors.white)),
            for (final c in t.columnas) texto(latino(c.titulo), negrita.copyWith(color: PdfColors.white)),
          ],
        ),
        for (final (n, fila) in t.filas.indexed)
          pw.TableRow(
            decoration: n.isOdd ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F6FA)) : null,
            children: [
              if (miniaturas)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(2),
                  child: fotos[t.fotos![n]] == null ? pw.SizedBox(width: 36, height: 36) : pw.Image(fotos[t.fotos![n]]!, width: 36, height: 36, fit: pw.BoxFit.cover),
                ),
              for (final (i, c) in t.columnas.indexed) texto(celda(i < fila.length ? fila[i] : null), txt, numero: c.numero),
            ],
          ),
        if (t.total != null)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFDDEBF7)),
            children: [
              if (miniaturas) pw.SizedBox(),
              for (final (i, c) in t.columnas.indexed) texto(celda(i < t.total!.length ? t.total![i] : null), negrita, numero: c.numero),
            ],
          ),
      ],
    );
  }

  pw.Widget firmas() => pw.Wrap(
        spacing: 24,
        runSpacing: 28,
        children: [
          for (final f in d.firmantes)
            pw.SizedBox(
              width: 200,
              child: pw.Column(children: [
                pw.Text(latino(f.papel.toUpperCase()), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 40),
                pw.Container(height: 0.6, color: PdfColors.black),
                pw.SizedBox(height: 3),
                pw.Text(latino(f.nombre.isEmpty ? ' ' : f.nombre), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
                if (f.cargo.isNotEmpty) pw.Text(latino(f.cargo), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
              ]),
            ),
        ],
      );

  doc.addPage(pw.MultiPage(
    pageFormat: formato,
    margin: const pw.EdgeInsets.all(0.5 * PdfPageFormat.inch),
    header: encabezado,
    footer: pie,
    build: (c) => [
      pw.Text(latino(d.titulo.toUpperCase()), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      if (d.periodo != null) pw.Text(latino('Periodo: ${d.periodo}'), style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 6),
      for (final p in d.parrafos)
        pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Text(latino(p), style: const pw.TextStyle(fontSize: 9.5), textAlign: pw.TextAlign.justify)),
      for (final t in d.tablas) ...[
        pw.SizedBox(height: 8),
        pw.Text(latino(t.titulo), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _azul)),
        if (t.nota != null) pw.Text(latino(t.nota!), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 3),
        if (t.filas.isEmpty && t.total == null) pw.Text('Sin renglones.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)) else tabla(t),
      ],
      if (d.firmantes.isNotEmpty) ...[pw.SizedBox(height: 28), firmas()],
    ],
  ));
  return doc.save();
}
