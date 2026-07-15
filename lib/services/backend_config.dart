// ============================================================
// lib/services/backend_config.dart
// Configuración del backend (Edge Functions de Supabase).
// Aquí viven SOLO datos públicos (URL y anon key). Las credenciales
// peligrosas (OpenAI key, R2 secret) viven en los secrets de Supabase,
// NO en la app.
// ============================================================
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BackendConfig {
  // URL base de las Edge Functions de tu proyecto Supabase.
  static const String functionsUrl =
      'https://ixthuzahrwoswbjjlbok.supabase.co/functions/v1';

  // La anon key (pública por diseño, la misma que ya usa tu app para
  // Supabase). Se lee del .env. No es un secreto peligroso.
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
}