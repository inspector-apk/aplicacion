require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const db = require('./db');
const ubicaciones = require('./ubicaciones');
const usuarios = require('./usuarios');

const app = express();
app.use(cors());
// Límite alto porque una respuesta puede traer foto/audio/video en
// base64 dentro del body (el video es lo más pesado).
app.use(express.json({ limit: '60mb' }));

const PUERTO = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;

function requiereApiKey(req, res, next) {
  if (!API_KEY) return next(); // sin API_KEY configurada: solo para pruebas locales
  if (req.header('x-api-key') !== API_KEY) {
    return res.status(401).json({ ok: false, error: 'API key inválida' });
  }
  next();
}

const TIPOS_VALIDOS = ['texto', 'imagen', 'audio', 'video'];
const CATEGORIAS_VALIDAS = ['personal', 'comercial', 'industrial'];
const URGENCIAS_VALIDAS = ['unaHora', 'cincoHoras', 'dosDias'];

app.post('/api/solicitudes', requiereApiKey, (req, res) => {
  const { clienteAlias, tipos, categoria, urgencia, valorTotal, referenciaPago, metodoPago, descripcion, localidad, direccion, imagenReferenciaBase64, latitud, longitud } = req.body;

  if (!clienteAlias || typeof clienteAlias !== 'string') {
    return res.status(400).json({ ok: false, error: 'clienteAlias es requerido' });
  }
  if (!Array.isArray(tipos) || tipos.length === 0 || !tipos.every((t) => TIPOS_VALIDOS.includes(t))) {
    return res.status(400).json({ ok: false, error: 'tipos inválidos: elige al menos uno (texto, imagen, audio, video)' });
  }
  if (!CATEGORIAS_VALIDAS.includes(categoria)) {
    return res.status(400).json({ ok: false, error: 'categoria inválida' });
  }
  if (!URGENCIAS_VALIDAS.includes(urgencia)) {
    return res.status(400).json({ ok: false, error: 'urgencia inválida' });
  }
  if (typeof valorTotal !== 'number' || valorTotal < 0) {
    return res.status(400).json({ ok: false, error: 'valorTotal inválido' });
  }
  if (!descripcion || !localidad || !direccion) {
    return res.status(400).json({ ok: false, error: 'descripcion, localidad y direccion son requeridos' });
  }
  if (!referenciaPago || !metodoPago) {
    return res.status(400).json({ ok: false, error: 'Falta completar el pago (ficticio) antes de enviar' });
  }
  if (typeof latitud !== 'number' || typeof longitud !== 'number') {
    return res.status(400).json({ ok: false, error: 'latitud/longitud inválidas' });
  }

  // No permitir una segunda solicitud activa para el mismo cliente.
  const activa = db.solicitudActivaDeCliente(clienteAlias);
  if (activa) {
    return res
      .status(409)
      .json({ ok: false, error: 'Ya tienes una solicitud activa', solicitud: activa });
  }

  const solicitud = db.crearSolicitud({ clienteAlias, tipos, categoria, urgencia, valorTotal, referenciaPago, metodoPago, descripcion, localidad, direccion, imagenReferenciaBase64, latitud, longitud });
  res.status(201).json({ ok: true, solicitud });
});

app.get('/api/solicitudes/pendientes', requiereApiKey, (req, res) => {
  res.json({ ok: true, solicitudes: db.solicitudesPendientes() });
});

app.get('/api/solicitudes/activa', requiereApiKey, (req, res) => {
  const clienteAlias = String(req.query.clienteAlias || '');
  if (!clienteAlias) {
    return res.status(400).json({ ok: false, error: 'clienteAlias es requerido' });
  }
  res.json({ ok: true, solicitud: db.solicitudActivaDeCliente(clienteAlias) });
});

app.get('/api/solicitudes/en-curso', requiereApiKey, (req, res) => {
  const colaboradorAlias = String(req.query.colaboradorAlias || '');
  if (!colaboradorAlias) {
    return res.status(400).json({ ok: false, error: 'colaboradorAlias es requerido' });
  }
  res.json({ ok: true, solicitudes: db.solicitudesEnCursoDeColaborador(colaboradorAlias) });
});

