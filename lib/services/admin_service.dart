import '../data/database_helper.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';

/// Consultas y gestión para el panel de administrador: todos los
/// usuarios y todas las solicitudes de la base de datos local.
class AdminService {
  AdminService._();

  static final DatabaseHelper _db = DatabaseHelper.instance;

  static Future<List<Usuario>> todosLosUsuarios() {
    return _db.getTodosLosUsuarios();
  }

  static Future<List<Solicitud>> todasLasSolicitudes() {
    return _db.getTodasLasSolicitudes();
  }

  static Future<void> eliminarUsuario(int id) {
    return _db.eliminarUsuario(id);
  }

  static Future<void> eliminarSolicitud(int id) {
    return _db.eliminarSolicitud(id);
  }
}
