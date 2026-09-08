import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';

/// Consultas y gestión para el panel de administrador — usuarios y
/// solicitudes viven en el mismo backend compartido (ver `backend/`).
class AdminService {
  AdminService._();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Uri _uri(String path) => Uri.parse('${BackendConfig.baseUrl}$path');

  static Future<List<Usuario>> todosLosUsuarios() async {
    final resp = await http
        .get(_uri('/api/usuarios'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
    if (cuerpo['ok'] != true) return [];
    return (cuerpo['usuarios'] as List)
        .map((u) => Usuario.fromMap(u as Map<String, dynamic>))
        .toList();
  }

  static Future<void> eliminarUsuario(int id) async {
    await http
        .delete(_uri('/api/usuarios/$id'), headers: _headers)
        .timeout(const Duration(seconds: 15));
  }

  /// Cambia el rol de un usuario (herramienta de soporte: ej. alguien
  /// se registró con el rol equivocado y no puede cambiarlo él mismo).
  static Future<void> cambiarRol(int id, RolUsuario rol) async {
    await http
        .patch(
          _uri('/api/usuarios/$id/rol'),
          headers: _headers,
          body: jsonEncode({'rol': rol.valor}),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// Desactiva el 2FA de una cuenta (herramienta de soporte: para
  /// cuando alguien perdió su app autenticadora Y su correo no
  /// funciona, así que no puede usar la recuperación normal).
  static Future<void> desactivarDosFactor(int id) async {
    await http
        .patch(_uri('/api/usuarios/$id/2fa'), headers: _headers, body: jsonEncode({}))
        .timeout(const Duration(seconds: 15));
  }

  /// Quita antes de tiempo el bloqueo de 5 minutos que se aplica cuando
  /// un colaborador cancela una solicitud ya aceptada.
  static Future<void> quitarBloqueo(int id) async {
    await http
        .patch(
          _uri('/api/usuarios/$id/bloqueo'),
          headers: _headers,
          body: jsonEncode({'bloquear': false}),
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<List<Solicitud>> todasLasSolicitudes() async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/api/solicitudes/todas');
    final respuesta =
        await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    if (cuerpo['ok'] != true) return [];
    return (cuerpo['solicitudes'] as List)
        .map((s) => Solicitud.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  static Future<void> eliminarSolicitud(int id) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/api/solicitudes/$id');
    await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 15));
  }
}
