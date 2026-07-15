import 'dart:convert';
import 'package:http/http.dart' as http;
import 'backend_config.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ai_coach_service.dart
// Contiene: AiCoachService, LiveFeedback, MedicalReport, ReporteCompleto
// Las llamadas a OpenAI pasan por el BACKEND (Edge Functions de Supabase).
// La API key NO vive en la app, vive en los secrets de Supabase.
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// ESTUDIOS CIENTÍFICOS (verificados). La IA los cita en el reporte.
// IMPORTANTE: estos datos son reales y verificables. Si necesitas ajustar algún
// hallazgo, edita SOLO el texto de 'hallazgo' (autor, año y título no se tocan).
// ══════════════════════════════════════════════════════════════════════════════
const String _estudiosCientificos = '''
ESTUDIOS CIENTÍFICOS DISPONIBLES PARA CITAR (usa cita APA: Autor et al., año):

1. Serafim et al. (2023) - "Which resistance training is safest to practice? A systematic review" (Journal of Orthopaedic Surgery and Research). Hallazgo: revisión sistemática sobre seguridad en el entrenamiento de fuerza; identifica que la técnica incorrecta y la sobrecarga son factores de riesgo principales de lesión musculoesquelética, y que la prevención se basa en la correcta ejecución biomecánica.

2. Chae et al. (2023) - "An artificial intelligence exercise coaching mobile app: Development and randomized controlled trial to verify its effectiveness in posture correction" (Interactive Journal of Medical Research). Hallazgo: una app móvil de IA para corregir la postura demostró, en un ensayo controlado aleatorizado, mejoras significativas en la corrección postural de los usuarios frente al grupo control.

3. Ko et al. (2024) - "Pose estimation for exercise analysis" (IEEE Access). Hallazgo: los sistemas de estimación de pose por visión por computadora permiten analizar la ejecución de ejercicios y detectar errores de técnica en tiempo real con buena precisión.

4. Liew et al. (2025) - "Human pose estimation for exercise monitoring" (International Journal of Advanced Computer Science and Applications, IJACSA). Hallazgo: el monitoreo de ejercicios mediante estimación de pose humana es viable en dispositivos móviles y ayuda a dar retroalimentación inmediata sobre la forma del movimiento.

5. Supanich et al. (2023) - "Real-time body movement detection" (ICACCS, IEEE). Hallazgo: la detección de movimiento corporal en tiempo real mediante puntos clave del cuerpo permite cuantificar ángulos articulares y evaluar la calidad del movimiento durante el ejercicio.
''';

class LiveFeedback {
  final String estado;
  final String feedbackCorto;
  final String colorAlerta;

  LiveFeedback({
    required this.estado,
    required this.feedbackCorto,
    required this.colorAlerta,
  });

  factory LiveFeedback.fromJson(Map<String, dynamic> json) => LiveFeedback(
    estado:        json['estado']         ?? 'Bueno',
    feedbackCorto: json['feedback_corto'] ?? '',
    colorAlerta:   json['color_alerta']   ?? 'verde',
  );

  factory LiveFeedback.ok() => LiveFeedback(
    estado:        'Perfecto',
    feedbackCorto: 'Excelente técnica',
    colorAlerta:   'verde',
  );
}

class MedicalReport {
  final String musculosEnRiesgo;
  final String posibleLesion;
  final String descripcion;
  final String recomendacion;
  final String nivelRiesgo;

  MedicalReport({
    required this.musculosEnRiesgo,
    required this.posibleLesion,
    required this.descripcion,
    required this.recomendacion,
    required this.nivelRiesgo,
  });

