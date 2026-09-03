import '../data/database_helper.dart';
import '../models/usuario.dart';
import 'alias_service.dart';
import 'password_service.dart';

class AuthException implements Exception {
  final String mensaje;
  AuthException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Orquesta registro, login y recuperación de contraseña, siempre
/// contra la base de datos local (no hay backend ni red).
class AuthService {
  AuthService._();

  static final DatabaseHelper _db = DatabaseHelper.instance;

  static const String correoAdmin = 'admin@inspector.com';
  static const String _contrasenaAdminPorDefecto = '4321';

  /// Crea la cuenta de administrador precargada la primera vez que la
  /// app arranca, si todavía no existe. Se llama desde `main()`.
  static Future<void> asegurarCuentaAdmin() async {
    if (await _db.existeCorreo(correoAdmin)) return;

    final salt = PasswordService.generarSalt();
    final hash = PasswordService.hashear(_contrasenaAdminPorDefecto, salt);
    final alias = await AliasService.generarAliasUnico();

    final admin = Usuario(
      nombre: 'Administrador',
      edad: 99,
      correo: correoAdmin,
      contrasenaHash: hash,
      salt: salt,
      alias: alias,
      rol: RolUsuario.administrador,
      fechaRegistro: DateTime.now().toIso8601String(),
      aceptoPoliticas: true,
      declaraMayorEdad: true,
    );
    await _db.insertUsuario(admin);
  }

  /// Lanza [AuthException] si el correo ya está registrado. Se usa antes
  /// de enviar el código de verificación, para no gastar un envío de
  /// correo en una cuenta que de todos modos no se podría crear.
  static Future<void> verificarCorreoDisponible(String correo) async {
    if (await _db.existeCorreo(correo.trim().toLowerCase())) {
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
    final correoNormalizado = correo.trim().toLowerCase();

    if (await _db.existeCorreo(correoNormalizado)) {
      throw AuthException('Ya existe una cuenta registrada con ese correo.');
    }

    final alias = await AliasService.generarAliasUnico();
    final salt = PasswordService.generarSalt();
    final hash = PasswordService.hashear(contrasena, salt);

    final nuevoUsuario = Usuario(
      nombre: nombre.trim(),
      edad: edad,
      correo: correoNormalizado,
      contrasenaHash: hash,
      salt: salt,
      alias: alias,
      rol: null,
      fechaRegistro: DateTime.now().toIso8601String(),
      aceptoPoliticas: aceptoPoliticas,
      declaraMayorEdad: declaraMayorEdad,
    );

    final id = await _db.insertUsuario(nuevoUsuario);
    return nuevoUsuario.copyWith(id: id);
  }

  static Future<Usuario> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final usuario = await _db.getUsuarioPorCorreo(correo);
    if (usuario == null) {
      throw AuthException('No existe una cuenta con ese correo.');
    }

    final esValida = PasswordService.verificar(
      contrasena,
      usuario.salt,
      usuario.contrasenaHash,
    );
    if (!esValida) {
      throw AuthException('Contraseña incorrecta.');
    }

    return usuario;
  }

  static Future<Usuario> buscarParaRecuperacion(String aliasONombre) async {
    final usuario = await _db.buscarPorAliasONombre(aliasONombre);
    if (usuario == null) {
      throw AuthException('No se encontró ninguna cuenta con ese alias o nombre.');
    }
    return usuario;
  }

  static Future<void> restablecerContrasena({
    required int usuarioId,
    required String nuevaContrasena,
  }) async {
    final nuevoSalt = PasswordService.generarSalt();
    final nuevoHash = PasswordService.hashear(nuevaContrasena, nuevoSalt);
    await _db.actualizarContrasena(
      usuarioId,
      nuevoHash: nuevoHash,
      nuevoSalt: nuevoSalt,
    );
  }

  static Future<Usuario> seleccionarRol({
    required int usuarioId,
    required RolUsuario rol,
  }) async {
    await _db.actualizarRol(usuarioId, rol);
    final actualizado = await _db.getUsuarioPorId(usuarioId);
    return actualizado!;
  }

  static Future<Usuario> activarDobleFactor({
    required int usuarioId,
    required String secreto,
  }) async {
    await _db.activarTotp(usuarioId, secreto);
    final actualizado = await _db.getUsuarioPorId(usuarioId);
    return actualizado!;
  }

  static Future<Usuario> desactivarDobleFactor(int usuarioId) async {
    await _db.desactivarTotp(usuarioId);
    final actualizado = await _db.getUsuarioPorId(usuarioId);
    return actualizado!;
  }

  static Future<Usuario> actualizarPerfilColaborador({
    required int usuarioId,
    String? ocupacion,
    String? localidadTrabajo,
  }) async {
    await _db.actualizarPerfilColaborador(
      usuarioId,
      ocupacion: ocupacion,
      localidadTrabajo: localidadTrabajo,
    );
    final actualizado = await _db.getUsuarioPorId(usuarioId);
    return actualizado!;
  }

  static Future<Usuario> actualizarCuentaBancaria({
    required int usuarioId,
    String? banco,
    String? numeroCuenta,
  }) async {
    await _db.actualizarCuentaBancaria(
      usuarioId,
      banco: banco,
      numeroCuenta: numeroCuenta,
    );
    final actualizado = await _db.getUsuarioPorId(usuarioId);
    return actualizado!;
  }
}
