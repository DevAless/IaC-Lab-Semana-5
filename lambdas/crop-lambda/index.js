// lambdas/crop-lambda/index.js
// Runtime: nodejs20.x  |  Memory: 512 MB  |  Timeout: 60s
// Handler: index.handler
//
// Triggered por SQS (ESM, batch size 5, ReportBatchItemFailures)
// Flujo: SQS message → S3 GetObject (uploads/) → Sharp crop 40×40 circular PNG
//        → S3 PutObject (processed/)
//
// Variables de entorno requeridas:
//   S3_BUCKET        — nombre del bucket
//   PROCESSED_PREFIX — prefijo de destino (ej: "processed/")

"use strict";

const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

const s3 = new S3Client({ region: process.env.AWS_REGION || "us-east-1" });

const BUCKET           = process.env.S3_BUCKET;
const PROCESSED_PREFIX = process.env.PROCESSED_PREFIX || "processed/";
const TARGET_SIZE      = 40; // px — tal como especifica el diagrama

// ─── Máscara circular SVG para generar PNG transparente ───────────────────────
// El diagrama especifica: "SVG circle mask, PNG with transparent alpha"
const CIRCLE_MASK = Buffer.from(
  `<svg width="${TARGET_SIZE}" height="${TARGET_SIZE}">
    <circle cx="${TARGET_SIZE / 2}" cy="${TARGET_SIZE / 2}" r="${TARGET_SIZE / 2}" fill="white"/>
  </svg>`
);

// ─── Helper: stream S3 a Buffer ───────────────────────────────────────────────
async function streamToBuffer(stream) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    stream.on("data", (chunk) => chunks.push(chunk));
    stream.on("end", () => resolve(Buffer.concat(chunks)));
    stream.on("error", reject);
  });
}

// ─── Procesa un solo mensaje SQS ─────────────────────────────────────────────
async function processRecord(record) {
  // El evento SQS viene de la notificación S3 → SQS
  let s3Event;
  try {
    const sqsBody = JSON.parse(record.body);
    // La notificación S3 puede venir envuelta en "Records"
    s3Event = sqsBody.Records ? sqsBody.Records[0] : sqsBody;
  } catch (err) {
    throw new Error(`No se pudo parsear el body del mensaje SQS: ${err.message}`);
  }

  const sourceKey    = decodeURIComponent(s3Event.s3.object.key.replace(/\+/g, " "));
  const sourceBucket = s3Event.s3.bucket.name;

  console.log(`Procesando: s3://${sourceBucket}/${sourceKey}`);

  // ── Descargar imagen original ───────────────────────────────────────────
  let imageBuffer;
  try {
    const getResponse = await s3.send(new GetObjectCommand({
      Bucket: sourceBucket,
      Key:    sourceKey,
    }));
    imageBuffer = await streamToBuffer(getResponse.Body);
  } catch (err) {
    throw new Error(`Error descargando imagen de S3: ${err.message}`);
  }

  // ── Recortar a 40×40 con máscara circular ────────────────────────────────
  let croppedBuffer;
  try {
    croppedBuffer = await sharp(imageBuffer)
      .resize(TARGET_SIZE, TARGET_SIZE, {
        fit:      "cover",      // "cover" para llenar el cuadrado sin distorsión
        position: "center",
      })
      .composite([{
        input:  CIRCLE_MASK,
        blend:  "dest-in",      // Aplica la máscara — mantiene pixels dentro del círculo
      }])
      .png({ compressionLevel: 9 }) // PNG con máxima compresión — fondo transparente
      .toBuffer();
  } catch (err) {
    throw new Error(`Error procesando imagen con sharp: ${err.message}`);
  }

  // ── Generar key de destino ────────────────────────────────────────────────
  const originalFilename = sourceKey.split("/").pop(); // ej: "uuid.jpg"
  const baseName         = originalFilename.replace(/\.[^.]+$/, ""); // quitar extensión
  const destKey          = `${PROCESSED_PREFIX}${baseName}_circular.png`;

  // ── Subir imagen recortada ────────────────────────────────────────────────
  try {
    await s3.send(new PutObjectCommand({
      Bucket:      BUCKET,
      Key:         destKey,
      Body:        croppedBuffer,
      ContentType: "image/png",
      Metadata: {
        "source-key":         sourceKey,
        "processed-at":       new Date().toISOString(),
        "dimensions":         `${TARGET_SIZE}x${TARGET_SIZE}`,
        "shape":              "circular",
      },
      ServerSideEncryption: "AES256",
    }));

    console.log(`Imagen procesada y guardada: s3://${BUCKET}/${destKey} (${croppedBuffer.length} bytes)`);
  } catch (err) {
    throw new Error(`Error subiendo imagen procesada a S3: ${err.message}`);
  }

  return { sourceKey, destKey };
}

// ─── Handler principal (SQS con ReportBatchItemFailures) ─────────────────────
exports.handler = async (event) => {
  console.log(`Batch de ${event.Records.length} mensajes recibidos`);

  // ReportBatchItemFailures: reportamos cada falla individualmente
  // Los mensajes exitosos se eliminan; los fallidos vuelven a la cola
  // y después de 3 intentos van al DLQ (maxReceiveCount: 3 en el diagrama)
  const batchItemFailures = [];

  for (const record of event.Records) {
    try {
      const result = await processRecord(record);
      console.log(`✓ Mensaje ${record.messageId} procesado:`, result);
    } catch (err) {
      console.error(`✗ Falla en mensaje ${record.messageId}:`, err.message);
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  if (batchItemFailures.length > 0) {
    console.warn(`${batchItemFailures.length} mensajes fallaron y serán reintentados`);
  }

  // Retornar fallos → SQS los reintenta (hasta maxReceiveCount=3) → luego DLQ
  return { batchItemFailures };
};
