import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../data/database_helper.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';

/// Consultas y gestión para el panel de administrador: usuarios (locales)
/// y solicitudes (backend compartido).
class AdminService {
  AdminService._();

  static final DatabaseHelper _db = DatabaseHelper.instance;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Future<List<Usuario>> todosLosUsuarios() {
    return _db.getTodosLosUsuarios();
  }

  static Future<void> eliminarUsuario(int id) {
    return _db.eliminarUsuario(id);
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
