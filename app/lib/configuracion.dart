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

  /// Firebase, para avisos al celular (Android). Son datos públicos del proyecto de Firebase
  /// (Configuración del proyecto → General → tu app Android). Proyecto: inventario-maker-77e2e.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyCyCm3RI-zzmA5lpEd9cs5z07JSq6hdZL4');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:850389332615:android:d205b92c09a9ccd6067e22');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '850389332615');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'inventario-maker-77e2e');

  static bool get hayFirebase => firebaseAppId.isNotEmpty && firebaseApiKey.isNotEmpty;
}
