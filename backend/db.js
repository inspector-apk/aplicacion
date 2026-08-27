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
    fecha_actualizacion TEXT NOT NULL,
    respuesta_texto TEXT,
    respuesta_imagen_base64 TEXT,
    respuesta_fecha TEXT,
    respuesta_vista INTEGER NOT NULL DEFAULT 0
  )
`);

// Columnas "seguras": todo excepto el contenido real de la respuesta
// (respuesta_texto, respuesta_imagen_base64). Se usan en cualquier
// consulta que no sea la de "ver la respuesta una sola vez", para que
// el contenido nunca se filtre por otro camino (ni al colaborador, ni
// al admin, ni al propio cliente antes de "abrirla").
const COLUMNAS_SEGURAS = `
  id, cliente_alias, colaborador_alias, tipo, descripcion, localidad,
  latitud, longitud, estado, fecha_creacion, fecha_actualizacion,
  respuesta_fecha, respuesta_vista
`;

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
  return db.prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes WHERE id = ?`).get(id) || null;
}

function solicitudesPendientes() {
  return db
    .prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes WHERE estado = 'pendiente' ORDER BY fecha_creacion DESC`)
    .all();
}

/**
 * La solicitud "vigente" para un cliente: la que sigue en curso, o una
 * ya completada cuya respuesta todavía no ha visto (para que la app le
 * muestre el botón de "ver respuesta").
 */
function solicitudActivaDeCliente(clienteAlias) {
  return (
    db
      .prepare(`
        SELECT ${COLUMNAS_SEGURAS} FROM solicitudes
        WHERE cliente_alias = ?
          AND (estado IN ('pendiente', 'aceptada') OR (estado = 'completada' AND respuesta_vista = 0))
        ORDER BY fecha_creacion DESC
        LIMIT 1
      `)
      .get(clienteAlias) || null
  );
}

function solicitudesEnCursoDeColaborador(colaboradorAlias) {
  return db
    .prepare(`
      SELECT ${COLUMNAS_SEGURAS} FROM solicitudes
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

/**
 * El colaborador envía su respuesta (texto o imagen en base64) y con
 * eso mismo la solicitud queda completada.
 */
function responderSolicitud(id, colaboradorAlias, { texto, imagenBase64 }) {
  const fecha = ahora();
  const info = db
    .prepare(`
      UPDATE solicitudes
      SET estado = 'completada',
          respuesta_texto = ?,
          respuesta_imagen_base64 = ?,
          respuesta_fecha = ?,
          respuesta_vista = 0,
          fecha_actualizacion = ?
      WHERE id = ? AND colaborador_alias = ? AND estado = 'aceptada'
    `)
    .run(texto || null, imagenBase64 || null, fecha, fecha, id, colaboradorAlias);
  if (info.changes === 0) return null;
  return obtenerPorId(id);
}

/**
 * Entrega el contenido de la respuesta UNA SOLA VEZ: si es válida y
 * todavía no se ha visto, la borra de la base de datos en el mismo
 * paso (no queda guardada en ningún lado después de esto). Llamadas
 * posteriores devuelven null.
 */
function consumirRespuesta(id, clienteAlias) {
  const fila = db
    .prepare('SELECT cliente_alias, tipo, respuesta_texto, respuesta_imagen_base64, respuesta_vista FROM solicitudes WHERE id = ?')
    .get(id);

  if (!fila) return null;
  if (fila.cliente_alias !== clienteAlias) return null;
  if (fila.respuesta_vista === 1) return null;
  if (!fila.respuesta_texto && !fila.respuesta_imagen_base64) return null;

  const contenido = {
    tipo: fila.tipo,
    texto: fila.respuesta_texto,
    imagenBase64: fila.respuesta_imagen_base64,
  };

  db.prepare(`
    UPDATE solicitudes
    SET respuesta_texto = NULL, respuesta_imagen_base64 = NULL, respuesta_vista = 1
    WHERE id = ?
  `).run(id);

  return contenido;
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
  return db.prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes ORDER BY fecha_creacion DESC`).all();
}

/** Historial completo (cualquier estado) de un cliente, sin contenido. */
function historialDeCliente(clienteAlias) {
  return db
    .prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes WHERE cliente_alias = ? ORDER BY fecha_creacion DESC`)
    .all(clienteAlias);
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
  responderSolicitud,
  consumirRespuesta,
  cancelarSolicitud,
  todasLasSolicitudes,
  historialDeCliente,
  eliminarSolicitud,
};
