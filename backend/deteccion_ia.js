/**
 * Detección de imágenes generadas por IA, usando el modelo "genai" de
 * Sightengine (https://sightengine.com). Se hace desde el backend (no
 * desde la app) para no exponer la clave de la API en el código fuente
 * público del repo.
 *
 * Requiere SIGHTENGINE_API_USER y SIGHTENGINE_API_SECRET en el .env —
 * ver backend/README.md para cómo crear una cuenta gratuita.
 */

const ENDPOINT = 'https://api.sightengine.com/1.0/check.json';

async function analizarImagen(imagenBase64) {
  const apiUser = process.env.SIGHTENGINE_API_USER;
  const apiSecret = process.env.SIGHTENGINE_API_SECRET;
  if (!apiUser || !apiSecret) {
    throw new Error('Detección de IA no configurada en el servidor (faltan credenciales de Sightengine)');
  }

  const buffer = Buffer.from(imagenBase64, 'base64');
  const form = new FormData();
  form.append('media', new Blob([buffer]), 'foto.jpg');
  form.append('models', 'genai');
  form.append('api_user', apiUser);
  form.append('api_secret', apiSecret);

  const respuesta = await fetch(ENDPOINT, { method: 'POST', body: form });
  const cuerpo = await respuesta.json();

  if (cuerpo.status !== 'success') {
    throw new Error(cuerpo.error?.message || 'El servicio de detección de IA no pudo analizar la imagen');
  }

  // 0 = totalmente real, 1 = totalmente generada por IA.
  const probabilidadIA = Number(cuerpo.type?.ai_generated ?? 0);
  const iaPorcentaje = Math.round(probabilidadIA * 100);
  const veracidadPorcentaje = 100 - iaPorcentaje;

  return { iaPorcentaje, veracidadPorcentaje };
}

module.exports = { analizarImagen };
