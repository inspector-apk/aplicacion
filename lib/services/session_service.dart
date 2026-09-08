import '../models/usuario.dart';

/// Mantiene en memoria al usuario con sesión activa mientras la app
/// está abierta. No hay tokens de sesión: la app vuelve a pedir correo
/// y contraseña cada vez que se abre (se valida contra el backend en
/// ese momento) — este objeto solo evita tener que recargarlo en cada
/// pantalla mientras la app sigue abierta.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  Usuario? _usuarioActual;

  Usuario? get usuarioActual => _usuarioActual;

  void iniciarSesion(Usuario usuario) {
    _usuarioActual = usuario;
  }

  void cerrarSesion() {
    _usuarioActual = null;
  }
}
