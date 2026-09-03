/// Roles disponibles dentro de la app. `administrador` no es
/// seleccionable desde RoleSelectionScreen: solo lo tiene la cuenta
/// admin precargada en la base de datos.
enum RolUsuario { colaborador, cliente, administrador }

extension RolUsuarioX on RolUsuario {
  String get valor => name;

  static RolUsuario? fromValor(String? valor) {
    switch (valor) {
      case 'colaborador':
        return RolUsuario.colaborador;
      case 'cliente':
        return RolUsuario.cliente;
      case 'administrador':
        return RolUsuario.administrador;
      default:
        return null;
    }
  }
}

class Usuario {
  final int? id;
  final String nombre;
  final int edad;
  final String correo;
  final String contrasenaHash;
  final String salt;
  final String alias;
  final RolUsuario? rol;
  final String fechaRegistro;
  final bool aceptoPoliticas;
  final bool declaraMayorEdad;
  final String? totpSecret;
  final bool totpHabilitado;
  final String? ocupacion;
  final String? localidadTrabajo;

  /// Cuenta bancaria FICTICIA del colaborador (no hay pasarela de pagos
  /// real ni transferencias de dinero de verdad) — solo para simular a
  /// dónde "llegaría" el pago al completar una solicitud.
  final String? bancoFicticio;
  final String? numeroCuentaFicticia;

  const Usuario({
    this.id,
    required this.nombre,
    required this.edad,
    required this.correo,
    required this.contrasenaHash,
    required this.salt,
    required this.alias,
    required this.rol,
    required this.fechaRegistro,
    required this.aceptoPoliticas,
    required this.declaraMayorEdad,
    this.totpSecret,
    this.totpHabilitado = false,
    this.ocupacion,
    this.localidadTrabajo,
    this.bancoFicticio,
    this.numeroCuentaFicticia,
  });

  Usuario copyWith({
    int? id,
    RolUsuario? rol,
    String? contrasenaHash,
    String? salt,
    String? totpSecret,
    bool? totpHabilitado,
    String? ocupacion,
    String? localidadTrabajo,
    String? bancoFicticio,
    String? numeroCuentaFicticia,
  }) {
    return Usuario(
      id: id ?? this.id,
      nombre: nombre,
      edad: edad,
      correo: correo,
      contrasenaHash: contrasenaHash ?? this.contrasenaHash,
      salt: salt ?? this.salt,
      alias: alias,
      rol: rol ?? this.rol,
      fechaRegistro: fechaRegistro,
      aceptoPoliticas: aceptoPoliticas,
      declaraMayorEdad: declaraMayorEdad,
      totpSecret: totpSecret ?? this.totpSecret,
      totpHabilitado: totpHabilitado ?? this.totpHabilitado,
      ocupacion: ocupacion ?? this.ocupacion,
      localidadTrabajo: localidadTrabajo ?? this.localidadTrabajo,
      bancoFicticio: bancoFicticio ?? this.bancoFicticio,
      numeroCuentaFicticia: numeroCuentaFicticia ?? this.numeroCuentaFicticia,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'edad': edad,
      'correo': correo,
      'contrasena': contrasenaHash,
      'salt': salt,
      'alias': alias,
      'rol': rol?.valor,
      'fecha_registro': fechaRegistro,
      'acepto_politicas': aceptoPoliticas ? 1 : 0,
      'declara_mayor_edad': declaraMayorEdad ? 1 : 0,
      'totp_secret': totpSecret,
      'totp_habilitado': totpHabilitado ? 1 : 0,
      'ocupacion': ocupacion,
      'localidad_trabajo': localidadTrabajo,
      'banco_ficticio': bancoFicticio,
      'numero_cuenta_ficticia': numeroCuentaFicticia,
    };
  }

  factory Usuario.fromMap(Map<String, Object?> map) {
    return Usuario(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      edad: map['edad'] as int,
      correo: map['correo'] as String,
      contrasenaHash: map['contrasena'] as String,
      salt: map['salt'] as String,
      alias: map['alias'] as String,
      rol: RolUsuarioX.fromValor(map['rol'] as String?),
      fechaRegistro: map['fecha_registro'] as String,
      aceptoPoliticas: (map['acepto_politicas'] as int) == 1,
      declaraMayorEdad: (map['declara_mayor_edad'] as int) == 1,
      totpSecret: map['totp_secret'] as String?,
      totpHabilitado: ((map['totp_habilitado'] as int?) ?? 0) == 1,
      ocupacion: map['ocupacion'] as String?,
      localidadTrabajo: map['localidad_trabajo'] as String?,
      bancoFicticio: map['banco_ficticio'] as String?,
      numeroCuentaFicticia: map['numero_cuenta_ficticia'] as String?,
    );
  }
}
