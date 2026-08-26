const path = require('path');
const Database = require('better-sqlite3');

const db = new Database(path.join(__dirname, 'solicitudes.db'));
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS solicitudes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_alias TEXT NOT NULL,
    colaborador_alias TEXT,
    tipo TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    localidad TEXT NOT NULL,
    latitud REAL NOT NULL,
    longitud REAL NOT NULL,
    estado TEXT NOT NULL,
    fecha_creacion TEXT NOT NULL,
    fecha_actualizacion TEXT NOT NULL
  )
`);

function ahora() {
  return new Date().toISOString();
}

function crearSolicitud({ clienteAlias, tipo, descripcion, localidad, latitud, longitud }) {
  const fecha = ahora();
  const info = db
    .prepare(`
      INSERT INTO solicitudes
        (cliente_alias, tipo, descripcion, localidad, latitud, longitud, estado, fecha_creacion, fecha_actualizacion)
      VALUES (?, ?, ?, ?, ?, ?, 'pendiente', ?, ?)
    `)
    .run(clienteAlias, tipo, descripcion, localidad, latitud, longitud, fecha, fecha);
  return obtenerPorId(info.lastInsertRowid);
}

function obtenerPorId(id) {
  return db.prepare('SELECT * FROM solicitudes WHERE id = ?').get(id) || null;
}

function solicitudesPendientes() {
  return db
    .prepare("SELECT * FROM solicitudes WHERE estado = 'pendiente' ORDER BY fecha_creacion DESC")
    .all();
}

function solicitudActivaDeCliente(clienteAlias) {
  return (
    db
      .prepare(`
        SELECT * FROM solicitudes
        WHERE cliente_alias = ? AND estado IN ('pendiente', 'aceptada')
        ORDER BY fecha_creacion DESC
        LIMIT 1
      `)
      .get(clienteAlias) || null
  );
}

function solicitudesEnCursoDeColaborador(colaboradorAlias) {
  return db
    .prepare(`
      SELECT * FROM solicitudes
      WHERE colaborador_alias = ? AND estado = 'aceptada'
      ORDER BY fecha_creacion DESC
    `)
    .all(colaboradorAlias);
}

/**
 * "El primero que acepta se la gana": UPDATE atómico que solo tiene
 * efecto si la solicitud sigue en estado 'pendiente'. Si otro
 * colaborador ya la aceptó, `changes` será 0 y devolvemos null.
 */
function aceptarSolicitud(id, colaboradorAlias) {
  const info = db
    .prepare(`
      UPDATE solicitudes
      SET estado = 'aceptada', colaborador_alias = ?, fecha_actualizacion = ?
      WHERE id = ? AND estado = 'pendiente'
    `)
    .run(colaboradorAlias, ahora(), id);
  if (info.changes === 0) return null;
  return obtenerPorId(id);
}

function completarSolicitud(id, colaboradorAlias) {
  const info = db
    .prepare(`
      UPDATE solicitudes
      SET estado = 'completada', fecha_actualizacion = ?
      WHERE id = ? AND colaborador_alias = ? AND estado = 'aceptada'
    `)
    .run(ahora(), id, colaboradorAlias);
  if (info.changes === 0) return null;
  return obtenerPorId(id);
}

function cancelarSolicitud(id, clienteAlias) {
  const info = db
    .prepare(`
      UPDATE solicitudes
      SET estado = 'cancelada', fecha_actualizacion = ?
      WHERE id = ? AND cliente_alias = ? AND estado = 'pendiente'
    `)
    .run(ahora(), id, clienteAlias);
  if (info.changes === 0) return null;
  return obtenerPorId(id);
}

function todasLasSolicitudes() {
  return db.prepare('SELECT * FROM solicitudes ORDER BY fecha_creacion DESC').all();
}

function eliminarSolicitud(id) {
  db.prepare('DELETE FROM solicitudes WHERE id = ?').run(id);
}

module.exports = {
  crearSolicitud,
  obtenerPorId,
  solicitudesPendientes,
  solicitudActivaDeCliente,
  solicitudesEnCursoDeColaborador,
  aceptarSolicitud,
  completarSolicitud,
  cancelarSolicitud,
  todasLasSolicitudes,
  eliminarSolicitud,
};
