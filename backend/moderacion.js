// Verificación de contenido de las respuestas de los colaboradores.
//
// Este módulo es la "guía" que revisa TODO lo que un colaborador envía
// (texto, imagen y video) antes de que llegue al cliente, y solo se
// encarga de una cosa: comprobar que no haya material explícito
// (sexual) ni violento.
//
// Funciona 100% en este servidor, sin APIs externas ni costos:
//  - Texto: reglas de palabras (contenido sexual explícito y violencia
//    gráfica).
//  - Imagen: dos modelos de código abierto (Apache 2.0 / MIT) que corren
//    con transformers.js + ONNX:
//      · Falconsai/nsfw_image_detection → contenido sexual/desnudez.
//      · CLIP (zero-shot) → escenas violentas (peleas, sangre, armas).
//  - Video: se extraen fotogramas repartidos con `ffmpeg` y cada uno se
//    revisa como imagen.
//  - Audio: no se revisa (no hay transcripción).
//
// Los modelos (~250 MB) se descargan una sola vez de Hugging Face al
// arrancar y se guardan en MODELOS_IA_DIR (por defecto ./modelos_ia).
//
// Si algo no se puede verificar (modelos sin descargar, sin ffmpeg...)
// y MODERACION_ESTRICTA no es "0", la respuesta se rechaza en vez de
// dejar pasar contenido sin revisar.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { promisify } = require('util');

const execFileP = promisify(execFile);

const ESTRICTA = process.env.MODERACION_ESTRICTA !== '0';
const UMBRAL_NSFW = parseFloat(process.env.MODERACION_UMBRAL_NSFW || '0.6');
const UMBRAL_VIOLENCIA = parseFloat(process.env.MODERACION_UMBRAL_VIOLENCIA || '0.6');
const DIR_MODELOS = process.env.MODELOS_IA_DIR || path.join(__dirname, 'modelos_ia');
const MAX_FOTOGRAMAS = 8;

const MODELO_NSFW = 'onnx-community/nsfw_image_detection-ONNX';
const MODELO_CLIP = 'Xenova/clip-vit-base-patch32';

// ---------------------------------------------------------------------
// Reglas locales de texto
// ---------------------------------------------------------------------

// Coinciden al inicio de una palabra (así "desnud" cubre "desnudo",
// "desnudas", pero "arma" no se activaría dentro de "armario").
const TERMINOS_SEXUALES = [
  'porno', 'pornograf', 'xxx', 'nsfw', 'desnud', 'erotic', 'prostitu',
  'sexo explicit', 'acto sexual', 'relaciones sexuales', 'genitales',
  'abuso sexual', 'explotacion sexual', 'violacion', 'violar', 'incesto',
  'pedofil', 'pederast',
];

const TERMINOS_VIOLENTOS = [
  'decapit', 'descuartiz', 'desmembr', 'mutilad', 'tortur', 'masacr',
  'asesinat', 'asesinar', 'degollar', 'apunal', 'acuchill', 'ahorcad',
  'cadaver', 'gore', 'autolesion', 'suicid',
];

