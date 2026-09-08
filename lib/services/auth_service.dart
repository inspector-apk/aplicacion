import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../models/usuario.dart';
import 'password_service.dart';

class AuthException implements Exception {
  final String mensaje;
  AuthException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Orquesta registro, login y todo lo demás de la cuenta — habla con el
/// backend compartido (ver `backend/usuarios.js`). Las contraseñas se
/// hashean SIEMPRE en el propio celular (SHA-256 + salt) antes de
/// mandarse: el servidor nunca ve una contraseña en texto plano en el
/// registro/login normales, solo guarda y compara el hash.
class AuthService {
  AuthService._();

  static const String correoAdmin = 'admin@inspector.com';
  static const String _contrasenaAdminPorDefecto = '4321';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${BackendConfig.baseUrl}$path')
        .replace(queryParameters: query);
  }

  static Map<String, dynamic> _decodificar(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'error': 'Respuesta inválida del servidor.'};
    }
  }

  static Usuario _usuarioDe(Map<String, dynamic> cuerpo) {
    return Usuario.fromMap(cuerpo['usuario'] as Map<String, dynamic>);
  }

  /// Crea la cuenta de administrador precargada en el servidor, si
  /// todavía no existe. Se llama desde `main()` al abrir la app; si no
  /// hay conexión en ese momento simplemente no hace nada (no es
  /// crítico — se reintenta la próxima vez que la app abra con internet).
  static Future<void> asegurarCuentaAdmin() async {
    try {
      final saltResp = await http
          .get(_uri('/api/usuarios/salt', {'correo': correoAdmin}), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (saltResp.statusCode == 200) return; // ya existe

      final salt = PasswordService.generarSalt();
      final hash = PasswordService.hashear(_contrasenaAdminPorDefecto, salt);
      await http
          .post(
            _uri('/api/usuarios/registro'),
            headers: _headers,
            body: jsonEncode({
              'nombre': 'Administrador',
              'edad': 99,
              'correo': correoAdmin,
              'contrasenaHash': hash,
              'salt': salt,
              'aceptoPoliticas': true,
              'declaraMayorEdad': true,
              'rol': 'administrador',
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Sin conexión al arrancar: no es crítico.
    }
  }

  /// Lanza [AuthException] si el correo ya está registrado. Se usa antes
  /// de enviar el código de verificación, para no gastar un envío de
  /// correo en una cuenta que de todos modos no se podría crear.
  static Future<void> verificarCorreoDisponible(String correo) async {
    final resp = await http
        .get(_uri('/api/usuarios/salt', {'correo': correo.trim().toLowerCase()}),
            headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      throw AuthException('Ya existe una cuenta registrada con ese correo.');
    }
  }

  static Future<Usuario> registrar({
    required String nombre,
    required int edad,
    required String correo,
    required String contrasena,
    required bool aceptoPoliticas,
    required bool declaraMayorEdad,
  }) async {
    final salt = PasswordService.generarSalt();
    final hash = PasswordService.hashear(contrasena, salt);

    final resp = await http
        .post(
          _uri('/api/usuarios/registro'),
          headers: _headers,
          body: jsonEncode({
            'nombre': nombre.trim(),
            'edad': edad,
            'correo': correo.trim().toLowerCase(),
            'contrasenaHash': hash,
            'salt': salt,
            'aceptoPoliticas': aceptoPoliticas,
            'declaraMayorEdad': declaraMayorEdad,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final cuerpo = _decodificar(resp);
    if (cuerpo['ok'] != true) {
      throw AuthException(
          (cuerpo['error'] as String?) ?? 'No se pudo crear la cuenta.');
    }
    return _usuarioDe(cuerpo);
  }

  static Future<Usuario> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final correoNormalizado = correo.trim().toLowerCase();

    final saltResp = await http
        .get(_uri('/api/usuarios/salt', {'correo': correoNormalizado}),
            headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (saltResp.statusCode != 200) {
      throw AuthException('No existe una cuenta con ese correo.');
    }
    final salt = (_decodificar(saltResp)['salt'] as String);
    final hash = PasswordService.hashear(contrasena, salt);

    final loginResp = await http
        .post(
          _uri('/api/usuarios/login'),
          headers: _headers,
          body: jsonEncode({'correo': correoNormalizado, 'contrasenaHash': hash}),
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(loginResp);
    if (cuerpo['ok'] != true) {
      throw AuthException((cuerpo['error'] as String?) ?? 'Contraseña incorrecta.');
    }
    return _usuarioDe(cuerpo);
  }

  /// Busca una cuenta por alias o nombre completo, para la recuperación
  /// de contraseña. Como las cuentas ya no viven solo en un celular,
  /// quien llame a esto debe verificar el correo del resultado (con
  /// `EmailVerificationService`) antes de dejar cambiar la contraseña —
  /// ver `forgot_password_screen.dart`.
  static Future<Usuario> buscarParaRecuperacion(String aliasONombre) async {
    final resp = await http
        .get(_uri('/api/usuarios/buscar-recuperacion', {'texto': aliasONombre.trim()}),
            headers: _headers)
        .timeout(const Duration(seconds: 15));
    final cuerpo = _decodificar(resp);
    if (cuerpo['ok'] != true) {
      throw AuthException((cuerpo['error'] as String?) ??
          'No se encontró ninguna cuenta con ese alias o nombre.');
    }
    final u = cuerpo['usuario'] as Map<String, dynamic>;
    // Respuesta parcial (id, alias, correo) — suficiente para mostrar y
    // para el paso de verificación; no trae el resto de la cuenta.
    return Usuario(
      id: u['id'] as int,
      nombre: '',
      edad: 0,
      correo: u['correo'] as String,
      contrasenaHash: '',
      salt: '',
      alias: u['alias'] as String,
      rol: null,
      fechaRegistro: '',
      aceptoPoliticas: true,
      declaraMayorEdad: true,
    );
  }

  static Future<void> restablecerContrasena({
    required int usuarioId,
    required String nuevaContrasena,
  }) async {
    final nuevoSalt = PasswordService.generarSalt();
    final nuevoHash = PasswordService.hashear(nuevaContrasena, nuevoSalt);
    await http
        .patch(
          _uri('/api/usuarios/$usuarioId/contrasena'),
          headers: _headers,
          body: jsonEncode({'contrasenaHash': nuevoHash, 'salt': nuevoSalt}),
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<Usuario> seleccionarRol({
    required int usuarioId,
    required RolUsuario rol,
  }) async {
    final resp = await http
        .patch(
          _uri('/api/usuarios/$usuarioId/rol'),
          headers: _headers,
          body: jsonEncode({'rol': rol.valor}),
        )
        .timeout(const Duration(seconds: 15));
    return _usuarioDe(_decodificar(resp));
  }

  static Future<Usuario> activarDobleFactor({
    required int usuarioId,
    required String secreto,
  }) async {
    final resp = await http
        .patch(
          _uri('/api/usuarios/$usuarioId/2fa'),
          headers: _headers,
          body: jsonEncode({'secreto': secreto}),
        )
        .timeout(const Duration(seconds: 15));
    return _usuarioDe(_decodificar(resp));
  }

  static Future<Usuario> desactivarDobleFactor(int usuarioId) async {
    final resp = await http
        .patch(
          _uri('/api/usuarios/$usuarioId/2fa'),
          headers: _headers,
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 15));
    return _usuarioDe(_decodificar(resp));
  }

  static Future<Usuario> actualizarPerfilColaborador({
    required int usuarioId,
    String? ocupacion,
    String? localidadTrabajo,
  }) async {
    final resp = await http
        .patch(
          _uri('/api/usuarios/$usuarioId/perfil-colaborador'),
          headers: _headers,
          body: jsonEncode({'ocupacion': ocupacion, 'localidadTrabajo': localidadTrabajo}),
        )
        .timeout(const Duration(seconds: 15));
    return _usuarioDe(_decodificar(resp));
  }

  static Future<Usuario> actualizarCuentaBancaria({
    required int usuarioId,
    String? banco,
    String? numeroCuenta,
  }) async {
    final resp = await http
        .patch(
          _uri('/api/usuarios/$usuarioId/cuenta-bancaria'),
          headers: _headers,
          body: jsonEncode({'banco': banco, 'numeroCuenta': numeroCuenta}),
        )
        .timeout(const Duration(seconds: 15));
    return _usuarioDe(_decodificar(resp));
  }

  /// Bloquea la cuenta del colaborador por 5 minutos: se llama cuando
  /// cancela una solicitud que ya había aceptado.
  static Future<Usuario> bloquearPorCancelacion(int usuarioId) async {
    final resp = await http
        .patch(
          _uri('/api/usuarios/$usuarioId/bloqueo'),
          headers: _headers,
          body: jsonEncode({'bloquear': true}),
        )
        .timeout(const Duration(seconds: 15));
    return _usuarioDe(_decodificar(resp));
  }
}