  factory MedicalReport.fromJson(Map<String, dynamic> json) => MedicalReport(
    musculosEnRiesgo: json['musculos_en_riesgo'] ?? '',
    posibleLesion:    json['posible_lesion']     ?? 'Ninguna',
    descripcion:      json['descripcion']        ?? '',
    recomendacion:    json['recomendacion']      ?? '',
    nivelRiesgo:      json['nivel_riesgo']       ?? 'bajo',
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// REPORTE COMPLETO de 4 hojas (para el PDF). Tiene varias secciones que la IA
// llena citando los estudios científicos.
// ══════════════════════════════════════════════════════════════════════════════
class ReporteCompleto {
  final String resumenGeneral;       // Hoja 1: resumen del desempeño
  final String analisisBiomecanico;  // Hoja 2: qué pasó con el cuerpo
  final String musculosEnRiesgo;     // Hoja 2: músculos/articulaciones
  final String posibleLesion;        // Hoja 2: lesión que podría desarrollarse
  final String evidenciaCientifica;  // Hoja 3: cita los estudios
  final String recomendaciones;      // Hoja 4: plan de corrección
  final String nivelRiesgo;          // bajo | medio | alto

  ReporteCompleto({
    required this.resumenGeneral,
    required this.analisisBiomecanico,
    required this.musculosEnRiesgo,
    required this.posibleLesion,
    required this.evidenciaCientifica,
    required this.recomendaciones,
    required this.nivelRiesgo,
  });

  factory ReporteCompleto.fromJson(Map<String, dynamic> json) => ReporteCompleto(
    resumenGeneral:      json['resumen_general']      ?? '',
    analisisBiomecanico: json['analisis_biomecanico'] ?? '',
    musculosEnRiesgo:    json['musculos_en_riesgo']   ?? '',
    posibleLesion:       json['posible_lesion']       ?? 'Ninguna',
    evidenciaCientifica: json['evidencia_cientifica'] ?? '',
    recomendaciones:     json['recomendaciones']      ?? '',
    nivelRiesgo:         json['nivel_riesgo']         ?? 'bajo',
  );

  // Reporte de respaldo si la IA no responde (sin internet, etc.)
  factory ReporteCompleto.respaldo(String ejercicio) => ReporteCompleto(
    resumenGeneral: 'No se pudo generar el análisis con IA en este momento '
        '(sin conexión). Tus repeticiones y errores quedaron registrados.',
    analisisBiomecanico: 'El análisis biomecánico detallado requiere conexión a internet.',
    musculosEnRiesgo: 'No disponible sin conexión.',
    posibleLesion: 'No disponible',
    evidenciaCientifica: 'La evidencia científica se mostrará cuando haya conexión.',
    recomendaciones: 'Mantén una técnica controlada y consulta a tu entrenador.',
    nivelRiesgo: 'bajo',
  );
}

class AiCoachService {
  final String userLevel;
  final double userWeightKg;

  AiCoachService({
    required this.userLevel,
    required this.userWeightKg,
  });

  // ── Análisis en tiempo real ────────────────────────────────────────────────
  Future<LiveFeedback> analyzeLive({
    required String ejercicio,
    required String fase,
    required Map<String, dynamic> anglesJson,
  }) async {
    // El feedback en vivo lo da el cálculo local de ángulos (angle_calculator),
    // no OpenAI. Devolvemos OK para no romper nada. La key ya no vive en la app.
    return LiveFeedback.ok();
  }

  // ── Reporte médico corto (el que ya usabas, intacto) ───────────────────────
  Future<MedicalReport?> getMedicalReport({
    required String ejercicio,
    required List<String> errores,
    required int totalReps,
    required int invalidReps,
  }) async {
    if (errores.isEmpty) return null;

    // Reutiliza la Edge Function 'reporte-ia' (la key vive en el backend) y
    // mapea el resultado al formato corto del MedicalReport.
    try {
      final response = await http.post(
        Uri.parse('${BackendConfig.functionsUrl}/reporte-ia'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${BackendConfig.anonKey}',
        },
        body: jsonEncode({
          'ejercicio': ejercicio,
          'errores': errores,
          'totalReps': totalReps,
          'validReps': totalReps - invalidReps,
          'invalidReps': invalidReps,
          'userLevel': userLevel,
          'userWeightKg': userWeightKg,
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final clean = response.body.replaceAll(RegExp(r'```json|```'), '').trim();
        final j = jsonDecode(clean);
        // Mapeamos los campos del reporte completo al formato corto
        return MedicalReport(
          musculosEnRiesgo: j['musculos_en_riesgo'] ?? '',
          posibleLesion:    j['posible_lesion'] ?? 'Ninguna',
          descripcion:      j['analisis_biomecanico'] ?? '',
          recomendacion:    j['recomendaciones'] ?? '',
          nivelRiesgo:      j['nivel_riesgo'] ?? 'bajo',
        );
      }
    } catch (_) {}
    return null;
  }

  // ── REPORTE COMPLETO de 4 hojas (para el PDF, con citas científicas) ───────
  Future<ReporteCompleto> getReporteCompleto({
    required String ejercicio,
    required List<String> errores,
    required int totalReps,
    required int validReps,
    required int invalidReps,
  }) async {
    // Llama a la Edge Function 'reporte-ia' (la API key de OpenAI vive en el
    // backend, NO en la app). Solo le mandamos los datos de la sesión.
    try {
      final response = await http.post(
        Uri.parse('${BackendConfig.functionsUrl}/reporte-ia'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${BackendConfig.anonKey}',
        },
        body: jsonEncode({
          'ejercicio': ejercicio,
          'errores': errores,
          'totalReps': totalReps,
          'validReps': validReps,
          'invalidReps': invalidReps,
          'userLevel': userLevel,
          'userWeightKg': userWeightKg,
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final clean = response.body.replaceAll(RegExp(r'```json|```'), '').trim();
        return ReporteCompleto.fromJson(jsonDecode(clean));
      }
    } catch (_) {}
    return ReporteCompleto.respaldo(ejercicio);
  }
}