function normalizar(texto) {
  return String(texto || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

function construirRegex(terminos) {
  return new RegExp('\\b(' + terminos.join('|') + ')', 'i');
}

const REGEX_SEXUAL = construirRegex(TERMINOS_SEXUALES);
const REGEX_VIOLENTO = construirRegex(TERMINOS_VIOLENTOS);

function revisarTextoConReglas(texto) {
  const t = normalizar(texto);
  if (REGEX_SEXUAL.test(t)) return 'contenido sexual explícito';
  if (REGEX_VIOLENTO.test(t)) return 'contenido violento';
  return null;
}

// ---------------------------------------------------------------------
// Modelos de imagen (locales)
// ---------------------------------------------------------------------

// Etiquetas para el clasificador zero-shot. Las "benignas" son
// necesarias para que fotos normales (fachadas, calles, mascotas...) no
// se confundan con violencia; el puntaje de violencia es la suma de las
// etiquetas violentas.
const ETIQUETAS_BENIGNAS = [
  'a photo of a building', 'a photo of a street', 'a photo of a store front',
  'a photo of a landscape', 'a photo of a room interior', 'a photo of a car',
  'a photo of people walking', 'a photo of an object', 'a logo or drawing',
  'a photo of an animal', 'a photo of a cat or dog', 'a photo of food',
  'a photo of a person', 'a photo of a group of people',
  'a photo of plants or trees', 'a photo of the sky', 'a photo of a house',
  'a photo of a shop counter', 'a photo of furniture',
];
const ETIQUETAS_VIOLENTAS = [
  'a photo of a violent fight', 'a photo of blood and injuries',
  'a photo of a dead body', 'a photo of a person pointing a gun',
  'a photo of a violent attack',
];
const ETIQUETAS_CLIP = [...ETIQUETAS_BENIGNAS, ...ETIQUETAS_VIOLENTAS];

let transformers = null;
const pipelines = {};

async function cargarTransformers() {
  if (!transformers) {
    transformers = await import('@huggingface/transformers');
    transformers.env.cacheDir = DIR_MODELOS;
  }
  return transformers;
}

function obtenerPipeline(clave, tarea, modelo) {
  if (!pipelines[clave]) {
    pipelines[clave] = (async () => {
      const t = await cargarTransformers();
      return t.pipeline(tarea, modelo, { dtype: 'q8' });
    })().catch((err) => {
      delete pipelines[clave]; // permite reintentar más tarde
      throw err;
    });
  }
  return pipelines[clave];
}

const obtenerNsfw = () =>
  obtenerPipeline('nsfw', 'image-classification', MODELO_NSFW);
const obtenerClip = () =>
  obtenerPipeline('clip', 'zero-shot-image-classification', MODELO_CLIP);

// Los modelos usan CPU: se procesa una imagen a la vez.
let cola = Promise.resolve();
function enCola(tarea) {
  const resultado = cola.then(tarea, tarea);
  cola = resultado.catch(() => {});
  return resultado;
}

/** Revisa una imagen (Buffer). Devuelve { permitido, motivo }. */
function revisarImagen(buffer) {
  return enCola(async () => {
    const t = await cargarTransformers();
    const imagen = await t.RawImage.fromBlob(new Blob([buffer]));

    const nsfw = await obtenerNsfw();
    const salidaNsfw = await nsfw(imagen, { top_k: 2 });
    const puntajeNsfw = salidaNsfw.find((r) => r.label === 'nsfw')?.score ?? 0;
    if (puntajeNsfw >= UMBRAL_NSFW) {
      return { permitido: false, motivo: 'contenido sexual o desnudez' };
    }

    const clip = await obtenerClip();
    const salidaClip = await clip(imagen, ETIQUETAS_CLIP);
    const puntajeViolencia = salidaClip
      .filter((r) => ETIQUETAS_VIOLENTAS.includes(r.label))
      .reduce((suma, r) => suma + r.score, 0);
    if (puntajeViolencia >= UMBRAL_VIOLENCIA) {
      return { permitido: false, motivo: 'contenido violento' };
    }

    return { permitido: true, motivo: '' };
  });
}

// ---------------------------------------------------------------------
// Video → fotogramas
// ---------------------------------------------------------------------

let ffmpegDisponible = null;
async function hayFfmpeg() {
  if (ffmpegDisponible !== null) return ffmpegDisponible;
  try {
    await execFileP('ffmpeg', ['-version']);
    await execFileP('ffprobe', ['-version']);
    ffmpegDisponible = true;
  } catch (_) {
    ffmpegDisponible = false;
  }
  return ffmpegDisponible;
}

async function extraerFotogramas(videoBase64) {
  const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'mod-'));
  try {
    const entrada = path.join(dir, 'video.bin');
    await fs.promises.writeFile(entrada, Buffer.from(videoBase64, 'base64'));

    let fps = 0.2;
    try {
      const { stdout } = await execFileP('ffprobe', [
        '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'csv=p=0', entrada,
      ]);
      const duracion = parseFloat(stdout);
      if (duracion > 0) fps = Math.min(1, MAX_FOTOGRAMAS / duracion);
    } catch (_) {
      // se queda con el valor por defecto
    }

    await execFileP('ffmpeg', [
      '-v', 'error', '-i', entrada,
      '-vf', `fps=${fps},scale=448:-2`,
      '-frames:v', String(MAX_FOTOGRAMAS), '-q:v', '4',
      path.join(dir, 'f_%02d.jpg'),
    ], { timeout: 60_000 });

    const archivos = (await fs.promises.readdir(dir))
      .filter((f) => f.startsWith('f_'))
      .sort();
    const fotogramas = [];
    for (const f of archivos) {
      fotogramas.push(await fs.promises.readFile(path.join(dir, f)));
    }
    return fotogramas;
  } finally {
    fs.promises.rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

// ---------------------------------------------------------------------
// API pública
// ---------------------------------------------------------------------

function noVerificable(motivo) {
  if (ESTRICTA) return { permitido: false, verificado: false, motivo };
  console.warn(`[moderación] Contenido sin verificar (modo no estricto): ${motivo}`);
  return { permitido: true, verificado: false, motivo };
}

/**
 * Revisa lo que envía un colaborador. Devuelve
 * { permitido, verificado, motivo }:
 *  - verificado=true  → se revisó; si permitido=false hay contenido
 *    explícito/violento (motivo dice cuál).
 *  - verificado=false → no se pudo revisar (ver MODERACION_ESTRICTA).
 */
async function verificarRespuesta({ texto, imagenBase64, videoBase64 }) {
  if (texto) {
    const motivo = revisarTextoConReglas(texto);
    if (motivo) return { permitido: false, verificado: true, motivo };
  }

  if (!imagenBase64 && !videoBase64) {
    // Solo texto: las reglas locales son la verificación.
    return { permitido: true, verificado: true, motivo: '' };
  }

  try {
    const imagenes = [];
    if (imagenBase64) imagenes.push(Buffer.from(imagenBase64, 'base64'));
    if (videoBase64) {
      if (!(await hayFfmpeg())) {
        return noVerificable('el servidor no puede analizar videos (falta ffmpeg)');
      }
      const fotogramas = await extraerFotogramas(videoBase64);
      if (fotogramas.length === 0) {
        return noVerificable('no se pudieron extraer imágenes del video');
      }
      imagenes.push(...fotogramas);
    }

    for (const buffer of imagenes) {
      const veredicto = await revisarImagen(buffer);
      if (!veredicto.permitido) return { ...veredicto, verificado: true };
    }
    return { permitido: true, verificado: true, motivo: '' };
  } catch (err) {
    console.error('[moderación] Error al verificar:', err.message);
    return noVerificable('no se pudo completar la verificación');
  }
}

/** Descarga/carga los modelos por adelantado (no bloquea el arranque). */
function precargar() {
  const inicio = Date.now();
  return Promise.all([obtenerNsfw(), obtenerClip()])
    .then(() => {
      console.log(`[moderación] Modelos listos (${Math.round((Date.now() - inicio) / 1000)} s).`);
    })
    .catch((err) => {
      console.error(
        '[moderación] No se pudieron cargar los modelos de imagen:', err.message,
        '— las respuestas con foto o video no se podrán verificar.'
      );
    });
}

function descripcionEstado() {
  const modo = ESTRICTA ? 'estricta' : 'no estricta';
  return 'Moderación de respuestas: texto por reglas, imágenes/video con '
    + `modelos locales (sin costo); modo ${modo}; modelos en ${DIR_MODELOS}.`;
}

module.exports = { verificarRespuesta, precargar, descripcionEstado };
