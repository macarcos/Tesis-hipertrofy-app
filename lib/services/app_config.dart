// ============================================================
// lib/services/app_config.dart
// Configuración global simple de la app (preferencias del usuario).
// Sin paquetes externos. Nota: estas preferencias se reinician al
// cerrar la app (vuelven a su valor por defecto).
// ============================================================

class AppConfig {
  // Grabar video de la sesión. ON por defecto (graba salvo que se apague).
  static bool grabarVideo = true;
}