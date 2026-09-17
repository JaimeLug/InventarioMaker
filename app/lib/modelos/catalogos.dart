/// Códigos de la base y cómo se dicen en pantalla.
library;

enum Categoria {
  vex('VEX', 'VEX'),
  ftc('FTC', 'FTC'),
  herramientas('HERRAMIENTAS', 'Herramientas'),
  herramientasElectricas('HERRAMIENTAS_ELECTRICAS', 'Herramientas eléctricas'),
  consumibles('CONSUMIBLES', 'Consumibles'),
  comun('COMUN', 'Común'),
  sinClasificar('SIN_CLASIFICAR', 'Sin clasificar');

  const Categoria(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static Categoria desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);

  /// VEX y FTC son sistemas incompatibles: pasar de uno a otro pide justificación.
  bool esRobotica() => this == vex || this == ftc;
}

enum EstadoInventario {
  sinClasificar('SIN_CLASIFICAR', 'Sin clasificar'),
  porContar('POR_CONTAR', 'Por contar'),
  porVerificar('POR_VERIFICAR', 'Por verificar'),
  verificado('VERIFICADO', 'Verificado'),
  desglosado('DESGLOSADO', 'Desglosado'),
  dadoDeBaja('DADO_DE_BAJA', 'Dado de baja');

  const EstadoInventario(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static EstadoInventario desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);
}

enum EstadoFisico {
  nuevo('NUEVO', 'Nuevo'),
  usado('USADO', 'Usado'),
  incompleto('INCOMPLETO', 'Incompleto'),
  danado('DANADO', 'Dañado'),
  sinAbrir('SIN_ABRIR', 'Sin abrir'),
  vacio('VACIO', 'Vacío');

  const EstadoFisico(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static EstadoFisico? desde(String? codigo) =>
      codigo == null ? null : values.firstWhere((v) => v.codigo == codigo);
}

enum Etiquetado {
  individual('INDIVIDUAL', 'Individual', 'Lleva su propio QR (equipos con serie o resguardo)'),
  contenedor('CONTENEDOR', 'En contenedor', 'El QR va en el cajón o bolsa donde vive'),
  lote('LOTE', 'Por lote', 'Sin QR; se descuenta por cantidad');

  const Etiquetado(this.codigo, this.nombre, this.explicacion);
  final String codigo;
  final String nombre;
  final String explicacion;

  static Etiquetado desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);
}

enum TipoFoto {
  general('GENERAL', 'General'),
  placaSerie('PLACA_SERIE', 'Placa de serie'),
  etiquetaResguardo('ETIQUETA_RESGUARDO', 'Etiqueta de resguardo'),
  dano('DANO', 'Daño'),
  entrega('ENTREGA', 'Entrega'),
  conteo('CONTEO', 'Conteo');

  const TipoFoto(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static TipoFoto desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);

  /// Las que se pueden agregar desde la ficha; las demás nacen de reportes y entregas.
  static const delCatalogo = [general, placaSerie, etiquetaResguardo];
}

enum Rol {
  docente('DOCENTE', 'Docente'),
  responsable('RESPONSABLE', 'Responsable del laboratorio'),
  subadmin('SUBADMIN', 'Sub administración');

  const Rol(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static Rol desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);
}

const nombresMovimiento = {
  'PRESTAMO': 'Préstamo',
  'DEVOLUCION': 'Devolución',
  'CONSUMO': 'Consumo',
  'PERDIDA': 'Pérdida',
  'DANO': 'Daño',
  'REPARACION': 'Reparación',
  'ALTA': 'Alta',
  'BAJA': 'Baja',
  'AJUSTE_CONTEO': 'Ajuste de conteo',
  'EXTENSION': 'Extensión de préstamo',
};

const nombresTarea = {
  'CONTAR': 'Contar físicamente',
  'VERIFICAR_DATO': 'Verificar dato o contenido',
  'ABRIR_REVISAR': 'Abrir y revisar contenido',
  'REGISTRAR_SERIE': 'Registrar serie o medida',
  'IDENTIFICAR_ETIQUETAR': 'Identificar y etiquetar',
  'FALTA_PIEZA': 'Falta pieza o dato',
  'DEFINIR_VEX_FTC': 'Definir si es VEX o FTC',
  'CONFIRMAR_VACIO': 'Confirmar si está vacío',
  'LOCALIZAR_CONTENIDO': 'Localizar contenido faltante',
};

const unidadesComunes = ['pieza', 'caja', 'bolsa', 'juego', 'paquete', 'rollo', 'estuche', 'kit'];

enum TipoSolicitante {
  alumno('ALUMNO', 'Alumno'),
  maestro('MAESTRO', 'Maestro'),
  otro('OTRO', 'Otro');

  const TipoSolicitante(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static TipoSolicitante desde(String codigo) => values.firstWhere((v) => v.codigo == codigo);
}

/// Motivos del ajuste de conteo (F-13).
const motivosAjuste = {
  'CONTEO_FISICO': 'Conteo físico',
  'ERROR_CAPTURA': 'Error de captura inicial',
  'APARECIO': 'Apareció',
  'NO_SE_ENCONTRO': 'No se encontró',
};

/// Motivos de baja (F-14).
const motivosBaja = {
  'IRREPARABLE': 'Irreparable',
  'OBSOLETO': 'Obsoleto',
  'PERDIDA_CONFIRMADA': 'Pérdida confirmada',
  'DONACION': 'Donación o transferencia',
  'OTRO': 'Otro',
};

const dominioCorreoAlumnos = 'prepasoficiales.net';
