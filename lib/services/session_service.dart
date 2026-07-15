// ============================================================
// lib/services/session_service.dart
// Guarda y lee las sesiones de entrenamiento en Supabase
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final SupabaseClient _sb = Supabase.instance.client;

  // ── GUARDAR una sesión de entrenamiento ────────────────────
  // Devuelve el ID de la sesión guardada (o null si falló).
  Future<String?> guardarSesion({
    required String ejercicio,
    required int repsTotales,
    required int repsValidas,
    required int repsInvalidas,
    required List<String> errores,
    List<Map<String, dynamic>>? repsDetalle,
    List<Map<String, int>>? erroresTimestamps,
    Map<String, dynamic>? diagnosticoIa,
    String? videoUrl,
    String? pdfUrl,        // URL del PDF en R2 (si ya se generó)
    Map<String, dynamic>? reporteCompleto, // reporte completo (para regenerar el PDF)
    String? ejercicioClave, // clave del ejercicio para la tabla normalizada
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;

    try {
      // 1) Buscar el ejercicio_id en el catálogo (tabla normalizada)
      String? ejercicioId;
      if (ejercicioClave != null) {
        try {
          final ej = await _sb
              .from('ejercicios')
              .select('id')
              .eq('clave', ejercicioClave)
              .maybeSingle();
          ejercicioId = ej?['id'] as String?;
        } catch (_) {
          ejercicioId = null; // si falla, seguimos sin romper
        }
      }

      // 2) Guardar la sesión (con columnas viejas Y la nueva ejercicio_id)
      final sesionInsertada = await _sb.from('sesiones_entrenamiento').insert({
        'perfil_id': user.id,
        'ejercicio': ejercicio,
        'ejercicio_id': ejercicioId, // NUEVO (normalizado)
        'reps_totales': repsTotales,
        'reps_validas': repsValidas,
        'reps_invalidas': repsInvalidas,
        'errores': errores,
        'reps_detalle': repsDetalle,
        'errores_timestamps': erroresTimestamps,
        'diagnostico_ia': diagnosticoIa,
        'reporte_completo': reporteCompleto, // guardamos el reporte completo
        'video_url': videoUrl,
        'pdf_url': pdfUrl,                    // URL del PDF (puede ir null al inicio)
        'estado': 'completada',
        'fecha_programada': DateTime.now().toIso8601String().substring(0, 10),
        'hora_inicio': DateTime.now().toIso8601String(),
        'hora_fin': DateTime.now().toIso8601String(),
      }).select('id').single();

      final sesionId = sesionInsertada['id'] as String;

      // 3) Guardar cada repetición en la tabla normalizada 'repeticiones'
      if (repsDetalle != null && repsDetalle.isNotEmpty) {
        final filas = <Map<String, dynamic>>[];
        for (var i = 0; i < repsDetalle.length; i++) {
          final r = repsDetalle[i];
          filas.add({
            'sesion_id': sesionId,
            'numero': i + 1,
            'es_valida': r['valida'] == true,
            'razon': r['razon']?.toString(),
          });
        }
        try {
          await _sb.from('repeticiones').insert(filas);
        } catch (_) {
          // si falla lo normalizado, la sesión ya quedó guardada igual
        }
      }

      return sesionId;
    } catch (e) {
      return null;
    }
  }

  // ── ACTUALIZAR la URL del PDF de una sesión ya guardada ────
  // Se usa cuando el usuario toca "Generar documento" y el PDF sube a R2.
  Future<String?> actualizarPdfUrl(String sesionId, String pdfUrl) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión iniciada';
    try {
      await _sb
          .from('sesiones_entrenamiento')
          .update({'pdf_url': pdfUrl})
          .eq('id', sesionId)
          .eq('perfil_id', user.id);
      return null;
    } catch (e) {
      return 'No se pudo guardar el PDF: $e';
    }
  }

  // ── ELIMINAR una sesión de entrenamiento (lado USUARIO) ────
  Future<String?> eliminarSesion(String sesionId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión iniciada';

    try {
      try {
        await _sb.from('repeticiones').delete().eq('sesion_id', sesionId);
      } catch (_) {}

      await _sb
          .from('sesiones_entrenamiento')
          .delete()
          .eq('id', sesionId)
          .eq('perfil_id', user.id);

      return null;
    } catch (_) {
      return 'No se pudo eliminar el entrenamiento';
    }
  }

  // ── LEER UNA sesión por su ID (versión fresca, con el pdf_url actual) ──────
  Future<Map<String, dynamic>?> sesionPorId(String sesionId) async {
    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select()
          .eq('id', sesionId)
          .maybeSingle();
      return data;
    } catch (_) {
      return null;
    }
  }

  // ── LEER las sesiones del usuario (para el historial) ──────
  Future<List<Map<String, dynamic>>> obtenerHistorial() async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];

    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select()
          .eq('perfil_id', user.id)
          .order('created_at', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ── SESIONES DE HOY (para el home) — máximo 5 ──────────────
  Future<List<Map<String, dynamic>>> obtenerSesionesDeHoy() async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];

    final ahora = DateTime.now();
    final inicioHoy = DateTime(ahora.year, ahora.month, ahora.day);

    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select()
          .eq('perfil_id', user.id)
          .gte('created_at', inicioHoy.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(5);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ── TODAS las sesiones (para el historial completo en Perfil) ─
  Future<List<Map<String, dynamic>>> obtenerTodoElHistorial() async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];

    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select()
          .eq('perfil_id', user.id)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ── ESTADÍSTICAS para el home (totales) ────────────────────
  Future<Map<String, int>> obtenerEstadisticas() async {
    final user = _sb.auth.currentUser;
    if (user == null) return {'sesiones': 0, 'repsValidas': 0, 'eficiencia': 0};

    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select('reps_totales, reps_validas')
          .eq('perfil_id', user.id);

      final lista = List<Map<String, dynamic>>.from(data);
      int totalReps = 0;
      int totalValidas = 0;
      for (final s in lista) {
        totalReps += (s['reps_totales'] as int?) ?? 0;
        totalValidas += (s['reps_validas'] as int?) ?? 0;
      }
      final eficiencia = totalReps > 0 ? ((totalValidas / totalReps) * 100).round() : 0;

      return {
        'sesiones': lista.length,
        'repsValidas': totalValidas,
        'eficiencia': eficiencia,
      };
    } catch (_) {
      return {'sesiones': 0, 'repsValidas': 0, 'eficiencia': 0};
    }
  }

  // ── DATOS PARA LA PANTALLA DE PROGRESO ─────────────────────
  Future<Map<String, dynamic>> obtenerProgreso() async {
    final user = _sb.auth.currentUser;
    final vacio = {
      'sesionesTotales': 0,
      'eficienciaMedia': 0,
      'repsValidas': 0,
      'erroresDetectados': 0,
      'sesionesSemana': 0,
      'eficienciaPorDia': List<double>.filled(7, 0),
    };
    if (user == null) return vacio;

    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select('reps_totales, reps_validas, reps_invalidas, errores, created_at')
          .eq('perfil_id', user.id);

      final lista = List<Map<String, dynamic>>.from(data);

      int totalReps = 0, totalValidas = 0, totalErrores = 0;
      for (final s in lista) {
        totalReps += (s['reps_totales'] as int?) ?? 0;
        totalValidas += (s['reps_validas'] as int?) ?? 0;
        final errs = s['errores'];
        if (errs is List) totalErrores += errs.length;
      }
      final efMedia = totalReps > 0 ? ((totalValidas / totalReps) * 100).round() : 0;

      final ahora = DateTime.now();
      final lunes = DateTime(ahora.year, ahora.month, ahora.day)
          .subtract(Duration(days: ahora.weekday - 1));

      int sesionesSemana = 0;
      final validasDia = List<int>.filled(7, 0);
      final totalesDia = List<int>.filled(7, 0);

      for (final s in lista) {
        final fecha = DateTime.tryParse(s['created_at']?.toString() ?? '')?.toLocal();
        if (fecha == null) continue;
        if (fecha.isAfter(lunes)) {
          sesionesSemana++;
          final idx = fecha.weekday - 1;
          validasDia[idx] += (s['reps_validas'] as int?) ?? 0;
          totalesDia[idx] += (s['reps_totales'] as int?) ?? 0;
        }
      }

      final eficienciaPorDia = List<double>.generate(7, (i) {
        if (totalesDia[i] == 0) return 0.0;
        return (validasDia[i] / totalesDia[i]) * 100;
      });

      return {
        'sesionesTotales': lista.length,
        'eficienciaMedia': efMedia,
        'repsValidas': totalValidas,
        'erroresDetectados': totalErrores,
        'sesionesSemana': sesionesSemana,
        'eficienciaPorDia': eficienciaPorDia,
      };
    } catch (_) {
      return vacio;
    }
  }
}