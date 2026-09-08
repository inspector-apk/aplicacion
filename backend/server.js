require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const db = require('./db');
const ubicaciones = require('./ubicaciones');
const usuarios = require('./usuarios');
const wompi = require('./wompi');
const pagos = require('./pagos');

const app = express();
app.use(cors());
// Assets estáticos del panel de administrador (el logo de la app).
app.use(express.static(path.join(__dirname, 'public')));
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
    return res.status(400).json({ ok: false, error: 'Falta completar el pago antes de enviar' });
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

// ---------------------------------------------------------------------
// Pagos por PSE (Wompi) — pasarela real, a diferencia del resto de la
// app que es ficticio. En modo sandbox por defecto: ver
// backend/README.md para cómo obtener llaves de prueba gratis.
// ---------------------------------------------------------------------

app.get('/api/pagos/bancos-pse', requiereApiKey, async (req, res) => {
  try {
    res.json({ ok: true, bancos: await wompi.listarBancosPSE() });
  } catch (err) {
    res.status(502).json({ ok: false, error: err.message });
  }
});

// Crea la transacción PSE y devuelve la URL a la que hay que mandar al
// cliente para que autentique el pago con su banco. `montoCentavos` es
// el valor en centavos de peso (multiplica el valor en pesos por 100).
app.post('/api/pagos/pse', requiereApiKey, async (req, res) => {
  const {
    clienteAlias, montoCentavos, correo, codigoBanco,
    tipoPersona, tipoDocumento, numeroDocumento, redirectUrl, descripcion,
  } = req.body;

  if (!clienteAlias || typeof montoCentavos !== 'number' || montoCentavos <= 0) {
    return res.status(400).json({ ok: false, error: 'clienteAlias y montoCentavos son requeridos' });
  }
  if (!correo || !codigoBanco || !tipoDocumento || !numeroDocumento || !redirectUrl) {
    return res.status(400).json({ ok: false, error: 'Faltan datos del pago (correo, banco, documento o redirectUrl)' });
  }

  const referencia = pagos.crear({ clienteAlias, montoCentavos, banco: codigoBanco, correo });
  try {
    const { wompiId, estado, urlBanco } = await wompi.crearTransaccionPSE({
      referencia, montoCentavos, correo, codigoBanco, tipoPersona,
      tipoDocumento, numeroDocumento, redirectUrl, descripcion,
    });
    pagos.asociarWompiId(referencia, wompiId);
    pagos.actualizarEstado(referencia, estado);
    res.status(201).json({ ok: true, referencia, urlBanco });
  } catch (err) {
    pagos.actualizarEstado(referencia, 'ERROR');
    const codigo = err instanceof wompi.ErrorWompi ? 502 : 500;
    res.status(codigo).json({ ok: false, error: err.message });
  }
});

// La app hace polling de esto mientras el cliente está en el banco
// autenticando el pago. Si sigue PENDING, de paso consulta a Wompi
// directamente (no depende únicamente del webhook, que necesita HTTPS
// configurado en el panel de Wompi para funcionar).
app.get('/api/pagos/estado/:referencia', requiereApiKey, async (req, res) => {
  const pago = pagos.obtenerPorReferencia(req.params.referencia);
  if (!pago) return res.status(404).json({ ok: false, error: 'Pago no encontrado' });

  if (pago.estado === 'PENDING' && pago.wompi_id) {
    try {
      const transaccion = await wompi.obtenerTransaccion(pago.wompi_id);
      if (transaccion?.status && transaccion.status !== pago.estado) {
        pagos.actualizarEstado(pago.referencia, transaccion.status);
        pago.estado = transaccion.status;
      }
    } catch (_) {
      // Si Wompi no responde en este momento, se devuelve el último
      // estado conocido; la app sigue reintentando.
    }
  }
  res.json({ ok: true, estado: pago.estado });
});

// Wompi notifica aquí cuando cambia el estado de una transacción.
// Requiere configurar esta URL en el panel de Wompi (Desarrolladores >
// Webhooks) — necesita HTTPS, así que solo funciona una vez el backend
// tenga un certificado real (ver la guía de nginx + Let's Encrypt).
// Mientras tanto, GET /api/pagos/estado/:referencia (arriba) cubre lo
// mismo por polling directo a Wompi.
app.post('/api/pagos/webhook-wompi', (req, res) => {
  const { event, data, signature, timestamp } = req.body || {};
  if (event !== 'transaction.updated' || !data?.transaction) {
    return res.status(200).json({ ok: true }); // se ignora, pero se responde 200
  }
  if (!wompi.verificarFirmaWebhook({ data, signature, timestamp })) {
    return res.status(401).json({ ok: false, error: 'Firma inválida' });
  }
  const { id, status } = data.transaction;
  pagos.actualizarEstadoPorWompiId(id, status);
  res.json({ ok: true });
});

// Panel de administrador para PC: usuarios y solicitudes. Es un solo
// archivo HTML estático con su propio JS — pide la misma API_KEY del
// backend como "clave de administrador" para poder usar los endpoints
// de arriba, no agrega autenticación nueva.
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'admin-panel.html'));
});

// A esta página vuelve el navegador después de que el cliente autentica
// el pago PSE con su banco (Wompi la abre con `?id=...` en la URL). La
// app no depende de esto para saber si el pago quedó aprobado (usa
// polling a /api/pagos/estado), es solo para que la persona sepa que ya
// puede cerrar el navegador y volver a Inspector.
app.get('/pago-completado', (req, res) => {
  res.send(`<!doctype html><html lang="es"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Pago procesado — Inspector</title>
    <style>
      body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
        background:#000; color:#f5f5f5; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif; text-align:center; padding:24px; }
      .caja { max-width:360px; }
      h1 { color:#ffd700; font-size:20px; margin:0 0 10px; }
      p { color:#a0a0a3; font-size:14px; line-height:1.5; }
    </style></head><body>
    <div class="caja">
      <h1>Pago procesado</h1>
      <p>Ya puedes cerrar esta ventana y volver a la app Inspector — ahí verás la confirmación.</p>
    </div>
    </body></html>`);
});

app.get('/api/salud', (req, res) => res.json({ ok: true }));

app.listen(PUERTO, () => {
  console.log(`Backend de solicitudes de Inspector escuchando en el puerto ${PUERTO}`);
});
