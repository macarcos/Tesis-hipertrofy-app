// ============================================================
// lib/services/fecha_helper.dart
// Convierte una fecha en texto tipo "Hoy 2:30pm", "Ayer 1:23pm",
// "15 jun 6:00am"
// ============================================================

class FechaHelper {
  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];

  // Recibe el valor de created_at (string ISO) y devuelve texto legible
  static String formatear(dynamic createdAt) {
    if (createdAt == null) return '';
    final fecha = DateTime.tryParse(createdAt.toString())?.toLocal();
    if (fecha == null) return '';

    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final diaFecha = DateTime(fecha.year, fecha.month, fecha.day);
    final difDias = hoy.difference(diaFecha).inDays;

    final hora = _hora12(fecha);

    if (difDias == 0) return 'Hoy $hora';
    if (difDias == 1) return 'Ayer $hora';
    return '${fecha.day} ${_meses[fecha.month - 1]} $hora';
  }

  // Solo la hora (para el home, donde ya se sabe que es de hoy)
  static String soloHora(dynamic createdAt) {
    if (createdAt == null) return '';
    final fecha = DateTime.tryParse(createdAt.toString())?.toLocal();
    if (fecha == null) return '';
    return _hora12(fecha);
  }

  // Convierte a formato 12h: "2:30pm"
  static String _hora12(DateTime f) {
    int h = f.hour;
    final m = f.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'pm' : 'am';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:$m$ampm';
  }
}