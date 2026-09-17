import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

/// En la web se descarga; en el celular se pregunta dónde guardarlo. Devuelve false si se canceló.
Future<bool> guardarArchivo(Uint8List bytes, String nombre, {required bool pdf}) async {
  final tipo = pdf ? MimeType.pdf : MimeType.microsoftExcel;
  final extension = pdf ? 'pdf' : 'xlsx';
  if (kIsWeb) {
    await FileSaver.instance.saveFile(name: nombre, bytes: bytes, fileExtension: extension, mimeType: tipo);
    return true;
  }
  final ruta = await FileSaver.instance.saveAs(name: nombre, bytes: bytes, fileExtension: extension, mimeType: tipo);
  return ruta != null && ruta.isNotEmpty;
}
