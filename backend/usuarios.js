const crypto = require('crypto');
const db = require('./conexion_db');

db.exec(`
  CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    edad INTEGER NOT NULL,
    correo TEXT NOT NULL UNIQUE,
    contrasena_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    alias TEXT NOT NULL UNIQUE,
    rol TEXT,
    fecha_registro TEXT NOT NULL,
    acepto_politicas INTEGER NOT NULL DEFAULT 0,
    declara_mayor_edad INTEGER NOT NULL DEFAULT 0,
    totp_secret TEXT,
    totp_habilitado INTEGER NOT NULL DEFAULT 0,
    ocupacion TEXT,
    localidad_trabajo TEXT,
    banco_ficticio TEXT,
    numero_cuenta_ficticia TEXT,
    bloqueado_hasta TEXT
  )
`);

// Todo excepto contrasena_hash y salt: eso nunca sale de esta base de
// datos por ningún endpoint. totp_secret sí se entrega, pero solo al
// propio dueño de la cuenta (login/registro) — nunca en el listado del
// admin, donde se usa COLUMNAS_ADMIN (sin ese campo tampoco).
const COLUMNAS_PROPIAS = `
  id, nombre, edad, correo, alias, rol, fecha_registro, acepto_politicas,
  declara_mayor_edad, totp_secret, totp_habilitado, ocupacion,
  localidad_trabajo, banco_ficticio, numero_cuenta_ficticia, bloqueado_hasta
`;

// Mismas columnas que COLUMNAS_PROPIAS (para que el modelo Usuario.fromMap
// del lado de la app pueda parsear cualquiera de las dos respuestas sin
// distinguir), pero con NULL en vez del secreto TOTP real: el admin ve
// que el 2FA está activo (totp_habilitado) sin poder ver el secreto.
const COLUMNAS_ADMIN = `
  id, nombre, edad, correo, alias, rol, fecha_registro, acepto_politicas,
  declara_mayor_edad, NULL AS totp_secret, totp_habilitado, ocupacion,
  localidad_trabajo, banco_ficticio, numero_cuenta_ficticia, bloqueado_hasta
`;

const PREFIJO_ALIAS = 'Inspector_';
const CARACTERES_ALIAS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generarSalt() {
  return crypto.randomBytes(16).toString('base64url');
}

/** Mismo esquema que el cliente usa localmente: SHA-256("salt:contraseña"). */
function hashear(contrasena, salt) {
  return crypto.createHash('sha256').update(`${salt}:${contrasena}`).digest('hex');
}

function generarAliasUnico() {
  for (let intento = 0; intento < 50; intento++) {
    let sufijo = '';
    for (let i = 0; i < 8; i++) {
      sufijo += CARACTERES_ALIAS[crypto.randomInt(CARACTERES_ALIAS.length)];
    }
    const alias = PREFIJO_ALIAS + sufijo;
    if (!existeAlias(alias)) return alias;
  }
  throw new Error('No se pudo generar un alias único');
}

function existeCorreo(correo) {
  return !!db.prepare('SELECT 1 FROM usuarios WHERE LOWER(correo) = ?').get(correo.toLowerCase());
}

function existeAlias(alias) {
  return !!db.prepare('SELECT 1 FROM usuarios WHERE LOWER(alias) = ?').get(alias.toLowerCase());
}

function ahora() {
  return new Date().toISOString();
}

class ErrorUsuario extends Error {}

/**
 * Crea una cuenta. Si no se pasa `contrasena` (texto plano) se espera
 * `contrasenaHash`+`salt` ya calculados por el cliente (registro normal
 * desde la app, que hashea localmente antes de enviar). Si se pasa
 * `contrasena` en texto plano, el servidor genera el salt y lo hashea
 * aquí mismo (usado por el panel de admin al crear una cuenta).
 */
