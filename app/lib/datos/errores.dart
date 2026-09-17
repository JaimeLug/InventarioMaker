import 'package:supabase_flutter/supabase_flutter.dart';

/// Un error con un mensaje que se puede mostrar tal cual a un docente.
class ErrorApp implements Exception {
  const ErrorApp(this.mensaje, {this.codigo, this.detalle});

  final String mensaje;

  /// PT401 = hay que identificarse; PT403 = falta rol, contraseña o confirmación.
  final String? codigo;

  /// ROL | NIVEL_CONTRASENA | CONFIRMAR_CONTRASENA | CUENTA_INACTIVA | SESION_VENCIDA | SIN_SESION
  final String? detalle;

  bool get pideAcceso => codigo == 'PT401';

  @override
  String toString() => mensaje;
}

const _sinConexion = 'No hay conexión con el servidor. Revisa el internet e intenta de nuevo.';

ErrorApp traducir(Object error) {
  if (error is ErrorApp) return error;
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return const ErrorApp('No tienes permiso para hacer esto. Identifícate con una cuenta que pueda.', codigo: 'PT401');
    }
    return ErrorApp(error.message, codigo: error.code, detalle: error.details?.toString());
  }
  if (error is AuthException) {
    final texto = '${error.code} ${error.message}'.toLowerCase();
    if (texto.contains('invalid') && texto.contains('credential')) {
      return const ErrorApp('Correo o contraseña incorrectos.');
    }
    if (texto.contains('banned')) return const ErrorApp('Esta cuenta está desactivada. Habla con el responsable del laboratorio.');
    if (texto.contains('fetch') || texto.contains('socket')) return const ErrorApp(_sinConexion);
    return ErrorApp('No se pudo entrar: ${error.message}');
  }
  if (error is FunctionException) {
    final datos = error.details;
    if (datos is Map && datos['mensaje'] is String) return ErrorApp(datos['mensaje'] as String);
    return const ErrorApp('El servidor no pudo completar la acción. Intenta de nuevo.');
  }
  if (error is StorageException) {
    return ErrorApp('No se pudo subir la foto (${error.message}). Intenta de nuevo.');
  }
  final texto = error.toString();
  if (texto.contains('SocketException') || texto.contains('Failed to fetch') || texto.contains('ClientException')) {
    return const ErrorApp(_sinConexion);
  }
  return ErrorApp('Algo salió mal: $texto');
}

/// Falla de red (sin señal, servidor inalcanzable o sin respuesta): lo capturado se puede guardar para después.
bool esFaltaDeConexion(Object error) {
  if (error is ErrorApp) return error.mensaje == _sinConexion;
  if (error is AuthRetryableFetchException) return true;
  final texto = error.toString();
  return texto.contains('SocketException') ||
      texto.contains('Failed host lookup') ||
      texto.contains('ClientException') ||
      texto.contains('TimeoutException') ||
      texto.contains('Connection closed') ||
      texto.contains('HandshakeException') ||
      texto.contains('Network is unreachable');
}
