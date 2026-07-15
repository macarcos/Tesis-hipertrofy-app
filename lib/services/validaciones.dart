// ============================================================
// lib/services/validaciones.dart
// Validaciones de entrada para los formularios. Evita que se ingresen
// caracteres peligrosos o inválidos (símbolos raros, campos vacíos, etc.).
// No es "anti-hackeo" (Supabase ya protege contra inyección SQL), sino
// validación de calidad y limpieza de datos.
// ============================================================

class Validaciones {
  // Nombre / apellido: solo letras, tildes, ñ y espacios. 2 a 40 caracteres.
  // Devuelve null si está bien, o un mensaje de error si está mal.
  static String? nombre(String valor, {String campo = 'nombre'}) {
    final v = valor.trim();
    if (v.isEmpty) return 'Ingresa tu $campo';
    if (v.length < 2) return 'El $campo es muy corto';
    if (v.length > 40) return 'El $campo es muy largo';
    // Solo letras (con tildes y ñ) y espacios
    final regex = RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]+$");
    if (!regex.hasMatch(v)) {
      return 'El $campo solo puede tener letras';
    }
    return null;
  }

  // Correo: formato válido de email. 5 a 100 caracteres.
  static String? email(String valor) {
    final v = valor.trim();
    if (v.isEmpty) return 'Ingresa tu correo';
    if (v.length > 100) return 'El correo es muy largo';
    final regex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
    if (!regex.hasMatch(v)) return 'El correo no es válido';
    return null;
  }

  // Contraseña: mínimo 6, máximo 72 (límite de bcrypt que usa Supabase).
  static String? password(String valor) {
    if (valor.isEmpty) return 'Ingresa una contraseña';
    if (valor.length < 6) return 'La contraseña debe tener al menos 6 caracteres';
    if (valor.length > 20) return 'La contraseña es demasiado larga';
    return null;
  }

  // Texto general (mensajes de chat, descripciones): quita caracteres de
  // control y limita longitud. Devuelve el texto limpio.
  static String limpiarTexto(String valor, {int max = 500}) {
    // Quitar caracteres de control (invisibles) que podrían causar problemas
    var v = valor.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    v = v.trim();
    if (v.length > max) v = v.substring(0, max);
    return v;
  }
}