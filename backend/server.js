require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { enviarCorreoCodigo } = require('./mailer');

const app = express();
app.use(cors());
app.use(express.json());

const PUERTO = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;

const DURACION_CODIGO_MS = 10 * 60 * 1000; // 10 minutos
const DURACION_VERIFICADO_MS = 30 * 60 * 1000; // 30 minutos
const REENVIO_MIN_MS = 30 * 1000; // 30 segundos entre reenvíos

// Almacenamiento en memoria: se pierde si el proceso se reinicia, lo
// cual está bien porque los códigos son de corta duración (el usuario
// simplemente pide uno nuevo).
const codigosPendientes = new Map(); // correo -> { codigo, expira, ultimoEnvio }
const correosVerificados = new Map(); // correo -> expira

const EMAIL_REGEX = /^[\w.-]+@[\w-]+\.[a-zA-Z]{2,}$/;

function requiereApiKey(req, res, next) {
  if (!API_KEY) return next(); // sin API_KEY configurada: solo para pruebas locales
  if (req.header('x-api-key') !== API_KEY) {
    return res.status(401).json({ ok: false, error: 'API key inválida' });
  }
  next();
}

function generarCodigo() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

app.post('/api/enviar-codigo', requiereApiKey, async (req, res) => {
  const correo = String(req.body.correo || '').trim().toLowerCase();
  if (!EMAIL_REGEX.test(correo)) {
    return res.status(400).json({ ok: false, error: 'Correo inválido' });
  }

  const ahora = Date.now();
  const pendiente = codigosPendientes.get(correo);
  if (pendiente && ahora - pendiente.ultimoEnvio < REENVIO_MIN_MS) {
    return res
      .status(429)
      .json({ ok: false, error: 'Espera unos segundos antes de reenviar el código' });
  }

  const codigo = generarCodigo();
  codigosPendientes.set(correo, {
    codigo,
    expira: ahora + DURACION_CODIGO_MS,
    ultimoEnvio: ahora,
  });

  try {
    await enviarCorreoCodigo(correo, codigo);
    res.json({ ok: true });
  } catch (err) {
    console.error('Error enviando correo:', err);
    res.status(500).json({ ok: false, error: 'No se pudo enviar el correo' });
  }
});

app.post('/api/verificar-codigo', requiereApiKey, (req, res) => {
  const correo = String(req.body.correo || '').trim().toLowerCase();
  const codigo = String(req.body.codigo || '').trim();

  const pendiente = codigosPendientes.get(correo);
  if (!pendiente || Date.now() > pendiente.expira) {
    return res.status(400).json({ ok: false, error: 'El código expiró, solicita uno nuevo' });
  }
  if (pendiente.codigo !== codigo) {
    return res.status(400).json({ ok: false, error: 'Código incorrecto' });
  }

  codigosPendientes.delete(correo);
  correosVerificados.set(correo, Date.now() + DURACION_VERIFICADO_MS);
  res.json({ ok: true });
});

// Consultado opcionalmente por el cliente para confirmar que el correo
// sigue "verificado" antes de crear la cuenta.
app.get('/api/esta-verificado', requiereApiKey, (req, res) => {
  const correo = String(req.query.correo || '').trim().toLowerCase();
  const expira = correosVerificados.get(correo);
  res.json({ ok: true, verificado: Boolean(expira) && Date.now() < expira });
});

app.get('/api/salud', (req, res) => res.json({ ok: true }));

// Limpieza periódica de códigos/verificaciones vencidos.
setInterval(() => {
  const ahora = Date.now();
  for (const [correo, v] of codigosPendientes) {
    if (ahora > v.expira) codigosPendientes.delete(correo);
  }
  for (const [correo, expira] of correosVerificados) {
    if (ahora > expira) correosVerificados.delete(correo);
  }
}, 60 * 1000);

app.listen(PUERTO, () => {
  console.log(`Servicio de verificación de Inspector escuchando en el puerto ${PUERTO}`);
});
