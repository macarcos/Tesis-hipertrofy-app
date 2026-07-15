// ============================================================
// lib/screens/widgets/login_form.dart
// Login amarillo/negro con Google y recuperación (sin huella)
// CON validación de correo.
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../recuperar_screen.dart';
import '../../../services/validaciones.dart';

const _amarillo = Color(0xFFFFD600);
const _gris = Color(0xFF1A1A1A);

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _cargando = false;
  bool _verPass = false;

  Future<void> _entrar() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    // Validar correo antes de enviar
    final errEmail = Validaciones.email(email);
    if (errEmail != null) { _msg(errEmail); return; }
    if (pass.isEmpty) {
      _msg('Ingresa tu contraseña');
      return;
    }

    try {
      setState(() => _cargando = true);
      final res = await _supabase.auth.signInWithPassword(email: email, password: pass);

      // Revisar si la cuenta está bloqueada por el admin
      final userId = res.user?.id;
      if (userId != null) {
        final perfil = await _supabase
            .from('perfiles')
            .select('cuenta_bloqueada')
            .eq('id', userId)
            .maybeSingle();
        if (perfil != null && perfil['cuenta_bloqueada'] == true) {
          // Está bloqueado: cerrar sesión y avisar
          await _supabase.auth.signOut();
          if (mounted) {
            _msg('Tu cuenta ha sido bloqueada. Contacta al administrador.');
            setState(() => _cargando = false);
          }
          return;
        }
      }
      // Si no está bloqueado, el AuthGate cambia de pantalla solo.
    } on AuthException catch (e) {
      _msg(_traducir(e.message));
    } catch (_) {
      _msg('No se pudo iniciar sesión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.biosmart://login-callback/',
      );
    } catch (e) {
      _msg('Error con Google: $e');
    }
  }

  void _msg(String m, {bool exito = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: exito ? Colors.green[700] : Colors.red[700]),
      );

  String _traducir(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirma tu correo antes de entrar.';
    }
    return msg;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),

          _label('CORREO ELECTRÓNICO'),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [
              LengthLimitingTextInputFormatter(100),
              // Solo caracteres válidos en un correo (bloquea <>{}#$ etc.)
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9@._%+\-]')),
            ],
            style: const TextStyle(color: Colors.white),
            decoration: _dec('usuario@correo.com'),
          ),
          const SizedBox(height: 16),
          _label('CONTRASEÑA'),
          TextField(
            controller: _passCtrl,
            obscureText: !_verPass,
            inputFormatters: [LengthLimitingTextInputFormatter(72)],
            style: const TextStyle(color: Colors.white),
            decoration: _dec('••••••••').copyWith(
              suffixIcon: IconButton(
                icon: Icon(_verPass ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38),
                onPressed: () => setState(() => _verPass = !_verPass),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RecuperarScreen())),
              child: const Text('¿Olvidaste tu contraseña?',
                  style: TextStyle(color: _amarillo)),
            ),
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _amarillo,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _cargando ? null : _entrar,
              child: _cargando
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('Entrar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 22),

          const Row(children: [
            Expanded(child: Divider(color: Colors.grey)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('O', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: Divider(color: Colors.grey)),
          ]),
          const SizedBox(height: 22),

          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.g_mobiledata, size: 34, color: Colors.white),
              label: const Text('Continuar con Google',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: _signInWithGoogle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: _gris,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _amarillo, width: 1.5)),
      );
}