const crypto = require('crypto');
const db = require('./conexion_db');

// Registro local de cada intento de pago PSE, aparte de lo que guarda
// Wompi — así el panel de admin puede ver el historial y la app puede
// consultar el estado sin depender de que el webhook haya llegado.
db.exec(`
  CREATE TABLE IF NOT EXISTS pagos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    referencia TEXT NOT NULL UNIQUE,
    wompi_id TEXT,
    cliente_alias TEXT NOT NULL,
    monto_centavos INTEGER NOT NULL,
    banco TEXT,
    correo TEXT,
    estado TEXT NOT NULL DEFAULT 'PENDING',
    fecha_creacion TEXT NOT NULL,
    fecha_actualizacion TEXT NOT NULL
  )
`);

function ahora() {
  return new Date().toISOString();
}

function generarReferencia() {
  return `INSP-${Date.now()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
}

function crear({ clienteAlias, montoCentavos, banco, correo }) {
  const referencia = generarReferencia();
  const fecha = ahora();
  db.prepare(`
    INSERT INTO pagos (referencia, cliente_alias, monto_centavos, banco, correo, estado, fecha_creacion, fecha_actualizacion)
    VALUES (?, ?, ?, ?, ?, 'PENDING', ?, ?)
  `).run(referencia, clienteAlias, montoCentavos, banco || null, correo || null, fecha, fecha);
  return referencia;
}

function asociarWompiId(referencia, wompiId) {
  db.prepare('UPDATE pagos SET wompi_id = ?, fecha_actualizacion = ? WHERE referencia = ?')
    .run(wompiId, ahora(), referencia);
}

function actualizarEstado(referencia, estado) {
  db.prepare('UPDATE pagos SET estado = ?, fecha_actualizacion = ? WHERE referencia = ?')
    .run(estado, ahora(), referencia);
}

function actualizarEstadoPorWompiId(wompiId, estado) {
  db.prepare('UPDATE pagos SET estado = ?, fecha_actualizacion = ? WHERE wompi_id = ?')
    .run(estado, ahora(), wompiId);
}

function obtenerPorReferencia(referencia) {
  return db.prepare('SELECT * FROM pagos WHERE referencia = ?').get(referencia) || null;
}

module.exports = {
  crear,
  asociarWompiId,
  actualizarEstado,
  actualizarEstadoPorWompiId,
  obtenerPorReferencia,
};
