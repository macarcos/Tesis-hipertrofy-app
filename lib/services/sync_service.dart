// ============================================================
// lib/services/sync_service.dart
// Sube las sesiones pendientes (guardadas sin internet) cuando hay conexión.
// Por cada pendiente: sube el video a R2, genera el reporte IA, guarda en
// Supabase y borra la sesión del teléfono. Silencioso, en segundo plano.
//
// Se llama al ABRIR la app (o al entrar al historial). Si no hay internet o
// no hay pendientes, no hace nada.
// ============================================================
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'offline_store.dart';
import 'r2_service.dart';
import 'session_service.dart';
import 'ai_coach_service.dart';

class SyncService {
  static bool _subiendo = false; // evita que corra dos veces a la vez

  // Sube todos los pendientes si hay internet. Devuelve cuántos subió
  // (o -1 si ya había una subida en curso).
  static Future<int> sincronizar() async {
    if (_subiendo) return -1; // ya está corriendo
    _subiendo = true;
    int subidas = 0;

    try {
      // 1) ¿Hay internet?
      if (!await _hayInternet()) {
        _subiendo = false;
        return 0;
      }

      // 2) Leer los pendientes
      final pendientes = await OfflineStore.leerPendientes();
      if (pendientes.isEmpty) {
        _subiendo = false;
        return 0;
      }

      final total = pendientes.length;

      // 3) Subir uno por uno
      for (var idx = 0; idx < pendientes.length; idx++) {
        final p = pendientes[idx];
        final idLocal = p['id_local']?.toString();
        if (idLocal == null) continue;

        try {
          final ejercicio = p['ejercicio']?.toString() ?? 'Ejercicio';
          final repsTotales = (p['reps_totales'] as int?) ?? 0;
          final repsValidas = (p['reps_validas'] as int?) ?? 0;
          final repsInvalidas = (p['reps_invalidas'] as int?) ?? 0;
          final errores = ((p['errores'] as List?) ?? [])
              .map((e) => e.toString()).toList();
          final repsDetalle = ((p['reps_detalle'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final erroresTimestamps = ((p['errores_timestamps'] as List?) ?? [])
              .map((e) => Map<String, int>.from((e as Map).map(
                  (k, v) => MapEntry(k.toString(), (v as num).toInt())))).toList();
          final videoLocal = p['video_local']?.toString() ?? '';

          // PASO 0: Subir el video a R2 (si hay).
          // Con timeout: si tarda más de 3 min, seguimos sin video (se reintenta
          // la próxima). Así la barra nunca se queda pegada para siempre.
          String? videoUrl;
          if (videoLocal.isNotEmpty && await File(videoLocal).exists()) {
            try {
              videoUrl = await R2Service.subirVideo(videoLocal)
                  .timeout(const Duration(minutes: 3), onTimeout: () => null);
            } catch (e) {
              debugPrint('SYNC | Video tardó demasiado o falló: $e');
              videoUrl = null;
            }
          }

          // pausa breve para que el punto de "Video" se vea completarse

          // PASO 1: Generar el reporte IA (ahora sí hay internet)
          final ai = AiCoachService(userLevel: 'Principiante', userWeightKg: 70);
          MedicalReport? report;
          if (errores.isNotEmpty) {
            report = await ai.getMedicalReport(
              ejercicio: ejercicio,
              errores: errores,
              totalReps: repsTotales,
              invalidReps: repsInvalidas,
            );
          }
          ReporteCompleto? reporteComp;
          try {
            reporteComp = await ai.getReporteCompleto(
              ejercicio: ejercicio,
              errores: errores,
              totalReps: repsTotales,
              validReps: repsValidas,
              invalidReps: repsInvalidas,
            );
          } catch (_) {}

          // pausa breve para que se vea completarse el punto de "IA"

          // PASO 2: Guardar en Supabase
          final diagnostico = report == null ? null : {
            'musculos_en_riesgo': report.musculosEnRiesgo,
            'posible_lesion': report.posibleLesion,
            'descripcion': report.descripcion,
            'recomendacion': report.recomendacion,
            'nivel_riesgo': report.nivelRiesgo,
          };
          final reporteMap = reporteComp == null ? null : {
            'resumen_general': reporteComp.resumenGeneral,
            'analisis_biomecanico': reporteComp.analisisBiomecanico,
            'musculos_en_riesgo': reporteComp.musculosEnRiesgo,
            'posible_lesion': reporteComp.posibleLesion,
            'evidencia_cientifica': reporteComp.evidenciaCientifica,
            'recomendaciones': reporteComp.recomendaciones,
            'nivel_riesgo': reporteComp.nivelRiesgo,
          };

          final sesionId = await SessionService().guardarSesion(
            ejercicio: ejercicio,
            repsTotales: repsTotales,
            repsValidas: repsValidas,
            repsInvalidas: repsInvalidas,
            errores: errores,
            repsDetalle: repsDetalle,
            erroresTimestamps: erroresTimestamps,
            diagnosticoIa: diagnostico,
            reporteCompleto: reporteMap,
            videoUrl: videoUrl,
          );

          // PASO 3: Si se guardó bien, borrar del teléfono (listo)
          if (sesionId != null) {
            await OfflineStore.borrarPendiente(idLocal);
            subidas++;
            debugPrint('SYNC | Pendiente subida y borrada: $idLocal');
          } else {
            debugPrint('SYNC | No se pudo guardar en Supabase: $idLocal (se reintentará luego)');
          }
        } catch (e) {
          debugPrint('SYNC | Error subiendo $idLocal: $e (se reintentará luego)');
          // No borramos: se reintentará la próxima vez
        }
      }
    } catch (e) {
      debugPrint('SYNC | Error general: $e');
    } finally {
      _subiendo = false;
    }

    return subidas;
  }

  static Future<bool> _hayInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}