app.post('/api/solicitudes/:id/aceptar', requiereApiKey, (req, res) => {
  const id = Number(req.params.id);
  const { colaboradorAlias } = req.body;
  if (!colaboradorAlias) {
    return res.status(400).json({ ok: false, error: 'colaboradorAlias es requerido' });
  }

  const solicitud = db.aceptarSolicitud(id, colaboradorAlias);
  if (!solicitud) {
    // Alguien más ya la aceptó, o ya no existe: "el primero que acepta se la gana".
    return res
      .status(409)
      .json({ ok: false, error: 'Esta solicitud ya no está disponible' });
  }
  res.json({ ok: true, solicitud });
});

// El colaborador envía su respuesta (uno o varios de: texto, imagen,
// audio, video) y con eso mismo queda completada la solicitud. Debe
// traer contenido para CADA tipo que se pidió originalmente.
app.post('/api/solicitudes/:id/responder', requiereApiKey, (req, res) => {
  const id = Number(req.params.id);
  const { colaboradorAlias, texto, imagenBase64, audioBase64, videoBase64 } = req.body;

  if (!colaboradorAlias) {
    return res.status(400).json({ ok: false, error: 'colaboradorAlias es requerido' });
  }

  const solicitudExistente = db.obtenerPorId(id);
  if (!solicitudExistente) {
    return res.status(404).json({ ok: false, error: 'Solicitud no encontrada' });
  }
  const contenidoPorTipo = { texto, imagen: imagenBase64, audio: audioBase64, video: videoBase64 };
  const faltantes = solicitudExistente.tipos.filter((t) => !contenidoPorTipo[t]);
  if (faltantes.length > 0) {
    return res.status(400).json({
      ok: false,
      error: `Falta responder: ${faltantes.join(', ')}`,
    });
  }

  const solicitud = db.responderSolicitud(id, colaboradorAlias, { texto, imagenBase64, audioBase64, videoBase64 });
  if (!solicitud) {
    return res
      .status(409)
      .json({ ok: false, error: 'No se pudo enviar la respuesta' });
  }
  res.json({ ok: true, solicitud });
});

// Entrega el contenido de la respuesta UNA SOLA VEZ: se borra del
// servidor en el mismo momento en que se consulta con éxito. Llamadas
// posteriores devuelven "ya fue vista".
app.get('/api/solicitudes/:id/respuesta', requiereApiKey, (req, res) => {
  const id = Number(req.params.id);
  const clienteAlias = String(req.query.clienteAlias || '');
  if (!clienteAlias) {
    return res.status(400).json({ ok: false, error: 'clienteAlias es requerido' });
  }

  const contenido = db.consumirRespuesta(id, clienteAlias);
  if (!contenido) {
    return res
      .status(409)
      .json({ ok: false, error: 'Esta respuesta ya fue vista o no existe' });
  }
  res.json({ ok: true, respuesta: contenido });
});

// Historial completo (cualquier estado) del cliente, sin el contenido
// de las respuestas — solo metadatos (fecha, quién respondió, etc.).
app.get('/api/solicitudes/historial', requiereApiKey, (req, res) => {
  const clienteAlias = String(req.query.clienteAlias || '');
  if (!clienteAlias) {
    return res.status(400).json({ ok: false, error: 'clienteAlias es requerido' });
  }
  res.json({ ok: true, solicitudes: db.historialDeCliente(clienteAlias) });
});

// El colaborador cancela una solicitud que ya había aceptado: vuelve a
// quedar disponible para cualquier otro colaborador. La app bloquea la
// cuenta de quien cancela por 5 minutos (eso lo hace el propio
// dispositivo, es local — ver AuthService.bloquearPorCancelacion).
app.post('/api/solicitudes/:id/cancelar-colaborador', requiereApiKey, (req, res) => {
  const id = Number(req.params.id);
  const { colaboradorAlias } = req.body;
  if (!colaboradorAlias) {
    return res.status(400).json({ ok: false, error: 'colaboradorAlias es requerido' });
  }
  const solicitud = db.colaboradorCancelaSolicitud(id, colaboradorAlias);
  if (!solicitud) {
    return res.status(409).json({ ok: false, error: 'No se pudo cancelar la solicitud' });
  }
  res.json({ ok: true, solicitud });
});

// Historial completo (cualquier estado) de un colaborador, para su
// pantalla de "Ganancias" (suma el valor_total de las completadas —
// FICTICIO, no hay dinero real de por medio).
app.get('/api/solicitudes/historial-colaborador', requiereApiKey, (req, res) => {
  const colaboradorAlias = String(req.query.colaboradorAlias || '');
  if (!colaboradorAlias) {
    return res.status(400).json({ ok: false, error: 'colaboradorAlias es requerido' });
  }
  res.json({ ok: true, solicitudes: db.historialDeColaborador(colaboradorAlias) });
});

