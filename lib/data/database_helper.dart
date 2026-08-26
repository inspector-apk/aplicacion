import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/solicitud.dart';
import '../models/usuario.dart';

/// Acceso centralizado a la base de datos local SQLite.
/// Toda la información del usuario permanece únicamente en el dispositivo.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _dbName = 'inspector.db';
  static const int _dbVersion = 4;
  static const String tableUsuarios = 'usuarios';
  static const String tableSolicitudes = 'solicitudes';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableUsuarios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nombre TEXT NOT NULL,
            edad INTEGER NOT NULL,
            correo TEXT NOT NULL UNIQUE,
            contrasena TEXT NOT NULL,
            salt TEXT NOT NULL,
            alias TEXT NOT NULL UNIQUE,
            rol TEXT,
            fecha_registro TEXT NOT NULL,
            acepto_politicas INTEGER NOT NULL DEFAULT 0,
            declara_mayor_edad INTEGER NOT NULL DEFAULT 0,
            totp_secret TEXT,
            totp_habilitado INTEGER NOT NULL DEFAULT 0,
            ocupacion TEXT,
            localidad_trabajo TEXT
          )
        ''');
        await db.execute(_createSolicitudesSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(_createSolicitudesSql);
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE $tableUsuarios ADD COLUMN totp_secret TEXT');
          await db.execute(
              'ALTER TABLE $tableUsuarios ADD COLUMN totp_habilitado INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 4) {
          await db
              .execute('ALTER TABLE $tableUsuarios ADD COLUMN ocupacion TEXT');
          await db.execute(
              'ALTER TABLE $tableUsuarios ADD COLUMN localidad_trabajo TEXT');
        }
      },
    );
  }

  static const String _createSolicitudesSql = '''
    CREATE TABLE $tableSolicitudes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cliente_id INTEGER NOT NULL,
      colaborador_id INTEGER,
      tipo TEXT NOT NULL,
      descripcion TEXT NOT NULL,
      localidad TEXT NOT NULL,
      latitud REAL NOT NULL,
      longitud REAL NOT NULL,
      estado TEXT NOT NULL,
      fecha_creacion TEXT NOT NULL,
      fecha_actualizacion TEXT NOT NULL,
      FOREIGN KEY (cliente_id) REFERENCES $tableUsuarios (id),
      FOREIGN KEY (colaborador_id) REFERENCES $tableUsuarios (id)
    )
  ''';

  Future<int> insertUsuario(Usuario usuario) async {
    final db = await database;
    return db.insert(
      tableUsuarios,
      usuario.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<Usuario?> getUsuarioPorCorreo(String correo) async {
    final db = await database;
    final rows = await db.query(
      tableUsuarios,
      where: 'LOWER(correo) = ?',
      whereArgs: [correo.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Usuario.fromMap(rows.first);
  }

  Future<Usuario?> getUsuarioPorId(int id) async {
    final db = await database;
    final rows = await db.query(
      tableUsuarios,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Usuario.fromMap(rows.first);
  }

  /// Todos los usuarios registrados, para el panel de administrador.
  Future<List<Usuario>> getTodosLosUsuarios() async {
    final db = await database;
    final rows = await db.query(tableUsuarios, orderBy: 'fecha_registro DESC');
    return rows.map(Usuario.fromMap).toList();
  }

  /// Búsqueda usada por el flujo de recuperación local: por alias o nombre.
  Future<Usuario?> buscarPorAliasONombre(String textoBusqueda) async {
    final db = await database;
    final texto = textoBusqueda.trim().toLowerCase();
    final rows = await db.query(
      tableUsuarios,
      where: 'LOWER(alias) = ? OR LOWER(nombre) = ?',
      whereArgs: [texto, texto],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Usuario.fromMap(rows.first);
  }

  Future<bool> existeCorreo(String correo) async {
    final usuario = await getUsuarioPorCorreo(correo);
    return usuario != null;
  }

  Future<bool> existeAlias(String alias) async {
    final db = await database;
    final rows = await db.query(
      tableUsuarios,
      where: 'LOWER(alias) = ?',
      whereArgs: [alias.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> actualizarRol(int id, RolUsuario rol) async {
    final db = await database;
    await db.update(
      tableUsuarios,
      {'rol': rol.valor},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> actualizarContrasena(
    int id, {
    required String nuevoHash,
    required String nuevoSalt,
  }) async {
    final db = await database;
    await db.update(
      tableUsuarios,
      {'contrasena': nuevoHash, 'salt': nuevoSalt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina por completo los datos del usuario (derecho de eliminación
  /// mencionado en la política de tratamiento de datos).
  Future<void> eliminarUsuario(int id) async {
    final db = await database;
    await db.delete(tableUsuarios, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> activarTotp(int id, String secreto) async {
    final db = await database;
    await db.update(
      tableUsuarios,
      {'totp_secret': secreto, 'totp_habilitado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> desactivarTotp(int id) async {
    final db = await database;
    await db.update(
      tableUsuarios,
      {'totp_secret': null, 'totp_habilitado': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> actualizarPerfilColaborador(
    int id, {
    required String? ocupacion,
    required String? localidadTrabajo,
  }) async {
    final db = await database;
    await db.update(
      tableUsuarios,
      {'ocupacion': ocupacion, 'localidad_trabajo': localidadTrabajo},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertSolicitud(Solicitud solicitud) async {
    final db = await database;
    return db.insert(
      tableSolicitudes,
      solicitud.toMap()..remove('id'),
    );
  }

  /// Elimina una solicitud por completo, usado desde el panel de admin.
  Future<void> eliminarSolicitud(int id) async {
    final db = await database;
    await db.delete(tableSolicitudes, where: 'id = ?', whereArgs: [id]);
  }

  /// Solicitud activa (pendiente o aceptada) de un cliente, si tiene una.
  Future<Solicitud?> getSolicitudActivaCliente(int clienteId) async {
    final db = await database;
    final rows = await db.query(
      tableSolicitudes,
      where: 'cliente_id = ? AND estado IN (?, ?)',
      whereArgs: [
        clienteId,
        EstadoSolicitud.pendiente.valor,
        EstadoSolicitud.aceptada.valor,
      ],
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Solicitud.fromMap(rows.first);
  }

  /// Todas las solicitudes, para el panel de administrador.
  Future<List<Solicitud>> getTodasLasSolicitudes() async {
    final db = await database;
    final rows =
        await db.query(tableSolicitudes, orderBy: 'fecha_creacion DESC');
    return rows.map(Solicitud.fromMap).toList();
  }

  Future<List<Solicitud>> getSolicitudesPendientes() async {
    final db = await database;
    final rows = await db.query(
      tableSolicitudes,
      where: 'estado = ?',
      whereArgs: [EstadoSolicitud.pendiente.valor],
      orderBy: 'fecha_creacion DESC',
    );
    return rows.map(Solicitud.fromMap).toList();
  }

  Future<List<Solicitud>> getSolicitudesAceptadasPorColaborador(
    int colaboradorId,
  ) async {
    final db = await database;
    final rows = await db.query(
      tableSolicitudes,
      where: 'colaborador_id = ? AND estado = ?',
      whereArgs: [colaboradorId, EstadoSolicitud.aceptada.valor],
      orderBy: 'fecha_creacion DESC',
    );
    return rows.map(Solicitud.fromMap).toList();
  }

  Future<void> actualizarEstadoSolicitud(
    int id, {
    required EstadoSolicitud estado,
    int? colaboradorId,
  }) async {
    final db = await database;
    final valores = <String, Object?>{
      'estado': estado.valor,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    };
    if (colaboradorId != null) {
      valores['colaborador_id'] = colaboradorId;
    }
    await db.update(tableSolicitudes, valores, where: 'id = ?', whereArgs: [id]);
  }
}
