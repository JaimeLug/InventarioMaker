import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'etiquetas.dart';

export 'etiquetas.dart';

/// La letra estándar de PDF no trae todos los símbolos: se cambian los que no tiene.
String _latino(String t) => t
    .replaceAll('›', '>')
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

/// [empezarEn] (1 = primera etiqueta) permite reutilizar una hoja a la que ya se le usaron algunas.
Future<Uint8List> generarEtiquetas(List<EtiquetaDatos> etiquetas, FormatoEtiqueta f, String urlApp, {int empezarEn = 1}) async {
  const pulgada = PdfPageFormat.inch;
  final doc = pw.Document(title: 'Etiquetas Laboratorio Maker', creator: 'Inventario Maker');
  final lugares = [...List<EtiquetaDatos?>.filled((empezarEn - 1).clamp(0, f.porHoja - 1), null), ...etiquetas];
  final grande = f == FormatoEtiqueta.grande;
  final lado = (f.alto - (grande ? 0.3 : 0.14)) * pulgada;

  for (var inicio = 0; inicio < lugares.length; inicio += f.porHoja) {
    final hoja = lugares.skip(inicio).take(f.porHoja).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(children: [
        for (var i = 0; i < hoja.length; i++)
          if (hoja[i] != null)
            pw.Positioned(
              left: (f.margenIzquierdo + (i % f.columnas) * f.pasoHorizontal) * pulgada,
              top: (f.margenSuperior + (i ~/ f.columnas) * f.pasoVertical) * pulgada,
              child: pw.SizedBox(
                width: f.ancho * pulgada,
                height: f.alto * pulgada,
                child: pw.Padding(
                  padding: pw.EdgeInsets.all((grande ? 0.15 : 0.07) * pulgada),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high),
                      data: direccionDeCodigo(urlApp, hoja[i]!.codigo),
                      width: lado,
                      height: lado,
                    ),
                    pw.SizedBox(width: (grande ? 0.15 : 0.08) * pulgada),
                    pw.Expanded(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(hoja[i]!.codigo, style: pw.TextStyle(fontSize: grande ? 22 : 11, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 2),
                          pw.Text(_latino(hoja[i]!.titulo), maxLines: grande ? 3 : 2, style: pw.TextStyle(fontSize: grande ? 14 : 7.5)),
                          if (hoja[i]!.detalle != null && hoja[i]!.detalle!.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(_latino(hoja[i]!.detalle!), maxLines: grande ? 2 : 1, style: pw.TextStyle(fontSize: grande ? 10 : 6, color: PdfColors.grey700)),
                          ],
                          if (grande) ...[
                            pw.SizedBox(height: 4),
                            pw.Text('Laboratorio Maker', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
      ]),
    ));
  }
  return doc.save();
}

/// Arma la hoja y abre el diálogo de impresión. La web baja este archivo (y el paquete de PDF)
/// solo cuando alguien imprime.
Future<void> imprimirEtiquetas(List<EtiquetaDatos> etiquetas, FormatoEtiqueta f, String urlApp, {int empezarEn = 1}) async {
  final bytes = await generarEtiquetas(etiquetas, f, urlApp, empezarEn: empezarEn);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Etiquetas Laboratorio Maker');
}
