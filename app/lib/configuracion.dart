/// Datos públicos del proyecto de Supabase. Van dentro de la app: no son secretos.
///
/// Para apuntar a otro servidor (por ejemplo tras una mudanza):
///   flutter build web --dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_LLAVE_PUBLICA=...
abstract final class Configuracion {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eirouznbikpvnuhdmbnm.supabase.co',
  );
  static const supabaseLlavePublica = String.fromEnvironment(
    'SUPABASE_LLAVE_PUBLICA',
    defaultValue: 'sb_publishable_Hnud27yTrhtvrhQC5xtX4Q_pXS1FPQD',
  );

  /// Almacén de las fotos del catálogo (público para ver).
  static const almacenFotos = 'fotos';

  /// En web, la sesión se cierra tras este tiempo sin tocar la pantalla (P-5).
  static const inactividadWeb = Duration(minutes: 30);
}
