// ============================================================
// lib/screens/nueva_password_screen.dart
// Se abre cuando el usuario llega por el ENLACE de recuperación del email.
// Supabase ya validó el token (por eso llegó aquí), así que solo pedimos
// la nueva contraseña y la guardamos. Sin código de 6 dígitos.
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _amarillo = Color(0xFFFFD600);
const _negro = Color(0xFF0A0A0A);
const _gris = Color(0xFF1A1A1A);

class NuevaPasswordScreen extends StatefulWidget {
  const NuevaPasswordScreen({super.key});

  @override
  State<NuevaPasswordScreen> createState() => _NuevaPasswordScreenState();
}

class _NuevaPasswordScreenState extends State<NuevaPasswordScreen> {
  final _sb = Supabase.instance.client;
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (pass.length < 6) {
      _msg('La contraseña debe tener al menos 6 caracteres');
      return;
    }
    if (pass != pass2) {
      _msg('Las contraseñas no coinciden');
      return;
    }

    try {
      setState(() => _cargando = true);
      // El usuario ya está autenticado temporalmente (llegó por el enlace).
      // Solo actualizamos la contraseña.
      await _sb.auth.updateUser(UserAttributes(password: pass));
      // Cerramos sesión para que entre con la nueva contraseña.
      await _sb.auth.signOut();
      if (mounted) {
        _msg('Contraseña actualizada. Ya puedes iniciar sesión.', exito: true);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          // Volver al inicio (login)
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } on AuthException catch (e) {
      _msg('No se pudo cambiar: ${e.message}');
    } catch (_) {
      _msg('No se pudo cambiar la contraseña.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _msg(String m, {bool exito = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: exito ? Colors.green[700] : Colors.red[700]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _negro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Nueva contraseña', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Center(child: Icon(Icons.lock_open, color: _amarillo, size: 64)),
              const SizedBox(height: 24),
              const Text('Crea tu nueva contraseña',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Ingresa una nueva contraseña para tu cuenta.',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 28),

              _label('NUEVA CONTRASEÑA'),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Mínimo 6 caracteres'),
              ),
              const SizedBox(height: 16),

              _label('CONFIRMAR CONTRASEÑA'),
              TextField(
                controller: _pass2Ctrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Repite la contraseña'),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _amarillo,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _cargando ? null : _guardar,
                  child: _cargando
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('Guardar contraseña',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: _gris,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _amarillo, width: 1.5)),
      );
}