function crear({ nombre, edad, correo, contrasena, contrasenaHash, salt, rol, aceptoPoliticas, declaraMayorEdad }) {
  const correoNormalizado = correo.trim().toLowerCase();
  if (existeCorreo(correoNormalizado)) {
    throw new ErrorUsuario('Ya existe una cuenta registrada con ese correo.');
  }

  let hashFinal = contrasenaHash;
  let saltFinal = salt;
  if (contrasena) {
    saltFinal = generarSalt();
    hashFinal = hashear(contrasena, saltFinal);
  }
  if (!hashFinal || !saltFinal) {
    throw new ErrorUsuario('Falta la contraseña.');
  }

  const alias = generarAliasUnico();
  const fecha = ahora();

  const info = db
    .prepare(`
      INSERT INTO usuarios
        (nombre, edad, correo, contrasena_hash, salt, alias, rol, fecha_registro, acepto_politicas, declara_mayor_edad)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .run(
      nombre.trim(), edad, correoNormalizado, hashFinal, saltFinal, alias,
      rol || null, fecha, aceptoPoliticas ? 1 : 0, declaraMayorEdad ? 1 : 0,
    );
  return obtenerPorId(info.lastInsertRowid);
}

function obtenerSaltPorCorreo(correo) {
  const fila = db.prepare('SELECT salt FROM usuarios WHERE LOWER(correo) = ?').get(correo.trim().toLowerCase());
  return fila ? fila.salt : null;
}

/** Verifica correo+hash y devuelve la cuenta completa (incluye totp_secret, para el propio dueño). */
function verificarLogin(correo, contrasenaHash) {
  const fila = db
    .prepare(`SELECT ${COLUMNAS_PROPIAS}, contrasena_hash FROM usuarios WHERE LOWER(correo) = ?`)
    .get(correo.trim().toLowerCase());
  if (!fila) return null;
  if (fila.contrasena_hash !== contrasenaHash) return null;
  delete fila.contrasena_hash;
  return fila;
}

function obtenerPorId(id) {
  return db.prepare(`SELECT ${COLUMNAS_PROPIAS} FROM usuarios WHERE id = ?`).get(id) || null;
}

/** Para la recuperación de contraseña: busca por alias o nombre completo. */
function buscarPorAliasONombre(texto) {
  const t = texto.trim().toLowerCase();
  return db
    .prepare(`SELECT ${COLUMNAS_PROPIAS} FROM usuarios WHERE LOWER(alias) = ? OR LOWER(nombre) = ? LIMIT 1`)
    .get(t, t) || null;
}

function listarTodos() {
  return db.prepare(`SELECT ${COLUMNAS_ADMIN} FROM usuarios ORDER BY fecha_registro DESC`).all();
}

function actualizarRol(id, rol) {
  db.prepare('UPDATE usuarios SET rol = ? WHERE id = ?').run(rol, id);
}

function actualizarContrasena(id, contrasenaHash, salt) {
  db.prepare('UPDATE usuarios SET contrasena_hash = ?, salt = ? WHERE id = ?').run(contrasenaHash, salt, id);
}

/** Herramienta de soporte del admin: cambia nombre/edad/correo de una cuenta. */
function actualizarDatos(id, { nombre, edad, correo }) {
  const correoNormalizado = correo.trim().toLowerCase();
  const enUso = db
    .prepare('SELECT 1 FROM usuarios WHERE LOWER(correo) = ? AND id != ?')
    .get(correoNormalizado, id);
  if (enUso) {
    throw new ErrorUsuario('Ya existe otra cuenta registrada con ese correo.');
  }
  db.prepare('UPDATE usuarios SET nombre = ?, edad = ?, correo = ? WHERE id = ?')
    .run(nombre.trim(), edad, correoNormalizado, id);
}

/**
 * Herramienta de soporte del admin: fija una contraseña nueva en texto
 * plano directamente desde el panel (para cuando alguien no puede
 * completar la recuperación normal por correo). El servidor genera un
 * salt nuevo y hashea aquí mismo, igual que en `crear`.
 */
function resetearContrasena(id, contrasenaPlano) {
  const salt = generarSalt();
  const hash = hashear(contrasenaPlano, salt);
  actualizarContrasena(id, hash, salt);
}

function activarTotp(id, secreto) {
  db.prepare('UPDATE usuarios SET totp_secret = ?, totp_habilitado = 1 WHERE id = ?').run(secreto, id);
}

function desactivarTotp(id) {
  db.prepare('UPDATE usuarios SET totp_secret = NULL, totp_habilitado = 0 WHERE id = ?').run(id);
}

function actualizarPerfilColaborador(id, { ocupacion, localidadTrabajo }) {
  db.prepare('UPDATE usuarios SET ocupacion = ?, localidad_trabajo = ? WHERE id = ?')
    .run(ocupacion || null, localidadTrabajo || null, id);
}

function actualizarCuentaBancaria(id, { banco, numeroCuenta }) {
  db.prepare('UPDATE usuarios SET banco_ficticio = ?, numero_cuenta_ficticia = ? WHERE id = ?')
    .run(banco || null, numeroCuenta || null, id);
}

function bloquearHasta(id, hastaIso) {
  db.prepare('UPDATE usuarios SET bloqueado_hasta = ? WHERE id = ?').run(hastaIso, id);
}

function quitarBloqueo(id) {
  db.prepare('UPDATE usuarios SET bloqueado_hasta = NULL WHERE id = ?').run(id);
}

// Un umbral así de lejano (100 años) se usa como "suspensión indefinida"
// desde el panel de admin, reutilizando el mismo campo del bloqueo
// temporal de 5 minutos por cancelar una solicitud — a la app y al panel
// les basta con saber si `bloqueado_hasta` sigue en el futuro o no.
const MINUTOS_SUSPENSION_INDEFINIDA = 100 * 365 * 24 * 60;

function suspender(id) {
  const hasta = new Date(Date.now() + MINUTOS_SUSPENSION_INDEFINIDA * 60 * 1000).toISOString();
  bloquearHasta(id, hasta);
}

function eliminar(id) {
  db.prepare('DELETE FROM usuarios WHERE id = ?').run(id);
}

module.exports = {
  ErrorUsuario,
  hashear,
  crear,
  existeCorreo,
  obtenerSaltPorCorreo,
  verificarLogin,
  obtenerPorId,
  buscarPorAliasONombre,
  listarTodos,
  actualizarRol,
  actualizarContrasena,
  actualizarDatos,
  resetearContrasena,
  activarTotp,
  desactivarTotp,
  actualizarPerfilColaborador,
  actualizarCuentaBancaria,
  bloquearHasta,
  quitarBloqueo,
  suspender,
  eliminar,
};
