import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../datos/repositorio.dart';

/// Toma una foto con la cámara o la elige de un archivo, ya reducida en el dispositivo
/// (máximo 1600 px, calidad 75: unos 200 KB) antes de subirla.
Future<FotoNueva?> elegirFoto(BuildContext context) async {
  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: const Text('Tomar foto'),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Elegir archivo o de la galería'),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (origen == null) return null;
  final archivo = await ImagePicker().pickImage(source: origen, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
  if (archivo == null) return null;
  return FotoNueva(await archivo.readAsBytes());
}
