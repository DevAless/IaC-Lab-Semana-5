#!/bin/bash
echo "=== Empaquetando lambdas para deploy ==="
ROOT_DIR=$(pwd)

# Convertir ruta Unix a Windows para PowerShell
WIN_ROOT=$(cygpath -w "$ROOT_DIR")

# ─── upload-lambda ────────────────────────────────────────────────────────────
echo ""
echo "→ Instalando dependencias de upload-lambda..."
cd "$ROOT_DIR/lambdas/upload-lambda"
npm install --omit=dev

echo "→ Generando upload-lambda.zip..."
WIN_SRC=$(cygpath -w "$ROOT_DIR/lambdas/upload-lambda")
WIN_DST=$(cygpath -w "$ROOT_DIR/upload-lambda.zip")
powershell.exe -Command "Compress-Archive -Path '$WIN_SRC\*' -DestinationPath '$WIN_DST' -Force"
echo "✓ upload-lambda.zip generado"

# ─── crop-lambda ─────────────────────────────────────────────────────────────
echo ""
echo "→ Instalando dependencias de crop-lambda..."
cd "$ROOT_DIR/lambdas/crop-lambda"
npm install --omit=dev

echo "→ Generando crop-lambda.zip..."
WIN_SRC=$(cygpath -w "$ROOT_DIR/lambdas/crop-lambda")
WIN_DST=$(cygpath -w "$ROOT_DIR/crop-lambda.zip")
powershell.exe -Command "Compress-Archive -Path '$WIN_SRC\*' -DestinationPath '$WIN_DST' -Force"
echo "✓ crop-lambda.zip generado"

cd "$ROOT_DIR"
echo ""
echo "=== Listo. Ahora puedes ejecutar terraform apply en el entorno deseado. ==="
