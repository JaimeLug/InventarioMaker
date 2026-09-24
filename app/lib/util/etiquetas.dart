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
