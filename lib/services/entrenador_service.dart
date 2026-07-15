// ============================================================
// lib/services/entrenador_service.dart
// Maneja: código entrenador, conexión usuario-entrenador, mensajes,
// y el sistema de BLOQUEOS (bloquear/desbloquear/listar).
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';

class EntrenadorService {
  final SupabaseClient _sb = Supabase.instance.client;

  // ── Obtener MI código de entrenador (FIJO, no cambia) ──────
  Future<String?> miCodigo() async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;
    try {
      final codigo = await _sb.rpc('obtener_mi_codigo');
      return codigo as String?;
    } catch (_) {
      try {
        final data = await _sb
            .from('perfiles')
            .select('codigo_entrenador')
            .eq('id', user.id)
            .maybeSingle();
        return data?['codigo_entrenador'] as String?;
      } catch (_) {
        return null;
      }
    }
  }

  // ── Usuario se conecta con un entrenador usando el código ──
  // Devuelve null si OK, o un mensaje de error.
  Future<String?> conectarConCodigo(String codigo) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';

    try {
      final resultado = await _sb.rpc('conectar_con_codigo', params: {
        'codigo_input': codigo,
      });

      switch (resultado.toString()) {
        case 'ok':
          return null; // éxito
        case 'codigo_invalido':
          return 'Código no válido';
        case 'no_contigo_mismo':
          return 'No puedes conectarte contigo mismo';
        case 'ya_conectado':
          return 'Ya estás conectado con este entrenador';
        case 'bloqueado':
          return 'Este entrenador te ha bloqueado';
        case 'sin_sesion':
          return 'No hay sesión';
        default:
          return 'No se pudo conectar';
      }
    } catch (_) {
      return 'No se pudo conectar';
    }
  }

  // ── Ver MI entrenador (lado usuario) ───────────────────────
  Future<Map<String, dynamic>?> miEntrenador() async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;
    try {
      final conexion = await _sb
          .from('entrenador_usuario')
          .select('entrenador_id')
          .eq('usuario_id', user.id)
          .maybeSingle();

      if (conexion == null) return null;

      final entrenador = await _sb
          .from('perfiles')
          .select('id, nombre, apellido, correo')
          .eq('id', conexion['entrenador_id'])
          .maybeSingle();
      return entrenador;
    } catch (_) {
      return null;
    }
  }

  // ── Usuario se DESCONECTA de su entrenador ─────────────────
  // Borra la conexión (no borra al entrenador, solo el vínculo).
  Future<String?> desconectarDeEntrenador() async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';
    try {
      await _sb
          .from('entrenador_usuario')
          .delete()
          .eq('usuario_id', user.id);
      return null;
    } catch (_) {
      return 'No se pudo desconectar';
    }
  }

  // Contar mensajes SIN LEER que tengo (de cualquiera, ej: mi entrenador)
  Future<int> misMensajesNoLeidos() async {
    final user = _sb.auth.currentUser;
    if (user == null) return 0;
    try {
      final data = await _sb
          .from('mensajes')
          .select('id')
          .eq('receptor_id', user.id)
          .eq('leido', false);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  // ── Ver MIS usuarios (lado entrenador) ─────────────────────
  Future<List<Map<String, dynamic>>> misUsuarios() async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];
    try {
      final conexiones = await _sb
          .from('entrenador_usuario')
          .select('usuario_id')
          .eq('entrenador_id', user.id);

      final ids = (conexiones as List).map((c) => c['usuario_id']).toList();
      if (ids.isEmpty) return [];

      final usuarios = await _sb
          .from('perfiles')
          .select('id, nombre, apellido, correo')
          .inFilter('id', ids);

      final lista = List<Map<String, dynamic>>.from(usuarios);
      for (final u in lista) {
        u['total_mensajes'] = await contarNoLeidos(u['id']);
      }
      return lista;
    } catch (_) {
      return [];
    }
  }

  // Contar los mensajes SIN LEER que ME envió un usuario
  Future<int> contarNoLeidos(String otroId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 0;
    try {
      final data = await _sb
          .from('mensajes')
          .select('id')
          .eq('emisor_id', otroId)
          .eq('receptor_id', user.id)
          .eq('leido', false);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  // ── Ver las sesiones de UN usuario (lado entrenador) ───────
  Future<List<Map<String, dynamic>>> sesionesDeUsuario(String usuarioId) async {
    try {
      final data = await _sb
          .from('sesiones_entrenamiento')
          .select()
          .eq('perfil_id', usuarioId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ── Eliminar (desconectar) un usuario ──────────────────────
  Future<String?> eliminarUsuario(String usuarioId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';
    try {
      await _sb
          .from('entrenador_usuario')
          .delete()
          .eq('entrenador_id', user.id)
          .eq('usuario_id', usuarioId);
      return null;
    } catch (_) {
      return 'No se pudo eliminar';
    }
  }

  // ── BLOQUEOS ───────────────────────────────────────────────

  // Bloquear un usuario (RPC: guarda el bloqueo + borra la conexión).
  // El bloqueo persiste aunque no haya conexión activa.
  Future<String?> bloquearUsuario(String usuarioId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';
    try {
      final res = await _sb.rpc('bloquear_usuario', params: {
        'usuario_input': usuarioId,
      });
      return res.toString() == 'ok' ? null : 'No se pudo bloquear';
    } catch (_) {
      return 'No se pudo bloquear';
    }
  }

  // Desbloquear un usuario (borra el bloqueo; ya puede reconectarse).
  Future<String?> desbloquearUsuario(String usuarioId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';
    try {
      final res = await _sb.rpc('desbloquear_usuario', params: {
        'usuario_input': usuarioId,
      });
      return res.toString() == 'ok' ? null : 'No se pudo desbloquear';
    } catch (_) {
      return 'No se pudo desbloquear';
    }
  }

  // Lista de usuarios que YO (entrenador) tengo bloqueados.
  Future<List<Map<String, dynamic>>> usuariosBloqueados() async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];
    try {
      final data = await _sb.rpc('mis_usuarios_bloqueados');
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ── MENSAJES ───────────────────────────────────────────────

  // Enviar un mensaje a otra persona (con cita opcional)
  Future<String?> enviarMensaje(
    String receptorId,
    String texto, {
    String? respondeA,
    String? respondeTexto,
    String? respondeEjercicio,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';
    if (texto.trim().isEmpty) return 'El mensaje está vacío';
    try {
      await _sb.from('mensajes').insert({
        'emisor_id': user.id,
        'receptor_id': receptorId,
        'texto': texto.trim(),
        if (respondeA != null) 'responde_a': respondeA,
        if (respondeTexto != null) 'responde_texto': respondeTexto,
        if (respondeEjercicio != null) 'responde_ejercicio': respondeEjercicio,
      });
      return null;
    } catch (_) {
      // Si falla por la política de bloqueo, avisamos claro
      return 'No se pudo enviar (puede que estés bloqueado)';
    }
  }

  // Enviar un mensaje CON un ejercicio adjunto (tarjeta tocable)
  Future<String?> enviarMensajeConEjercicio({
    required String receptorId,
    required String texto,
    required String sesionId,
    required String ejercicio,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'No hay sesión';
    try {
      await _sb.from('mensajes').insert({
        'emisor_id': user.id,
        'receptor_id': receptorId,
        'texto': texto.trim(),
        'sesion_id': sesionId,
        'sesion_ejercicio': ejercicio,
      });
      return null;
    } catch (_) {
      return 'No se pudo enviar (puede que estés bloqueado)';
    }
  }

  // Obtener UNA sesión por su ID (para abrirla desde el chat)
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

  // Ver la conversación con otra persona
  Future<List<Map<String, dynamic>>> conversacionCon(String otroId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];
    try {
      final data = await _sb
          .from('mensajes')
          .select()
          .or('and(emisor_id.eq.${user.id},receptor_id.eq.$otroId),'
              'and(emisor_id.eq.$otroId,receptor_id.eq.${user.id})')
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // Marcar como leídos los mensajes que ME envió la otra persona
  Future<void> marcarLeidos(String otroId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      await _sb
          .from('mensajes')
          .update({'leido': true})
          .eq('emisor_id', otroId)
          .eq('receptor_id', user.id)
          .eq('leido', false);
    } catch (_) {}
  }
}