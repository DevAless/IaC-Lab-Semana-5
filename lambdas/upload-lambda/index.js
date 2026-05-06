"use strict";

const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const busboy = require("busboy");
const { v4: uuidv4 } = require("uuid");

// Cliente S3 — usa el endpoint de la VPC automáticamente si la Lambda
// está dentro de la VPC y el Gateway Endpoint está configurado.
const s3 = new S3Client({ region: process.env.AWS_REGION || "us-east-1" });

const BUCKET        = process.env.S3_BUCKET;
const UPLOAD_PREFIX = process.env.UPLOAD_PREFIX || "uploads/";
const MAX_SIZE      = 10 * 1024 * 1024; // 10 MB
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/gif", "image/webp"];
const ALLOWED_EXTS  = /\.(jpg|jpeg|png|gif|webp)$/i;

// ─── Helpers ─────────────────────────────────────────────────────────────────

function buildResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify(body),
  };
}

/**
 * Parsea multipart/form-data usando busboy.
 * Retorna { buffer, filename, mimetype }
 */
function parseMultipart(event) {
  return new Promise((resolve, reject) => {
    const contentType = event.headers["content-type"] || event.headers["Content-Type"] || "";
    const bb = busboy({ headers: { "content-type": contentType }, limits: { fileSize: MAX_SIZE } });

    let fileBuffer = null;
    let filename   = null;
    let mimetype   = null;
    let tooLarge   = false;

    bb.on("file", (fieldname, fileStream, info) => {
      filename = info.filename;
      mimetype = info.mimeType;
      const chunks = [];

      fileStream.on("data", (chunk) => chunks.push(chunk));
      fileStream.on("limit", () => { tooLarge = true; fileStream.resume(); });
      fileStream.on("end", () => {
        if (!tooLarge) fileBuffer = Buffer.concat(chunks);
      });
    });

    bb.on("finish", () => {
      if (tooLarge)   return reject(new Error("FILE_TOO_LARGE"));
      if (!fileBuffer) return reject(new Error("NO_FILE_FIELD"));
      resolve({ buffer: fileBuffer, filename, mimetype });
    });

    bb.on("error", reject);

    // API Gateway Payload 2.0 puede enviar body en base64
    const body = event.isBase64Encoded
      ? Buffer.from(event.body, "base64")
      : Buffer.from(event.body || "");

    bb.write(body);
    bb.end();
  });
}

// ─── Handler principal ────────────────────────────────────────────────────────

exports.handler = async (event) => {
  console.log("Evento recibido:", JSON.stringify({
    method:      event.requestContext?.http?.method,
    path:        event.requestContext?.http?.path,
    contentType: event.headers?.["content-type"],
    bodyLength:  event.body?.length,
  }));

  if (!BUCKET) {
    console.error("ERROR: Variable S3_BUCKET no configurada");
    return buildResponse(500, { message: "Error de configuración del servidor" });
  }

  const contentType = (event.headers?.["content-type"] || event.headers?.["Content-Type"] || "").toLowerCase();

  let fileBuffer, filename, mimetype;

  try {
    // ── Rama 1: multipart/form-data ──────────────────────────────────────────
    if (contentType.includes("multipart/form-data")) {
      ({ buffer: fileBuffer, filename, mimetype } = await parseMultipart(event));
    }
    // ── Rama 2: application/json con base64 ──────────────────────────────────
    else if (contentType.includes("application/json")) {
      const body = JSON.parse(event.body || "{}");

      if (!body.file)     return buildResponse(400, { message: "Campo 'file' requerido en base64" });
      if (!body.filename) return buildResponse(400, { message: "Campo 'filename' requerido" });

      fileBuffer = Buffer.from(body.file, "base64");
      filename   = body.filename;
      mimetype   = body.mimetype || "application/octet-stream";

      if (fileBuffer.length > MAX_SIZE) {
        return buildResponse(413, { message: "Archivo supera el límite de 10 MB" });
      }
    } else {
      return buildResponse(415, {
        message: "Content-Type no soportado. Use multipart/form-data o application/json+base64",
      });
    }
  } catch (err) {
    if (err.message === "FILE_TOO_LARGE") return buildResponse(413, { message: "Archivo supera el límite de 10 MB" });
    if (err.message === "NO_FILE_FIELD")  return buildResponse(400, { message: "No se encontró el campo 'file' en el formulario" });
    console.error("Error al parsear el body:", err);
    return buildResponse(400, { message: "Error al procesar el archivo" });
  }

  // ── Validar extensión ──────────────────────────────────────────────────────
  if (!ALLOWED_EXTS.test(filename)) {
    return buildResponse(400, {
      message: "Tipo de archivo no permitido. Solo se aceptan: jpg, png, gif, webp",
    });
  }

  // ── Validar mimetype ───────────────────────────────────────────────────────
  if (!ALLOWED_TYPES.includes(mimetype)) {
    return buildResponse(400, {
      message: `MIME type '${mimetype}' no permitido`,
    });
  }

  // ── Generar key única en S3 ────────────────────────────────────────────────
  const ext       = filename.split(".").pop().toLowerCase();
  const fileId    = uuidv4();
  const s3Key     = `${UPLOAD_PREFIX}${fileId}.${ext}`;

  // ── Subir a S3 ────────────────────────────────────────────────────────────
  try {
    await s3.send(new PutObjectCommand({
      Bucket:      BUCKET,
      Key:         s3Key,
      Body:        fileBuffer,
      ContentType: mimetype,
      Metadata: {
        "original-filename": filename,
        "upload-timestamp":  new Date().toISOString(),
      },
      // SSE-S3 (AES-256) — el bucket ya lo fuerza, pero lo especificamos
      ServerSideEncryption: "AES256",
    }));

    console.log(`Imagen subida exitosamente: s3://${BUCKET}/${s3Key}`);

    return buildResponse(200, {
      message:  "Imagen subida exitosamente",
      fileId,
      s3Key,
      size:     fileBuffer.length,
    });
  } catch (err) {
    console.error("Error al subir a S3:", err);
    return buildResponse(500, { message: "Error al almacenar la imagen" });
  }
};
