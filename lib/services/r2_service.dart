// ============================================================
// lib/services/r2_service.dart
// Sube videos a Cloudflare R2 usando una URL FIRMADA que genera
// el backend (Edge Function 'firmar-subida'). El secret de R2 NO
// vive en la app: la función firma la subida y la app sube directo
// a R2 con esa URL temporal. Misma lógica de antes: devuelve la URL
// pública del video (o null si falla).
// ============================================================
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'backend_config.dart';

class R2Service {
  // Sube un video y devuelve la URL pública (o null si falla)
  static Future<String?> subirVideo(String rutaArchivo) async {
    try {
      final file = File(rutaArchivo);
      if (!await file.exists()) {
        debugPrint('R2 | El archivo no existe: $rutaArchivo');
        return null;
      }

      // 1) Pedir al backend una URL firmada para subir (rápido, texto pequeño)
      final firmaResp = await http.post(
        Uri.parse('${BackendConfig.functionsUrl}/firmar-subida'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${BackendConfig.anonKey}',
        },
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 15));

      if (firmaResp.statusCode != 200) {
        debugPrint('R2 | Error al pedir URL firmada: ${firmaResp.statusCode} ${firmaResp.body}');
        return null;
      }

      final firma = jsonDecode(firmaResp.body);
      final String uploadUrl = firma['uploadUrl'] ?? '';
      final String publicUrl = firma['publicUrl'] ?? '';
      if (uploadUrl.isEmpty) {
        debugPrint('R2 | La función no devolvió uploadUrl');
        return null;
      }

      // 2) Subir el video DIRECTO a R2 con la URL firmada (PUT). No pasa por
      //    el backend, va directo: rápido y aprovecha todo el internet.
      final bytes = await file.readAsBytes();
      final putResp = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'video/mp4'},
        body: bytes,
      ).timeout(const Duration(minutes: 5));

      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        debugPrint('R2 | Video subido: $publicUrl');
        return publicUrl;
      } else {
        debugPrint('R2 | Error al subir el video: ${putResp.statusCode} ${putResp.body}');
        return null;
      }
    } catch (e) {
      debugPrint('R2 | Error al subir video: $e');
      return null;
    }
  }

  // Sube un PDF (bytes) y devuelve la URL pública (o null si falla).
  // Usa la misma URL firmada del backend, pero pidiendo tipo 'pdf'.
  static Future<String?> subirPdf(List<int> pdfBytes) async {
    try {
      // 1) Pedir al backend una URL firmada para un PDF
      final firmaResp = await http.post(
        Uri.parse('${BackendConfig.functionsUrl}/firmar-subida'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${BackendConfig.anonKey}',
        },
        body: jsonEncode({'tipo': 'pdf'}),
      ).timeout(const Duration(seconds: 15));

      if (firmaResp.statusCode != 200) {
        debugPrint('R2 | Error al pedir URL firmada (pdf): ${firmaResp.statusCode} ${firmaResp.body}');
        return null;
      }

      final firma = jsonDecode(firmaResp.body);
      final String uploadUrl = firma['uploadUrl'] ?? '';
      final String publicUrl = firma['publicUrl'] ?? '';
      if (uploadUrl.isEmpty) {
        debugPrint('R2 | La función no devolvió uploadUrl (pdf)');
        return null;
      }

      // 2) Subir el PDF directo a R2 con la URL firmada
      final putResp = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'application/pdf'},
        body: pdfBytes,
      ).timeout(const Duration(minutes: 2));

      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        debugPrint('R2 | PDF subido: $publicUrl');
        return publicUrl;
      } else {
        debugPrint('R2 | Error al subir el PDF: ${putResp.statusCode} ${putResp.body}');
        return null;
      }
    } catch (e) {
      debugPrint('R2 | Error al subir PDF: $e');
      return null;
    }
  }
}