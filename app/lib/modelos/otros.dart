import 'catalogos.dart';

class Foto {
  const Foto({required this.id, required this.ruta, required this.url, required this.esPrincipal, required this.tipo, required this.tomadaEn});

  final String id;
  final String ruta;
  final String url;
  final bool esPrincipal;
  final TipoFoto tipo;
  final DateTime tomadaEn;
}

class MovimientoPublico {
  const MovimientoPublico({required this.tipo, required this.cantidad, required this.fecha, this.prestadoHasta});

  final String tipo;
  final int cantidad;
  final DateTime fecha;
  final DateTime? prestadoHasta;

  factory MovimientoPublico.desdeMapa(Map<String, dynamic> m) => MovimientoPublico(
        tipo: m['tipo'] as String,
        cantidad: m['cantidad'] as int,
        fecha: DateTime.parse(m['fecha'] as String),
        prestadoHasta: m['prestado_hasta'] == null ? null : DateTime.parse(m['prestado_hasta'] as String),
      );

  String get nombre => nombresMovimiento[tipo] ?? tipo;
}

class Pendiente {
  const Pendiente({required this.tipo, required this.descripcion, required this.prioridadAlta});

  final String tipo;
  final String descripcion;
  final bool prioridadAlta;

  factory Pendiente.desdeMapa(Map<String, dynamic> m) => Pendiente(
        tipo: m['tipo'] as String,
        descripcion: m['descripcion'] as String,
        prioridadAlta: (m['prioridad'] as int) == 1,
      );

  String get nombre => nombresTarea[tipo] ?? tipo;
}

class PersonaPin {
  const PersonaPin(this.id, this.nombre);
  final String id;
  final String nombre;
}

class Cuenta {
  const Cuenta({
    required this.id,
    required this.nombre,
    required this.rol,
    required this.activo,
    required this.tienePin,
    this.correo,
    this.pinBloqueadoHasta,
  });

  final String id;
  final String nombre;
  final String? correo;
  final Rol rol;
  final bool activo;
  final bool tienePin;
  final DateTime? pinBloqueadoHasta;

  factory Cuenta.desdeMapa(Map<String, dynamic> m) => Cuenta(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        correo: m['correo'] as String?,
        rol: Rol.desde(m['rol'] as String),
        activo: m['activo'] as bool,
        tienePin: m['tiene_pin'] as bool,
        pinBloqueadoHasta: m['pin_bloqueado_hasta'] == null ? null : DateTime.parse(m['pin_bloqueado_hasta'] as String),
      );
}
