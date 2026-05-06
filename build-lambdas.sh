#!/bin/bash
# build-lambdas.sh
# Empaqueta las lambdas en .zip listos para Terraform
# Ejecutar desde la raíz del proyecto: bash build-lambdas.sh

set -e

echo "=== Empaquetando lambdas para deploy ==="
ROOT_DIR=$(pwd)

# ─── upload-lambda ────────────────────────────────────────────────────────────
echo ""
echo "→ Instalando dependencias de upload-lambda..."
cd "$ROOT_DIR/lambdas/upload-lambda"
npm install --omit=dev
echo "→ Generando upload-lambda.zip..."
zip -r "$ROOT_DIR/upload-lambda.zip" . --exclude "*.test.js" --exclude ".env*"
echo "✓ upload-lambda.zip generado ($(du -sh "$ROOT_DIR/upload-lambda.zip" | cut -f1))"

# ─── crop-lambda ─────────────────────────────────────────────────────────────
echo ""
echo "→ Instalando dependencias de crop-lambda..."
cd "$ROOT_DIR/lambdas/crop-lambda"
# Sharp necesita binarios nativos para Linux x64 (plataforma de Lambda)
npm install --omit=dev --platform=linux --arch=x64
echo "→ Generando crop-lambda.zip..."
zip -r "$ROOT_DIR/crop-lambda.zip" . --exclude "*.test.js" --exclude ".env*"
echo "✓ crop-lambda.zip generado ($(du -sh "$ROOT_DIR/crop-lambda.zip" | cut -f1))"

cd "$ROOT_DIR"
echo ""
echo "=== Listo. Ahora puedes ejecutar terraform apply en el entorno deseado. ==="
echo ""
echo "Ejemplo:"
echo "  cd environments/dev"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
