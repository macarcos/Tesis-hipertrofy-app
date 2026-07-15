// ============================================================
// lib/services/offline_store.dart
// Guarda sesiones de entrenamiento en el TELÉFONO cuando no hay internet.
// Cada sesión pendiente = un archivo JSON (datos) + el video copiado a una
// carpeta permanente. Cuando vuelve el internet, otro servicio las sube y
// las borra de aquí (eso es la Pieza 2).
//
// NO necesita paquetes nuevos: usa path_provider (ya instalado) y dart:io.
// ============================================================
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class OfflineStore {
  // Carpeta donde guardamos las sesiones pendientes
  static Future<Directory> _carpeta() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sesiones_pendientes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── GUARDAR una sesión pendiente (sin internet) ───────────────────────────
  // Copia el video a la carpeta permanente y guarda los datos en un JSON.
  // Devuelve el id local de la sesión pendiente (o null si falla).
  static Future<String?> guardarPendiente({
    required String ejercicio,
    required int repsTotales,
    required int repsValidas,
    required int repsInvalidas,
    required List<String> errores,
    required List<Map<String, dynamic>> repsDetalle,
    required List<Map<String, int>> erroresTimestamps,
    required String videoPath, // ruta del video grabado (puede estar vacía)
  }) async {
    try {
      final dir = await _carpeta();
      final idLocal = 'local_${DateTime.now().millisecondsSinceEpoch}';

      // 1) Copiar el video a la carpeta permanente (si hay video)
      String videoLocal = '';
      if (videoPath.isNotEmpty) {
        final orig = File(videoPath);
        if (await orig.exists()) {
          videoLocal = '${dir.path}/$idLocal.mp4';
          await orig.copy(videoLocal);
        }
      }

      // 2) Guardar los datos en un JSON
      final datos = {
        'id_local': idLocal,
        'ejercicio': ejercicio,
        'reps_totales': repsTotales,
        'reps_validas': repsValidas,
        'reps_invalidas': repsInvalidas,
        'errores': errores,
        'reps_detalle': repsDetalle,
        'errores_timestamps': erroresTimestamps,
        'video_local': videoLocal,
        'creado': DateTime.now().toIso8601String(),
        'pendiente': true, // marca de que falta subir
      };
      final jsonFile = File('${dir.path}/$idLocal.json');
      await jsonFile.writeAsString(jsonEncode(datos));

      debugPrint('OFFLINE | Sesión guardada localmente: $idLocal');
      return idLocal;
    } catch (e) {
      debugPrint('OFFLINE | Error al guardar pendiente: $e');
      return null;
    }
  }

  // ── LEER todas las sesiones pendientes (para el historial) ────────────────
  static Future<List<Map<String, dynamic>>> leerPendientes() async {
    try {
      final dir = await _carpeta();
      final archivos = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.json'));

      final lista = <Map<String, dynamic>>[];
      for (final f in archivos) {
        try {
          final contenido = await f.readAsString();
          final datos = jsonDecode(contenido) as Map<String, dynamic>;
          lista.add(datos);
        } catch (_) {
          // si un archivo está corrupto, lo ignoramos
        }
      }

      // Ordenar por fecha de creación (más reciente primero)
      lista.sort((a, b) => (b['creado'] ?? '').toString()
          .compareTo((a['creado'] ?? '').toString()));
      return lista;
    } catch (e) {
      debugPrint('OFFLINE | Error al leer pendientes: $e');
      return [];
    }
  }

  // ── ¿Hay sesiones pendientes? (para saber si subir cuando vuelve internet) ─
  static Future<bool> hayPendientes() async {
    final lista = await leerPendientes();
    return lista.isNotEmpty;
  }

  // ── BORRAR una sesión pendiente (cuando ya se subió) ──────────────────────
  // Borra el JSON y el video local para liberar espacio.
  static Future<void> borrarPendiente(String idLocal) async {
    try {
      final dir = await _carpeta();
      final jsonFile = File('${dir.path}/$idLocal.json');
      final videoFile = File('${dir.path}/$idLocal.mp4');
      if (await jsonFile.exists()) await jsonFile.delete();
      if (await videoFile.exists()) await videoFile.delete();
      debugPrint('OFFLINE | Sesión pendiente borrada: $idLocal');
    } catch (e) {
      debugPrint('OFFLINE | Error al borrar pendiente: $e');
    }
  }
}