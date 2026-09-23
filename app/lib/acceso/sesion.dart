import '../modelos/catalogos.dart';

enum NivelSesion { pin, contrasena }

/// La sesión tal como la ve el servidor (public.mi_sesion).
class Sesion {
  const Sesion({
    required this.id,
    required this.nombre,
    required this.rol,
    required this.nivel,
    required this.activo,
    required this.vigente,
    required this.tienePin,
    this.expiraEn,
  });

  final String id;
  final String nombre;
  final Rol rol;
  final NivelSesion nivel;
  final bool activo;
  final bool vigente;
  final bool tienePin;
  final DateTime? expiraEn;

  static Sesion? desdeMapa(Map<String, dynamic>? m) {
    if (m == null || m['id'] == null) return null;
    return Sesion(
      id: m['id'] as String,
      nombre: m['nombre'] as String,
      rol: Rol.desde(m['rol'] as String),
      nivel: m['nivel'] == 'CONTRASENA' ? NivelSesion.contrasena : NivelSesion.pin,
      activo: m['activo'] as bool,
      vigente: m['vigente'] as bool,
      tienePin: m['tiene_pin'] as bool,
      expiraEn: m['expira_en'] == null ? null : DateTime.parse(m['expira_en'] as String),
    );
  }

  bool get administra => rol == Rol.responsable || rol == Rol.subadmin;

  /// La selección de robótica: ve el catálogo y propone, no mueve el inventario.
  bool get esSeleccion => rol == Rol.seleccion;

  /// Personal del taller (docentes y administración).
  bool get esDelTaller => !esSeleccion;

  String get nombreCorto => nombre.split(' ').firstWhere((p) => !p.endsWith('.'), orElse: () => nombre);
}

enum Nivel { sesion, contrasena }

/// Qué pide una acción (sección 0 y matriz de permisos de docs/flujos.md).
class Requisito {
  const Requisito(this.nivel, {this.roles, this.confirmar = false});

  final Nivel nivel;
  final Set<Rol>? roles;

  /// Nivel N3: reconfirmar la contraseña justo antes de la acción.
  final bool confirmar;

  /// N1 del personal del taller, con PIN o contraseña (prestar, devolver, notas).
  /// La selección de robótica no entra aquí: solo propone.
  static const docente = Requisito(Nivel.sesion, roles: {Rol.docente, Rol.responsable, Rol.subadmin});

  /// N1 de cualquier cuenta, incluida la selección de robótica: fotos, conteos,
  /// reportes de daño y propuestas.
  static const cualquiera = Requisito(Nivel.sesion);

  /// N2: responsable o sub administración con contraseña (alta, edición).
  static const administracion = Requisito(Nivel.contrasena, roles: {Rol.responsable, Rol.subadmin});

  /// N3 sobre N2 (pasar entre VEX y FTC, cuentas).
  static const administracionConfirmada =
      Requisito(Nivel.contrasena, roles: {Rol.responsable, Rol.subadmin}, confirmar: true);

  /// Bitácora completa: solo sub administración con contraseña.
  static const subadministracion = Requisito(Nivel.contrasena, roles: {Rol.subadmin});

  /// N3 para cualquier cuenta (cambiar su propio PIN).
  static const propiaConfirmada = Requisito(Nivel.contrasena, confirmar: true);
}

enum Falta { nada, sesion, rol, contrasena }

/// Qué le falta a la sesión actual para la acción. Primero la cuenta, luego el rol, luego la contraseña:
/// a un docente no se le pide contraseña para algo que su cuenta nunca podría hacer.
Falta evaluar(Sesion? sesion, Requisito requisito) {
  if (sesion == null || !sesion.activo || !sesion.vigente) return Falta.sesion;
  if (requisito.roles != null && !requisito.roles!.contains(sesion.rol)) return Falta.rol;
  if (requisito.nivel == Nivel.contrasena && sesion.nivel != NivelSesion.contrasena) return Falta.contrasena;
  return Falta.nada;
}
