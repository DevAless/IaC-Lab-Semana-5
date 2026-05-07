# ─── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames  = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpc"
  })
}

# ─── INTERNET GATEWAY ─────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-igw"
  })
}

# ─── PUBLIC SUBNETS ───────────────────────────────────────────────────────────
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-pub-a"
  })
}

resource "aws_subnet" "public_b" {
  count             = var.enable_multi_az ? 1 : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_b_cidr
  availability_zone = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-pub-b"
  })
}

# ─── PRIVATE SUBNETS ──────────────────────────────────────────────────────────
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = "${var.aws_region}a"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-priv-a"
  })
}

resource "aws_subnet" "private_b" {
  count             = var.enable_multi_az ? 1 : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = "${var.aws_region}b"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-priv-b"
  })
}

# ─── ELASTIC IPs para NAT (solo prod) ─────────────────────────────────────────
resource "aws_eip" "nat_a" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-eip-nat-a"
  })
}

resource "aws_eip" "nat_b" {
  count  = var.enable_nat_gateway && var.enable_multi_az ? 1 : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-eip-nat-b"
  })
}

# ─── NAT GATEWAYS (solo prod — justificación: ~$32/mes c/u) ──────────────────
# En DEV y QA se omiten. Las Lambdas se despliegan en subnets públicas
# o se accede a S3/SQS vía endpoints gratuitos. No se requiere HA en no-prod.
resource "aws_nat_gateway" "nat_a" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat_a[0].id
  subnet_id     = aws_subnet.public_a.id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-nat-a"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "nat_b" {
  count         = var.enable_nat_gateway && var.enable_multi_az ? 1 : 0
  allocation_id = aws_eip.nat_b[0].id
  subnet_id     = aws_subnet.public_b[0].id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-nat-b"
  })

  depends_on = [aws_internet_gateway.main]
}

# ─── ROUTE TABLES ─────────────────────────────────────────────────────────────

# Tabla de rutas pública → IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-rt-public"
  })
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  count          = var.enable_multi_az ? 1 : 0
  subnet_id      = aws_subnet.public_b[0].id
  route_table_id = aws_route_table.public.id
}

# Tabla de rutas privada AZ-a → NAT-a (prod) o vacía (dev/qa)
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat_a[0].id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-rt-priv-a"
  })
}

resource "aws_route_table" "private_b" {
  count  = var.enable_multi_az ? 1 : 0
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat_b[0].id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-rt-priv-b"
  })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  count          = var.enable_multi_az ? 1 : 0
  subnet_id      = aws_subnet.private_b[0].id
  route_table_id = aws_route_table.private_b[0].id
}

# ─── S3 GATEWAY ENDPOINT (gratis — tipo Gateway, sin ENI) ────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.private_a.id],
    var.enable_multi_az ? [aws_route_table.private_b[0].id] : [],
    [aws_route_table.public.id]
  )

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "arn:aws:s3:::${var.s3_bucket_name}/*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpce-s3"
  })
}

# ─── SQS INTERFACE ENDPOINT (solo prod — ~$7/mes por AZ) ─────────────────────
# Justificación: En DEV/QA las Lambdas acceden a SQS por internet (tráfico
# de desarrollo es mínimo). Solo en PROD se necesita que el tráfico quede
# dentro del backbone de AWS por seguridad y latencia.
resource "aws_security_group" "vpce_sqs" {
  count       = var.enable_sqs_endpoint ? 1 : 0
  name        = "${var.project}-${var.env}-sg-vpce-sqs"
  description = "SG para el SQS Interface Endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS desde Lambda upload"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.upload_lambda.id, aws_security_group.crop_lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-sg-vpce-sqs"
  })
}

resource "aws_vpc_endpoint" "sqs" {
  count               = var.enable_sqs_endpoint ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = concat(
    [aws_subnet.private_a.id],
    var.enable_multi_az ? [aws_subnet.private_b[0].id] : []
  )

  security_group_ids = [aws_security_group.vpce_sqs[0].id]

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-vpce-sqs"
  })
}

# ─── SECURITY GROUPS PARA LAMBDAS ────────────────────────────────────────────
resource "aws_security_group" "upload_lambda" {
  name        = "${var.project}-${var.env}-sg-upload-lambda"
  description = "SG upload Lambda - outbound HTTPS to S3 and SQS"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS salida (S3 Gateway Endpoint y SQS)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-sg-upload-lambda"
  })
}

resource "aws_security_group" "crop_lambda" {
  name        = "${var.project}-${var.env}-sg-crop-lambda"
  description = "SG crop Lambda - outbound HTTPS to S3 and SQS"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS salida (S3 Gateway Endpoint y SQS)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-sg-crop-lambda"
  })
}