app.post('/api/solicitudes/:id/cancelar', requiereApiKey, (req, res) => {
  const id = Number(req.params.id);
  const { clienteAlias } = req.body;
  const solicitud = db.cancelarSolicitud(id, clienteAlias);
  if (!solicitud) {
    return res.status(409).json({ ok: false, error: 'No se pudo cancelar la solicitud' });
  }
  res.json({ ok: true, solicitud });
});

// Usado por el panel de administrador de la app.
app.get('/api/solicitudes/todas', requiereApiKey, (req, res) => {
  res.json({ ok: true, solicitudes: db.todasLasSolicitudes() });
});

app.delete('/api/solicitudes/:id', requiereApiKey, (req, res) => {
  db.eliminarSolicitud(Number(req.params.id));
  res.json({ ok: true });
});

// El colaborador envía su posición mientras tiene la pantalla de inicio
// abierta ("disponible"), para que los clientes lo vean en el mapa. Se
// guarda solo en memoria (ver ubicaciones.js) y expira sola si deja de
// enviarse.
app.post('/api/colaboradores/ubicacion', requiereApiKey, (req, res) => {
  const { colaboradorAlias, latitud, longitud } = req.body;
  if (!colaboradorAlias || typeof colaboradorAlias !== 'string') {
    return res.status(400).json({ ok: false, error: 'colaboradorAlias es requerido' });
  }
  if (typeof latitud !== 'number' || typeof longitud !== 'number') {
    return res.status(400).json({ ok: false, error: 'latitud/longitud inválidas' });
  }
  ubicaciones.actualizarUbicacion(colaboradorAlias, latitud, longitud);
  res.json({ ok: true });
});

// El colaborador avisa que ya no está disponible (cierra sesión o sale
// de la pantalla de inicio) para desaparecer del mapa de inmediato.
app.post('/api/colaboradores/desconectar', requiereApiKey, (req, res) => {
  const { colaboradorAlias } = req.body;
  if (colaboradorAlias) ubicaciones.quitarUbicacion(colaboradorAlias);
  res.json({ ok: true });
});

// Posiciones aproximadas (difuminadas por privacidad) de los
// colaboradores disponibles ahora mismo, para pintarlos en el mapa del
// Cliente.
app.get('/api/colaboradores/cercanos', requiereApiKey, (req, res) => {
  res.json({ ok: true, colaboradores: ubicaciones.colaboradoresCercanos() });
});

// ---------------------------------------------------------------------
// Usuarios (cuentas): registro, login y todo lo que antes vivía 100%
// local en SQLite de cada celular. La contraseña NUNCA viaja en texto
// plano en el registro/login normales: el cliente ya trae el hash
// (SHA-256 salt:contraseña, mismo esquema que usaba localmente) — el
// servidor solo lo compara. La excepción es la creación de cuentas
// desde el panel de admin (contrasena en texto plano en el body),
// donde el propio servidor genera el salt y hashea.
// ---------------------------------------------------------------------

app.post('/api/usuarios/registro', requiereApiKey, (req, res) => {
  const { nombre, edad, correo, contrasenaHash, salt, aceptoPoliticas, declaraMayorEdad, rol } = req.body;
  if (!nombre || !correo || !contrasenaHash || !salt || typeof edad !== 'number') {
    return res.status(400).json({ ok: false, error: 'Faltan datos del registro' });
  }
  // El registro normal desde la app nunca manda `rol` (se elige después,
  // en la pantalla de selección de rol); solo lo usa el arranque de la
  // app para crear la cuenta admin precargada con su rol ya fijo.
  if (rol && !['cliente', 'colaborador', 'administrador'].includes(rol)) {
    return res.status(400).json({ ok: false, error: 'rol inválido' });
  }
  try {
    const usuario = usuarios.crear({ nombre, edad, correo, contrasenaHash, salt, aceptoPoliticas, declaraMayorEdad, rol });
    res.status(201).json({ ok: true, usuario });
  } catch (err) {
    if (err instanceof usuarios.ErrorUsuario) {
      return res.status(409).json({ ok: false, error: err.message });
    }
    res.status(500).json({ ok: false, error: 'No se pudo crear la cuenta' });
  }
});

