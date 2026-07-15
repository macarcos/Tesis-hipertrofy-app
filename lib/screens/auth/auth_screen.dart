// ============================================================
// lib/screens/auth/auth_screen.dart
// Login / Registro con pestañas — amarillo y negro
// Muestra el LOGO (imagen PNG) de BioSmart arriba.
// ============================================================
import 'package:flutter/material.dart';
import 'widgets/login_form.dart';
import 'widgets/signup_form.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const amarillo = Color(0xFFFFD600);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Column(
            children: [
              // ── LOGO (imagen) arriba ──
              const SizedBox(height: 24),
              Image.asset(
                'assets/images/logo.png',
                height: 150,           // ajusta el tamaño aquí si lo quieres más grande/pequeño
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),

              // ── Pestañas ──
              const TabBar(
                indicatorColor: amarillo,
                labelColor: amarillo,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(text: 'Iniciar Sesión'),
                  Tab(text: 'Registrarse'),
                ],
              ),

              // ── Contenido ──
              const Expanded(
                child: TabBarView(
                  children: [
                    LoginForm(),
                    SignUpForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}