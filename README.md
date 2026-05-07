Procesador de Imagen — Infraestructura como Código
Implementa una arquitectura serverless de procesamiento de imágenes en AWS, desplegable en tres entornos independientes (DEV, QA y PROD) mediante Terraform.

Alumno: Colona Chávez, Fabricio (ID: 000244576)
---
Descripción General
La arquitectura permite subir una imagen a través de una API REST. La imagen se almacena en S3 y, de forma asíncrona y desacoplada, se recorta automáticamente a un formato circular de 40×40 píxeles. Este flujo desacopla la carga de la imagen del procesamiento, siguiendo un patrón habitual en aplicaciones que manejan medios (redes sociales, plataformas de perfil, etc.).
---
Arquitectura
```
Cliente
  │
  │  HTTPS POST /upload (multipart/form-data o JSON+base64, máx. 10 MB)
  ▼
API Gateway HTTP API v2
  │
  │  Lambda Proxy Invoke (Payload 2.0)
  ▼
upload-lambda (Node.js 20)
  │
  │  s3:PutObject → uploads/
  ▼
Amazon S3
  │
  │  S3 Event Notification (ObjectCreated)
  ▼
Amazon SQS (cola principal)
  │
  │  Event Source Mapping (batch size 5, ReportBatchItemFailures)
  ▼
crop-lambda (Node.js 20 + sharp)
  │
  │  s3:PutObject → processed/ (PNG 40×40, máscara circular)
  ▼
Amazon S3 (processed/)
```
En caso de fallo repetido (3 intentos), los mensajes son redirigidos al Dead-Letter Queue (DLQ), que dispara una alarma en CloudWatch.
---
Estructura del Proyecto
```
image-processor-iac/
├── modules/
│   ├── vpc/            # VPC, subnets, IGW, NAT, SGs, VPC Endpoints
│   ├── s3/             # Bucket, cifrado, versionamiento, lifecycle, notificaciones
│   ├── sqs/            # Cola principal + Dead-Letter Queue
│   ├── lambda/         # upload-lambda, crop-lambda, ESM trigger
│   ├── api-gateway/    # HTTP API v2, ruta POST /upload, throttling, logs
│   ├── iam/            # Roles con principio de mínimo privilegio
│   └── observability/  # Log Groups, SNS, alarma DLQ
├── environments/
│   ├── dev/            # Entorno de desarrollo
│   ├── qa/             # Entorno de pruebas
│   └── prod/           # Entorno de producción (arquitectura completa)
├── lambdas/
│   ├── upload-lambda/  # Código Node.js — recibe y valida la imagen
│   └── crop-lambda/    # Código Node.js — recorta a 40×40 circular
└── build-lambdas.sh    # Script de empaquetado (.zip) para el deploy
```
---
Módulos Terraform
`vpc`
Crea la red privada donde se ejecutan las Lambdas. Incluye subnets públicas y privadas, Internet Gateway, NAT Gateways (solo PROD), tablas de rutas y Security Groups. También configura los VPC Endpoints: uno tipo Gateway para S3 (tráfico dentro de AWS) y uno tipo Interface para SQS (solo PROD).
`s3`
Crea el bucket de imágenes con cifrado del lado del servidor AES-256, versionamiento habilitado, bloqueo total de acceso público y reglas de ciclo de vida para expiración automática de objetos. Configura las notificaciones S3 → SQS al crearse objetos en el prefijo `uploads/`.
`sqs`
Crea la cola principal con long polling (20 s), timeout de visibilidad de 360 s (6× el timeout de la Lambda) y el Dead-Letter Queue con retención de 14 días. Define la política que autoriza a S3 a publicar mensajes.
`lambda`
Despliega las dos funciones Lambda dentro de la VPC con sus variables de entorno, configuración de memoria/timeout y Event Source Mapping de SQS hacia `crop-lambda` con soporte para `ReportBatchItemFailures`.
`api-gateway`
Crea un HTTP API v2 con la ruta `POST /upload`, integración Lambda Proxy con Payload Format 2.0, CORS habilitado, throttling configurable por entorno y access logs en formato JSON hacia CloudWatch.
`iam`
Define dos roles con mínimo privilegio: `upload-lambda-role` (solo `s3:PutObject` en `uploads/`) y `crop-lambda-role` (`s3:GetObject` en `uploads/`, `s3:PutObject` en `processed/`, y operaciones SQS necesarias).
`observability`
Crea los Log Groups de CloudWatch para ambas Lambdas y el API Gateway, un SNS Topic para notificaciones y la alarma que se dispara cuando el DLQ tiene mensajes visibles.
---
Entornos
Característica	DEV	QA	PROD
NAT Gateways	❌	❌	✅
Multi-AZ	❌	❌	✅
SQS Interface Endpoint	❌	❌	✅
Retención de logs	3 días	7 días	14 días
Throttling API	100 RPS	1 000 RPS	10 000 RPS
Expiración uploads/	7 días	15 días	30 días
Expiración processed/	14 días	30 días	90 días
---
Lambdas
`upload-lambda`
Runtime: Node.js 20, Memoria: 256 MB, Timeout: 30 s
Acepta `multipart/form-data` (campo `file`) y `application/json` (campo `file` en base64 + `filename`)
Valida extensión (jpg, png, gif, webp), MIME type y tamaño (máx. 10 MB)
Genera un UUID único para cada archivo y lo sube a `uploads/` con cifrado AES-256
Dependencias: `@aws-sdk/client-s3`, `busboy`, `uuid`
`crop-lambda`
Runtime: Node.js 20, Memoria: 512 MB, Timeout: 60 s
Triggered por SQS con batch size 5 y `ReportBatchItemFailures`
Descarga la imagen original desde `uploads/`, aplica resize `cover` a 40×40 px con máscara SVG circular, genera un PNG con canal alfa transparente
Guarda el resultado en `processed/` con el sufijo `\\\_circular.png`
Dependencias: `@aws-sdk/client-s3`, `sharp 0.33`
---
Requisitos
Terraform >= 1.6
AWS CLI configurado (`aws configure`)
Node.js 20
zip (disponible en la terminal)
---
Cómo Desplegar
```bash
# 1. Empaquetar las lambdas (una sola vez o cuando cambie el código)
bash build-lambdas.sh

# 2. Ir al entorno deseado
cd environments/dev   # o qa / prod

# 3. Inicializar Terraform
terraform init

# 4. Revisar los recursos que se crearán
terraform plan

# 5. Aplicar la infraestructura
terraform apply
```
Al finalizar, el output `api\\\_endpoint` muestra la URL del API Gateway lista para usar.
---
Probar la API
```bash
# Con multipart/form-data
curl -X POST https://TU\\\_API\\\_URL/upload \\\\
  -F "file=@/ruta/imagen.jpg"

# Con JSON + base64
curl -X POST https://TU\\\_API\\\_URL/upload \\\\
  -H "Content-Type: application/json" \\\\
  -d '{
    "file": "'$(base64 -i imagen.jpg)'",
    "filename": "imagen.jpg",
    "mimetype": "image/jpeg"
  }'
```
---
## Destruir la Infraestructura

```bash
# Destruir PROD
cd environments/prod
terraform destroy

# Destruir QA
cd ../qa
terraform destroy

# Destruir DEV
cd ../dev
terraform destroy
```

Terraform elimina todos los recursos en el orden correcto. Al finalizar cada destroy el entorno queda completamente limpio en AWS.
---
Principios Aplicados
Least Privilege: cada Lambda tiene únicamente los permisos que necesita, nada más.
Desacoplamiento: la carga (upload) y el procesamiento (crop) son independientes y se comunican por cola.
Observabilidad: logs estructurados en CloudWatch y alarma automática ante fallos en el DLQ.
Infraestructura como código: toda la arquitectura es reproducible, versionable y eliminable con un solo comando.
Multi-entorno: un mismo conjunto de módulos se reutiliza en DEV, QA y PROD con configuración diferente por variables.