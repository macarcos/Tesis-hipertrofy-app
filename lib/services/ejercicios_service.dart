// ============================================================
// lib/services/ejercicios_service.dart
// Lee la lista de ejercicios desde Supabase. Sirve para mostrar,
// además de los 4 que ya funcionan (programados en la app), los
// ejercicios que el admin agregue desde la web (que salen como
// "en próximas actualizaciones" si no están disponibles todavía).
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';

class EjercicioRemoto {
  final String clave;
  final String nombre;
  final String musculo;
  final bool disponible;
  final String descripcion;

  EjercicioRemoto({
    required this.clave,
    required this.nombre,
    required this.musculo,
    required this.disponible,
    required this.descripcion,
  });

  factory EjercicioRemoto.fromMap(Map<String, dynamic> m) => EjercicioRemoto(
        clave: m['clave']?.toString() ?? '',
        nombre: m['nombre']?.toString() ?? 'Ejercicio',
        musculo: m['musculo']?.toString() ?? '',
        disponible: m['disponible'] == true,
        descripcion: m['descripcion']?.toString() ?? '',
      );
}

class EjerciciosService {
  final SupabaseClient _sb = Supabase.instance.client;

  // Trae todos los ejercicios de Supabase (con límite de tiempo para no colgar).
  // Si no hay internet, devuelve lista vacía (la app usa sus 4 fijos igual).
  Future<List<EjercicioRemoto>> obtenerEjercicios() async {
    try {
      final data = await _sb
          .from('ejercicios')
          .select()
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 5));
      return List<Map<String, dynamic>>.from(data)
          .map((m) => EjercicioRemoto.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }
}