const path = require('path');
const Database = require('better-sqlite3');

// Una sola conexión compartida (modo WAL) para todo el backend:
// solicitudes.js la usa para las solicitudes, usuarios.js para las
// cuentas. Mismo archivo de base de datos que ya existía.
const db = new Database(path.join(__dirname, 'solicitudes.db'));
db.pragma('journal_mode = WAL');

module.exports = db;
