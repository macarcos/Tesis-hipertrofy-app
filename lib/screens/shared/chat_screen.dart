// ============================================================
// lib/screens/shared/chat_screen.dart
// Chat entre usuario y entrenador (sirve para ambos lados)
// Permite adjuntar/compartir un ejercicio como tarjeta tocable
// y RESPONDER/CITAR un mensaje (deslizar o mantener presionado).
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/entrenador_service.dart';
import '../../services/fecha_helper.dart';
import 'detalle_sesion_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class ChatScreen extends StatefulWidget {
  final String otroId;       // con quién chateo
  final String otroNombre;   // su nombre
  // Si se abre para compartir un ejercicio, llegan estos datos:
  final String? sesionIdAdjunta;
  final String? ejercicioAdjunto;

  const ChatScreen({
    super.key,
    required this.otroId,
    required this.otroNombre,
    this.sesionIdAdjunta,
    this.ejercicioAdjunto,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _servicio = EntrenadorService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _miId = Supabase.instance.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _mensajes = [];
  bool _cargando = true;
  bool _adjuntando = false;

  // Mensaje que estoy respondiendo (null = no estoy respondiendo)
  Map<String, dynamic>? _respondiendo;

  // Para resaltar un mensaje cuando salto a él desde una cita
  String? _resaltadoId;

  // Ir al mensaje original al tocar una cita
  void _irAlMensaje(String? mensajeId) {
    if (mensajeId == null) return;
    final indice = _mensajes.indexWhere((m) => m['id'] == mensajeId);
    if (indice == -1) return; // no está en la lista cargada

    // Estimar la posición y hacer scroll aproximado
    final posicion = (indice / _mensajes.length) * _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      posicion,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    // Resaltar el mensaje un momento
    setState(() => _resaltadoId = mensajeId);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _resaltadoId = null);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.sesionIdAdjunta != null) {
      _adjuntando = true;
    }
    _cargar();
  }

  Future<void> _cargar() async {
    await _servicio.marcarLeidos(widget.otroId);
    final msgs = await _servicio.conversacionCon(widget.otroId);
    if (mounted) {
      setState(() { _mensajes = msgs; _cargando = false; });
      _bajar();
    }
  }

  void _bajar() {
    // Reintenta varias veces porque la lista tarda en dibujarse
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bajarConReintento(0);
    });
  }

  void _bajarConReintento(int intento) {
    if (!_scroll.hasClients) {
      if (intento < 5) {
        Future.delayed(const Duration(milliseconds: 100),
            () => _bajarConReintento(intento + 1));
      }
      return;
    }
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    // Reintentar un par de veces más por si crecieron las burbujas
    if (intento < 3) {
      Future.delayed(const Duration(milliseconds: 150),
          () => _bajarConReintento(intento + 1));
    }
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty && !_adjuntando) return;
    _ctrl.clear();

    // Datos de la cita (si estoy respondiendo a un mensaje)
    final respondeA = _respondiendo?['id'] as String?;
    final respondeTexto = _respondiendo == null
        ? null
        : ((_respondiendo!['texto'] ?? '').toString().isNotEmpty
            ? _respondiendo!['texto'].toString()
            : null);
    final respondeEjercicio = _respondiendo?['sesion_ejercicio'] as String?;

    if (_adjuntando && widget.sesionIdAdjunta != null) {
      await _servicio.enviarMensajeConEjercicio(
        receptorId: widget.otroId,
        texto: texto.isEmpty ? 'Mira este ejercicio' : texto,
        sesionId: widget.sesionIdAdjunta!,
        ejercicio: widget.ejercicioAdjunto ?? 'Ejercicio',
      );
      setState(() => _adjuntando = false);
    } else {
      await _servicio.enviarMensaje(
        widget.otroId,
        texto,
        respondeA: respondeA,
        respondeTexto: respondeTexto,
        respondeEjercicio: respondeEjercicio,
      );
    }
    setState(() => _respondiendo = null);
    await _cargar();
  }

  Future<void> _abrirEjercicio(String sesionId) async {
    final sesion = await _servicio.sesionPorId(sesionId);
    if (sesion != null && mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => DetalleSesionScreen(sesion: sesion)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el ejercicio')));
    }
  }

  // Activa el modo "respondiendo a este mensaje"
  void _responderA(Map<String, dynamic> m) {
    setState(() => _respondiendo = m);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: _gris,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.otroNombre, style: const TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: _amarillo))
                : _mensajes.isEmpty
                    ? const Center(
                        child: Text('No hay mensajes aún.\n¡Escribe el primero!',
                            style: TextStyle(color: Colors.white38),
                            textAlign: TextAlign.center))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _mensajes.length,
                        itemBuilder: (context, i) => _burbujaDeslizable(_mensajes[i]),
                      ),
          ),
          if (_adjuntando) _avisoAdjunto(),
          if (_respondiendo != null) _avisoRespondiendo(),
          _barraEnviar(),
        ],
      ),
    );
  }

  // Envuelve la burbuja para poder deslizarla y responder
  Widget _burbujaDeslizable(Map<String, dynamic> m) {
    return Dismissible(
      key: ValueKey(m['id']),
      // Deslizar hacia la derecha activa responder, pero NO borra el mensaje
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        _responderA(m);
        return false; // no lo elimina, solo activa responder
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.reply, color: _amarillo, size: 26),
      ),
      child: GestureDetector(
        onLongPress: () => _menuMensaje(m), // mantener presionado = menú
        child: _burbuja(m),
      ),
    );
  }

  // Menú al mantener presionado
  void _menuMensaje(Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _gris,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: _amarillo),
              title: const Text('Responder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _responderA(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _avisoAdjunto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _amarillo.withOpacity(0.12),
      child: Row(
        children: [
          const Icon(Icons.attach_file, color: _amarillo, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Adjuntando: ${widget.ejercicioAdjunto ?? "Ejercicio"}',
                style: const TextStyle(color: _amarillo, fontSize: 13)),
          ),
          GestureDetector(
            onTap: () => setState(() => _adjuntando = false),
            child: const Icon(Icons.close, color: Colors.white54, size: 18),
          ),
        ],
      ),
    );
  }

  // Aviso arriba del input cuando estás respondiendo a un mensaje
  Widget _avisoRespondiendo() {
    final m = _respondiendo!;
    final tieneEjercicio = m['sesion_ejercicio'] != null;
    final textoCita = tieneEjercicio
        ? '📎 ${m['sesion_ejercicio']}'
        : (m['texto'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _gris,
      child: Row(
        children: [
          Container(width: 3, height: 36, color: _amarillo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Respondiendo a',
                    style: TextStyle(color: _amarillo, fontSize: 12, fontWeight: FontWeight.bold)),
                Text(
                  textoCita,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _respondiendo = null),
            child: const Icon(Icons.close, color: Colors.white54, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _burbuja(Map<String, dynamic> m) {
    final esMio = m['emisor_id'] == _miId;
    final tieneEjercicio = m['sesion_id'] != null;
    final tieneCita = (m['responde_texto'] != null &&
            m['responde_texto'].toString().isNotEmpty) ||
        (m['responde_ejercicio'] != null &&
            m['responde_ejercicio'].toString().isNotEmpty);
    final estaResaltado = _resaltadoId != null && m['id'] == _resaltadoId;

    return Align(
      alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: esMio ? _amarillo : _gris,
          borderRadius: BorderRadius.circular(14),
          border: estaResaltado
              ? Border.all(color: Colors.white, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Si este mensaje responde a otro, mostrar la cita arriba (tocable)
            if (tieneCita)
              GestureDetector(
                onTap: () => _irAlMensaje(m['responde_a'] as String?),
                child: _citaDentro(m, esMio),
              ),
            // Si el mensaje lleva un ejercicio, mostrar la tarjeta tocable
            if (tieneEjercicio) ...[
              GestureDetector(
                onTap: () => _abrirEjercicio(m['sesion_id']),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: esMio ? Colors.black.withOpacity(0.12) : _negro,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: esMio ? Colors.black26 : _amarillo.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: esMio ? Colors.black12 : _amarillo.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.fitness_center,
                            color: esMio ? Colors.black : _amarillo, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['sesion_ejercicio'] ?? 'Ejercicio',
                                style: TextStyle(
                                    color: esMio ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            Text('Toca para ver el ejercicio',
                                style: TextStyle(
                                    color: esMio ? Colors.black54 : Colors.white54,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.play_circle_fill,
                          color: esMio ? Colors.black : _amarillo, size: 24),
                    ],
                  ),
                ),
              ),
            ],
            // El texto del mensaje
            if ((m['texto'] ?? '').toString().isNotEmpty)
              Text(m['texto'],
                  style: TextStyle(color: esMio ? Colors.black : Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FechaHelper.formatear(m['created_at']),
                    style: TextStyle(
                        color: esMio ? Colors.black54 : Colors.white38, fontSize: 10)),
                if (esMio) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all,
                    size: 14,
                    color: m['leido'] == true ? const Color(0xFF34B7F1) : Colors.black38,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // La cita que se muestra DENTRO de la burbuja (el mensaje al que responde)
  Widget _citaDentro(Map<String, dynamic> m, bool esMio) {
    final ejercicio = m['responde_ejercicio'];
    final texto = (ejercicio != null && ejercicio.toString().isNotEmpty)
        ? '📎 $ejercicio'
        : (m['responde_texto'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: esMio ? Colors.black.withOpacity(0.10) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: esMio ? Colors.black54 : _amarillo,
            width: 3,
          ),
        ),
      ),
      child: Text(
        texto,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: esMio ? Colors.black87 : Colors.white60,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _barraEnviar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: _gris,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: Colors.white),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _adjuntando
                      ? 'Escribe qué corregir...'
                      : 'Escribe un mensaje...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: _negro,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _enviar,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: _amarillo, shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.black, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}