Lab Semana 4 - Procesador de Imagen — Infraestructura como Código

Alumno: Colona Chávez, Fabricio

Implementa una arquitectura serverless de procesamiento de imágenes en AWS, desplegable en tres entornos independientes (DEV, QA y PROD) mediante Terraform.
---
Descripción General
La arquitectura permite a un cliente subir una imagen a través de una API REST. La imagen se almacena en S3 y, de forma asíncrona y desacoplada, se recorta automáticamente a un formato circular de 40×40 píxeles. Este flujo desacopla la carga de la imagen del procesamiento, siguiendo un patrón habitual en aplicaciones que manejan medios como redes sociales o plataformas de perfil de usuario.
---
Flujo de la Arquitectura
```
Cliente
  │
  │  HTTPS POST /upload (multipart/form-data o JSON+base64, máx. 10 MB)
  ▼
API Gateway HTTP API v2
  │
  │  Lambda Proxy Invoke (Payload Format 2.0)
  ▼
upload-lambda (Node.js 20)
  │
  │  s3:PutObject → uploads/
  ▼
Amazon S3
  │
  │  S3 Event Notification (ObjectCreated en uploads/)
  ▼
Amazon SQS — Cola principal
  │
  │  Event Source Mapping (batch size 5, ReportBatchItemFailures)
  ▼
crop-lambda (Node.js 20 + sharp)
  │
  │  s3:PutObject → processed/ (PNG 40×40 circular)
  ▼
Amazon S3 (processed/)
```
Cuando la crop-lambda falla al procesar un mensaje, SQS lo reintenta hasta 3 veces. Al tercer fallo el mensaje se mueve al Dead-Letter Queue (DLQ), que dispara una alarma en CloudWatch.
---
Estructura del Proyecto
```
image-processor-iac/
├── modules/
│   ├── vpc/            # VPC, subnets, IGW, NAT, SGs, VPC Endpoints
│   ├── s3/             # Bucket, cifrado AES-256, versionamiento, lifecycle
│   ├── sqs/            # Cola principal + Dead-Letter Queue
│   ├── lambda/         # upload-lambda, crop-lambda, trigger SQS
│   ├── api-gateway/    # HTTP API v2, ruta POST /upload, throttling, logs
│   ├── iam/            # Roles con principio de mínimo privilegio
│   └── observability/  # Log Groups CloudWatch, SNS, alarma DLQ
├── environments/
│   ├── dev/            # Entorno de desarrollo
│   ├── qa/             # Entorno de pruebas
│   └── prod/           # Entorno de producción
├── lambdas/
│   ├── upload-lambda/  # Código Node.js — recibe y valida la imagen
│   └── crop-lambda/    # Código Node.js — recorta a 40×40 circular
└── build-lambdas.sh    # Script de empaquetado (.zip) para el deploy
```
---
Módulos Terraform
`vpc`
Crea la red privada donde se ejecutan los recursos. Incluye subnets públicas y privadas, Internet Gateway, NAT Gateways (solo PROD), tablas de rutas y Security Groups. Configura dos VPC Endpoints: uno tipo Gateway para S3 (siempre activo) y uno tipo Interface para SQS (solo PROD).
`s3`
Crea el bucket de imágenes con cifrado del lado del servidor AES-256, versionamiento habilitado, bloqueo total de acceso público y reglas de ciclo de vida para expiración automática de objetos en los prefijos `uploads/` y `processed/`. Configura las notificaciones S3 → SQS al crearse objetos en `uploads/`.
`sqs`
Crea la cola principal con long polling (20 s) y timeout de visibilidad de 360 s, y el Dead-Letter Queue con retención de 14 días. Define la política que autoriza a S3 a publicar mensajes en la cola.
`lambda`
Despliega las dos funciones Lambda con sus variables de entorno, configuración de memoria y timeout, y el Event Source Mapping de SQS hacia crop-lambda con soporte para `ReportBatchItemFailures`. En PROD las funciones se despliegan dentro de la VPC.
`api-gateway`
Crea un HTTP API v2 con la ruta `POST /upload`, integración Lambda Proxy con Payload Format 2.0, CORS habilitado, throttling configurable por entorno y access logs en formato JSON hacia CloudWatch.
`iam`
Define dos roles con mínimo privilegio: `upload-lambda-role` con permiso únicamente de `s3:PutObject` en el prefijo `uploads/`, y `crop-lambda-role` con `s3:GetObject` en `uploads/`, `s3:PutObject` en `processed/` y las operaciones SQS necesarias.
`observability`
Crea los Log Groups de CloudWatch para ambas Lambdas y el API Gateway, un SNS Topic para notificaciones y la alarma que se dispara cuando el DLQ tiene mensajes visibles.
---
Lambdas
`upload-lambda`
Runtime: Node.js 20, Memoria: 256 MB, Timeout: 30 s
Acepta `multipart/form-data` con campo `file` y `application/json` con campo `file` en base64
Valida extensión (jpg, png, gif, webp), MIME type y tamaño máximo de 10 MB
Genera un UUID único por archivo y lo sube a `uploads/` con cifrado AES-256
Dependencias: `@aws-sdk/client-s3`, `busboy`, `uuid`
`crop-lambda`
Runtime: Node.js 20, Memoria: 512 MB, Timeout: 60 s
Triggered por SQS con batch size 5 y `ReportBatchItemFailures`
Descarga la imagen original desde `uploads/`, aplica resize `cover` a 40×40 px con máscara SVG circular y genera un PNG con canal alfa transparente
Guarda el resultado en `processed/` con el sufijo `_circular.png`
Dependencias: `@aws-sdk/client-s3`, `sharp`
---
Entornos
El proyecto se desplegó en tres entornos completamente independientes en AWS, cada uno con su propio conjunto de recursos nombrados con el prefijo correspondiente.
Característica	DEV	QA	PROD
NAT Gateways	❌	❌	✅ ×2
Multi-AZ	❌	❌	✅
SQS Interface Endpoint	❌	❌	✅
Lambdas dentro de VPC	❌	❌	✅
Retención de logs	3 días	7 días	14 días
Throttling API	100 RPS	1.000 RPS	10.000 RPS
Expiración uploads/	7 días	15 días	30 días
Expiración processed/	14 días	30 días	90 días
Recursos creados	47	47	58
DEV
Entorno de desarrollo con configuración mínima. Las Lambdas se despliegan fuera de la VPC para simplificar el acceso. Sin multi-AZ ni endpoints adicionales. Retención de logs de 3 días.
QA
Entorno de pruebas con configuración intermedia. Igual que DEV en cuanto a red, pero con retención de logs de 7 días y throttling de 1.000 RPS para pruebas de carga ligeras.
PROD
Entorno de producción con la arquitectura completa del diagrama. Incluye dos Availability Zones, dos NAT Gateways para alta disponibilidad, SQS Interface Endpoint para mantener el tráfico dentro del backbone de AWS, Lambdas desplegadas dentro de la VPC, retención de logs de 14 días y throttling de 10.000 RPS.
---
Requisitos
Terraform >= 1.6
AWS CLI configurado (`aws configure`)
Node.js 20
Git Bash (en Windows)
---
Despliegue
1. Configurar credenciales AWS
```bash
aws configure
```
2. Empaquetar las Lambdas
```bash
bash build-lambdas.sh
```
3. Desplegar cada entorno
```bash
# DEV
cd environments/dev
terraform init
terraform apply

# QA
cd ../qa
terraform init
terraform apply

# PROD
cd ../prod
terraform init
terraform apply
```
---
Probar la API
```bash
# Reemplaza TU_API_ENDPOINT con el valor del output api_endpoint
curl -X POST https://TU_API_ENDPOINT/upload \
  -F "file=@/ruta/a/imagen.jpg"
```
Respuesta esperada:
```json
{
  "message": "Imagen subida exitosamente",
  "fileId": "uuid-generado",
  "s3Key": "uploads/uuid.jpg"
}
```
Luego verifica en S3 que aparecen dos objetos: la imagen original en `uploads/` y la imagen recortada en `processed/` con el sufijo `_circular.png`.
---
Verificación en la Consola AWS
Para cada entorno se verificaron los siguientes servicios en la consola AWS:
VPC — VPC, subnets, Internet Gateway, NAT Gateways (solo PROD), Route Tables, Security Groups y VPC Endpoints
S3 — Bucket con cifrado AES-256, versionamiento, bloqueo de acceso público y lifecycle rules
SQS — Cola principal con DLQ configurado con maxReceiveCount de 3
Lambda — Funciones con runtime Node.js 20, variables de entorno y trigger SQS en crop-lambda
API Gateway — HTTP API con ruta POST /upload y throttling configurado
IAM — Roles con políticas de mínimo privilegio para cada Lambda
CloudWatch — Log Groups con retención por entorno y alarma del DLQ en estado OK
---
Destrucción de Infraestructura
Una vez completada la verificación, se destruyeron todos los recursos de los tres entornos para liberar los recursos en AWS:
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
Terraform elimina todos los recursos en el orden correcto, respetando las dependencias entre ellos. Al finalizar cada `destroy`, el entorno queda completamente limpio en AWS.
---
Principios Aplicados
Least Privilege — Cada Lambda tiene únicamente los permisos que necesita, nada más.
Desacoplamiento — La carga (upload) y el procesamiento (crop) son independientes y se comunican por cola.
Observabilidad — Logs estructurados en CloudWatch y alarma automática ante fallos en el DLQ.
Infraestructura como Código — Toda la arquitectura es reproducible, versionable y eliminable con un solo comando.
Multi-entorno — Un mismo conjunto de módulos se reutiliza en DEV, QA y PROD con configuración diferente por variables.
Alta Disponibilidad — En PROD, recursos distribuidos en dos Availability Zones con NAT Gateways redundantes.