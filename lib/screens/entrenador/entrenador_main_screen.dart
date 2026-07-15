// ============================================================
// lib/screens/entrenador/entrenador_main_screen.dart
// Contenedor del ENTRENADOR con barra inferior fija:
// Inicio / Usuarios / Perfil
// Recarga TODAS las pestañas cuando algo cambia (bloquear/eliminar),
// para que ningún número quede viejo en ninguna pestaña.
// ============================================================
import 'package:flutter/material.dart';
import 'entrenador_inicio_screen.dart';
import 'entrenador_usuarios_screen.dart';
import 'entrenador_perfil_screen.dart';

const _amarillo = Color(0xFFFFD600);
const _gris = Color(0xFF1A1A1A);

class EntrenadorMainScreen extends StatefulWidget {
  const EntrenadorMainScreen({super.key});

  @override
  State<EntrenadorMainScreen> createState() => _EntrenadorMainScreenState();
}

class _EntrenadorMainScreenState extends State<EntrenadorMainScreen> {
  int _indice = 0;

  // Keys para poder pedirle a cada pestaña que recargue
  final _inicioKey = GlobalKey<EntrenadorInicioScreenState>();
  final _usuariosKey = GlobalKey<EntrenadorUsuariosScreenState>();
  final _perfilKey = GlobalKey<EntrenadorPerfilScreenState>();

  late final List<Widget> _pantallas = [
    EntrenadorInicioScreen(key: _inicioKey),
    // A la lista de usuarios le pasamos un aviso: "cuando cambie algo,
    // recarga TODAS las pestañas".
    EntrenadorUsuariosScreen(
      key: _usuariosKey,
      onCambio: _recargarTodo,
    ),
    EntrenadorPerfilScreen(key: _perfilKey),
  ];

  // Recarga las 3 pestañas a la vez
  void _recargarTodo() {
    _inicioKey.currentState?.recargar();
    _usuariosKey.currentState?.recargar();
    _perfilKey.currentState?.recargar();
  }

  void _onTap(int i) {
    setState(() => _indice = i);
    // Recargar SIEMPRE al tocar, aunque ya estés en esa pestaña.
    if (i == 0) _inicioKey.currentState?.recargar();
    if (i == 1) _usuariosKey.currentState?.recargar();
    if (i == 2) _perfilKey.currentState?.recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: IndexedStack(index: _indice, children: _pantallas),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _gris,
        selectedItemColor: _amarillo,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        currentIndex: _indice,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Usuarios'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}