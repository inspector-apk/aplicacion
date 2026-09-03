require('dotenv').config();
const express = require('express');
const cors = require('cors');
const db = require('./db');
const ubicaciones = require('./ubicaciones');

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

app.post('/api/solicitudes', requiereApiKey, (req, res) => {
  const { clienteAlias, tipos, categoria, valorTotal, referenciaPago, metodoPago, descripcion, localidad, direccion, latitud, longitud } = req.body;

  if (!clienteAlias || typeof clienteAlias !== 'string') {
    return res.status(400).json({ ok: false, error: 'clienteAlias es requerido' });
  }
  if (!Array.isArray(tipos) || tipos.length === 0 || !tipos.every((t) => TIPOS_VALIDOS.includes(t))) {
    return res.status(400).json({ ok: false, error: 'tipos inválidos: elige al menos uno (texto, imagen, audio, video)' });
  }
  if (!CATEGORIAS_VALIDAS.includes(categoria)) {
    return res.status(400).json({ ok: false, error: 'categoria inválida' });
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

  const solicitud = db.crearSolicitud({ clienteAlias, tipos, categoria, valorTotal, referenciaPago, metodoPago, descripcion, localidad, direccion, latitud, longitud });
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
// abierta ("disponible"), para que los clientes lo vean en el mapa como
// los carros de Uber/Didi. Se guarda solo en memoria (ver ubicaciones.js)
// y expira sola si deja de enviarse.
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

app.get('/api/salud', (req, res) => res.json({ ok: true }));

app.listen(PUERTO, () => {
  console.log(`Backend de solicitudes de Inspector escuchando en el puerto ${PUERTO}`);
});
