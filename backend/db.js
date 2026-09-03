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

// Migraciones aditivas: agregan columnas nuevas a una base de datos que
// ya existía con el esquema anterior. SQLite no soporta "ADD COLUMN IF
// NOT EXISTS", así que se intenta y se ignora el error si ya existe.
function agregarColumnaSiFalta(nombre, definicion) {
  try {
    db.exec(`ALTER TABLE solicitudes ADD COLUMN ${nombre} ${definicion}`);
  } catch (err) {
    if (!/duplicate column/i.test(err.message)) throw err;
  }
}
agregarColumnaSiFalta('categoria', "TEXT NOT NULL DEFAULT 'personal'");
agregarColumnaSiFalta('tipos', "TEXT NOT NULL DEFAULT '[\"texto\"]'");
agregarColumnaSiFalta('valor_total', 'INTEGER NOT NULL DEFAULT 0');
agregarColumnaSiFalta('respuesta_audio_base64', 'TEXT');
agregarColumnaSiFalta('respuesta_video_base64', 'TEXT');
agregarColumnaSiFalta('direccion', "TEXT NOT NULL DEFAULT ''");
agregarColumnaSiFalta('referencia_pago', "TEXT NOT NULL DEFAULT ''");
agregarColumnaSiFalta('metodo_pago', "TEXT NOT NULL DEFAULT ''");

// Columnas "seguras": todo excepto el contenido real de la respuesta
// (respuesta_texto, respuesta_imagen_base64, respuesta_audio_base64,
// respuesta_video_base64). Se usan en cualquier consulta que no sea la
// de "ver la respuesta una sola vez", para que el contenido nunca se
// filtre por otro camino (ni al colaborador, ni al admin, ni al propio
// cliente antes de "abrirla").
const COLUMNAS_SEGURAS = `
  id, cliente_alias, colaborador_alias, tipos, categoria, valor_total,
  referencia_pago, metodo_pago, descripcion, localidad, direccion,
  latitud, longitud, estado, fecha_creacion, fecha_actualizacion,
  respuesta_fecha, respuesta_vista
`;

function ahora() {
  return new Date().toISOString();
}

/** Convierte la columna `tipos` (JSON guardado como texto) en un array real. */
function conTiposParseados(fila) {
  if (!fila) return null;
  let tipos;
  try {
    tipos = JSON.parse(fila.tipos);
  } catch (_) {
    tipos = [fila.tipo || 'texto'];
  }
  return { ...fila, tipos };
}

function crearSolicitud({ clienteAlias, tipos, categoria, valorTotal, referenciaPago, metodoPago, descripcion, localidad, direccion, latitud, longitud }) {
  const fecha = ahora();
  const info = db
    .prepare(`
      INSERT INTO solicitudes
        (cliente_alias, tipo, tipos, categoria, valor_total, referencia_pago, metodo_pago, descripcion, localidad, direccion, latitud, longitud, estado, fecha_creacion, fecha_actualizacion)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pendiente', ?, ?)
    `)
    .run(clienteAlias, tipos[0], JSON.stringify(tipos), categoria, valorTotal, referenciaPago || '', metodoPago || '', descripcion, localidad, direccion || '', latitud, longitud, fecha, fecha);
  return obtenerPorId(info.lastInsertRowid);
}

function obtenerPorId(id) {
  const fila = db.prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes WHERE id = ?`).get(id);
  return conTiposParseados(fila) || null;
}

function solicitudesPendientes() {
  return db
    .prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes WHERE estado = 'pendiente' ORDER BY fecha_creacion DESC`)
    .all()
    .map(conTiposParseados);
}

/**
 * La solicitud "vigente" para un cliente: la que sigue en curso, o una
 * ya completada cuya respuesta todavía no ha visto (para que la app le
 * muestre el botón de "ver respuesta").
 */
function solicitudActivaDeCliente(clienteAlias) {
  const fila = db
    .prepare(`
      SELECT ${COLUMNAS_SEGURAS} FROM solicitudes
      WHERE cliente_alias = ?
        AND (estado IN ('pendiente', 'aceptada') OR (estado = 'completada' AND respuesta_vista = 0))
      ORDER BY fecha_creacion DESC
      LIMIT 1
    `)
    .get(clienteAlias);
  return conTiposParseados(fila) || null;
}

function solicitudesEnCursoDeColaborador(colaboradorAlias) {
  return db
    .prepare(`
      SELECT ${COLUMNAS_SEGURAS} FROM solicitudes
      WHERE colaborador_alias = ? AND estado = 'aceptada'
      ORDER BY fecha_creacion DESC
    `)
    .all(colaboradorAlias)
    .map(conTiposParseados);
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
 * El colaborador envía su respuesta (uno o varios de: texto, imagen,
 * audio, video en base64, según lo que haya pedido la solicitud) y con
 * eso la solicitud queda completada.
 */
function responderSolicitud(id, colaboradorAlias, { texto, imagenBase64, audioBase64, videoBase64 }) {
  const fecha = ahora();
  const info = db
    .prepare(`
      UPDATE solicitudes
      SET estado = 'completada',
          respuesta_texto = ?,
          respuesta_imagen_base64 = ?,
          respuesta_audio_base64 = ?,
          respuesta_video_base64 = ?,
          respuesta_fecha = ?,
          respuesta_vista = 0,
          fecha_actualizacion = ?
      WHERE id = ? AND colaborador_alias = ? AND estado = 'aceptada'
    `)
    .run(texto || null, imagenBase64 || null, audioBase64 || null, videoBase64 || null, fecha, fecha, id, colaboradorAlias);
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
    .prepare('SELECT cliente_alias, respuesta_texto, respuesta_imagen_base64, respuesta_audio_base64, respuesta_video_base64, respuesta_vista FROM solicitudes WHERE id = ?')
    .get(id);

  if (!fila) return null;
  if (fila.cliente_alias !== clienteAlias) return null;
  if (fila.respuesta_vista === 1) return null;
  if (!fila.respuesta_texto && !fila.respuesta_imagen_base64 && !fila.respuesta_audio_base64 && !fila.respuesta_video_base64) {
    return null;
  }

  const contenido = {
    texto: fila.respuesta_texto,
    imagenBase64: fila.respuesta_imagen_base64,
    audioBase64: fila.respuesta_audio_base64,
    videoBase64: fila.respuesta_video_base64,
  };

  db.prepare(`
    UPDATE solicitudes
    SET respuesta_texto = NULL, respuesta_imagen_base64 = NULL, respuesta_audio_base64 = NULL, respuesta_video_base64 = NULL, respuesta_vista = 1
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
  return db
    .prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes ORDER BY fecha_creacion DESC`)
    .all()
    .map(conTiposParseados);
}

/** Historial completo (cualquier estado) de un cliente, sin contenido. */
function historialDeCliente(clienteAlias) {
  return db
    .prepare(`SELECT ${COLUMNAS_SEGURAS} FROM solicitudes WHERE cliente_alias = ? ORDER BY fecha_creacion DESC`)
    .all(clienteAlias)
    .map(conTiposParseados);
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