// Paso 1 del login: el cliente necesita el salt del usuario para poder
// calcular el mismo hash localmente antes de mandarlo a verificar.
app.get('/api/usuarios/salt', requiereApiKey, (req, res) => {
  const correo = String(req.query.correo || '');
  if (!correo) return res.status(400).json({ ok: false, error: 'correo es requerido' });
  const salt = usuarios.obtenerSaltPorCorreo(correo);
  if (!salt) return res.status(404).json({ ok: false, error: 'No existe una cuenta con ese correo' });
  res.json({ ok: true, salt });
});

app.post('/api/usuarios/login', requiereApiKey, (req, res) => {
  const { correo, contrasenaHash } = req.body;
  if (!correo || !contrasenaHash) {
    return res.status(400).json({ ok: false, error: 'correo y contrasenaHash son requeridos' });
  }
  const usuario = usuarios.verificarLogin(correo, contrasenaHash);
  if (!usuario) {
    return res.status(401).json({ ok: false, error: 'Correo o contraseña incorrectos' });
  }
  res.json({ ok: true, usuario });
});

// Recuperación de contraseña: busca por alias o nombre completo (igual
// que antes, cuando era local) y devuelve el correo para que la app
// mande un código de verificación antes de dejar cambiar la contraseña
// — ya no puede ser "sin verificar nada" como cuando esto vivía en un
// solo dispositivo, porque ahora cualquier celular puede alcanzar
// cualquier cuenta.
app.get('/api/usuarios/buscar-recuperacion', requiereApiKey, (req, res) => {
  const texto = String(req.query.texto || '');
  if (!texto) return res.status(400).json({ ok: false, error: 'texto es requerido' });
  const usuario = usuarios.buscarPorAliasONombre(texto);
  if (!usuario) {
    return res.status(404).json({ ok: false, error: 'No se encontró ninguna cuenta con ese alias o nombre' });
  }
  res.json({ ok: true, usuario: { id: usuario.id, alias: usuario.alias, correo: usuario.correo } });
});

app.get('/api/usuarios/:id', requiereApiKey, (req, res) => {
  const usuario = usuarios.obtenerPorId(Number(req.params.id));
  if (!usuario) return res.status(404).json({ ok: false, error: 'Usuario no encontrado' });
  res.json({ ok: true, usuario });
});

// Incluye 'administrador': el admin puede promover a alguien a admin o
// bajarlo de vuelta a cliente/colaborador desde el panel.
app.patch('/api/usuarios/:id/rol', requiereApiKey, (req, res) => {
  const { rol } = req.body;
  if (!['cliente', 'colaborador', 'administrador'].includes(rol)) {
    return res.status(400).json({ ok: false, error: 'rol inválido' });
  }
  usuarios.actualizarRol(Number(req.params.id), rol);
  res.json({ ok: true, usuario: usuarios.obtenerPorId(Number(req.params.id)) });
});

app.patch('/api/usuarios/:id/contrasena', requiereApiKey, (req, res) => {
  const { contrasenaHash, salt } = req.body;
  if (!contrasenaHash || !salt) {
    return res.status(400).json({ ok: false, error: 'contrasenaHash y salt son requeridos' });
  }
  usuarios.actualizarContrasena(Number(req.params.id), contrasenaHash, salt);
  res.json({ ok: true });
});

// Herramienta de soporte del admin: cambia nombre/edad/correo de una
// cuenta directamente desde el panel.
app.patch('/api/usuarios/:id/datos', requiereApiKey, (req, res) => {
  const { nombre, edad, correo } = req.body;
  if (!nombre || !correo || typeof edad !== 'number') {
    return res.status(400).json({ ok: false, error: 'Faltan datos' });
  }
  const id = Number(req.params.id);
  try {
    usuarios.actualizarDatos(id, { nombre, edad, correo });
    res.json({ ok: true, usuario: usuarios.obtenerPorId(id) });
  } catch (err) {
    if (err instanceof usuarios.ErrorUsuario) {
      return res.status(409).json({ ok: false, error: err.message });
    }
    res.status(500).json({ ok: false, error: 'No se pudo actualizar' });
  }
});

// Herramienta de soporte del admin: fija una contraseña nueva en texto
// plano directamente (para cuando alguien no puede completar la
// recuperación normal por correo). El servidor la hashea aquí mismo.
app.patch('/api/usuarios/:id/resetear-contrasena', requiereApiKey, (req, res) => {
  const { contrasena } = req.body;
  if (!contrasena || contrasena.length < 6) {
    return res.status(400).json({ ok: false, error: 'La contraseña debe tener mínimo 6 caracteres' });
  }
  usuarios.resetearContrasena(Number(req.params.id), contrasena);
  res.json({ ok: true });
});

