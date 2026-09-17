import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Hoja de etiquetas carta. Medidas en pulgadas, como vienen en el paquete de etiquetas.
enum FormatoEtiqueta {
  chica('3 × 10 · 2⅝ × 1 pulgada (Avery 5160 o compatible)', 3, 10, 2.625, 1.0, 0.1875, 0.5, 2.75, 1.0),
  grande('2 × 5 · 4 × 2 pulgadas (Avery 5163 o compatible), para gabinetes', 2, 5, 4.0, 2.0, 0.15625, 0.5, 4.1875, 2.0);

  const FormatoEtiqueta(this.nombre, this.columnas, this.filas, this.ancho, this.alto, this.margenIzquierdo,
      this.margenSuperior, this.pasoHorizontal, this.pasoVertical);

  final String nombre;
  final int columnas;
  final int filas;
  final double ancho;
  final double alto;
  final double margenIzquierdo;
  final double margenSuperior;
  final double pasoHorizontal;
  final double pasoVertical;

  int get porHoja => columnas * filas;
}

class EtiquetaDatos {
  const EtiquetaDatos({required this.codigo, required this.titulo, this.detalle});

  /// A-0101 o C-0012: va en el QR y debajo, por si el QR no se puede leer.
  final String codigo;
  final String titulo;

  /// Ruta del contenedor, o categoría del artículo.
  final String? detalle;
}

/// La dirección que lleva el QR: al escanearlo con la cámara normal del celular abre la ficha.
String direccionDeCodigo(String urlApp, String codigo) => '${urlApp.replaceAll(RegExp(r'/+$'), '')}/q/$codigo';

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