app.patch('/api/usuarios/:id/2fa', requiereApiKey, (req, res) => {
  const { secreto } = req.body;
  const id = Number(req.params.id);
  if (secreto) usuarios.activarTotp(id, secreto);
  else usuarios.desactivarTotp(id);
  res.json({ ok: true, usuario: usuarios.obtenerPorId(id) });
});

app.patch('/api/usuarios/:id/perfil-colaborador', requiereApiKey, (req, res) => {
  const { ocupacion, localidadTrabajo } = req.body;
  const id = Number(req.params.id);
  usuarios.actualizarPerfilColaborador(id, { ocupacion, localidadTrabajo });
  res.json({ ok: true, usuario: usuarios.obtenerPorId(id) });
});

app.patch('/api/usuarios/:id/cuenta-bancaria', requiereApiKey, (req, res) => {
  const { banco, numeroCuenta } = req.body;
  const id = Number(req.params.id);
  usuarios.actualizarCuentaBancaria(id, { banco, numeroCuenta });
  res.json({ ok: true, usuario: usuarios.obtenerPorId(id) });
});

// Bloqueo de 5 minutos por cancelar una solicitud aceptada (bloquear:true,
// lo llama la propia app) o para que el admin lo levante antes (bloquear:false).
app.patch('/api/usuarios/:id/bloqueo', requiereApiKey, (req, res) => {
  const { bloquear } = req.body;
  const id = Number(req.params.id);
  if (bloquear) {
    const hasta = new Date(Date.now() + 5 * 60 * 1000).toISOString();
    usuarios.bloquearHasta(id, hasta);
  } else {
    usuarios.quitarBloqueo(id);
  }
  res.json({ ok: true, usuario: usuarios.obtenerPorId(id) });
});

// Suspensión manual del admin (indefinida, no los 5 minutos automáticos
// por cancelar una solicitud) y su reverso — este último es el mismo
// "quitar bloqueo" de arriba, así que no hace falta duplicarlo.
app.patch('/api/usuarios/:id/suspender', requiereApiKey, (req, res) => {
  const id = Number(req.params.id);
  usuarios.suspender(id);
  res.json({ ok: true, usuario: usuarios.obtenerPorId(id) });
});

// ---- Solo para el panel de administrador ----

app.get('/api/usuarios', requiereApiKey, (req, res) => {
  res.json({ ok: true, usuarios: usuarios.listarTodos() });
});

// El admin crea una cuenta directamente con contraseña en texto plano
// (el servidor la hashea aquí mismo) — a diferencia del registro normal,
// que siempre llega ya hasheado desde la app.
app.post('/api/usuarios/admin-crear', requiereApiKey, (req, res) => {
  const { nombre, edad, correo, contrasena, rol } = req.body;
  if (!nombre || !correo || !contrasena || typeof edad !== 'number') {
    return res.status(400).json({ ok: false, error: 'Faltan datos' });
  }
  if (rol && !['cliente', 'colaborador', 'administrador'].includes(rol)) {
    return res.status(400).json({ ok: false, error: 'rol inválido' });
  }
  try {
    const usuario = usuarios.crear({
      nombre, edad, correo, contrasena, rol,
      aceptoPoliticas: true, declaraMayorEdad: true,
    });
    res.status(201).json({ ok: true, usuario });
  } catch (err) {
    if (err instanceof usuarios.ErrorUsuario) {
      return res.status(409).json({ ok: false, error: err.message });
    }
    res.status(500).json({ ok: false, error: 'No se pudo crear la cuenta' });
  }
});

app.delete('/api/usuarios/:id', requiereApiKey, (req, res) => {
  usuarios.eliminar(Number(req.params.id));
  res.json({ ok: true });
});

// Panel de administrador para PC: usuarios y solicitudes. Es un solo
// archivo HTML estático con su propio JS — pide la misma API_KEY del
// backend como "clave de administrador" para poder usar los endpoints
// de arriba, no agrega autenticación nueva.
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'admin-panel.html'));
});

app.get('/api/salud', (req, res) => res.json({ ok: true }));

app.listen(PUERTO, () => {
  console.log(`Backend de solicitudes de Inspector escuchando en el puerto ${PUERTO}`);
});
