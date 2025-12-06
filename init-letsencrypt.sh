#!/bin/bash

# Script para obtener certificados SSL iniciales de Let's Encrypt
# Para el dominio umap.mingaabierta.org

DOMAIN="umap.mingaabierta.org"
EMAIL="panovaldez@democraciaenred.org"  # Cambia esto por tu email
STAGING=0  # Establecer a 1 si quieres usar el servidor de staging de Let's Encrypt

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # Sin Color

echo -e "${GREEN}Iniciando configuración de certificados SSL para $DOMAIN${NC}"

# Verificar si docker-compose está disponible
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: docker compose no está instalado${NC}"
    exit 1
fi

COMPOSE_CMD="docker compose"
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
fi

# Crear directorios necesarios si no existen
echo "Creando directorios necesarios..."
mkdir -p ./docker/certbot/conf
mkdir -p ./docker/certbot/www

# Descargar parámetros DH recomendados
echo "Descargando parámetros DH..."
if [ ! -f "./docker/certbot/conf/ssl-dhparams.pem" ]; then
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > ./docker/certbot/conf/options-ssl-nginx.conf
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > ./docker/certbot/conf/ssl-dhparams.pem
fi

# Usar configuración inicial de nginx (sin SSL)
echo "Configurando nginx para modo inicial (sin SSL)..."
cp ./docker/nginx.conf ./docker/nginx-ssl.conf.bak 2>/dev/null || true
cp ./docker/nginx-initial.conf ./docker/nginx.conf

echo "Iniciando servicios (sin certbot)..."
$COMPOSE_CMD up -d db redis app proxy

echo "Verificando que nginx esté funcionando..."
sleep 3
if ! $COMPOSE_CMD ps | grep proxy | grep -q "Up"; then
    echo -e "${RED}Error: nginx no pudo iniciar. Revisando logs...${NC}"
    $COMPOSE_CMD logs proxy
    exit 1
fi

echo "Esperando que nginx esté listo..."
sleep 5

# Obtener certificado
echo -e "${GREEN}Obteniendo certificado SSL de Let's Encrypt...${NC}"

if [ $STAGING != "0" ]; then
    STAGING_ARG="--staging"
    echo "MODO STAGING ACTIVADO - Los certificados no serán válidos"
else
    STAGING_ARG=""
fi

# Detener certbot si está corriendo
$COMPOSE_CMD stop certbot 2>/dev/null || true

# Ejecutar certbot con un comando específico
$COMPOSE_CMD run --rm --entrypoint "" certbot certbot certonly --webroot \
    --webroot-path=/var/www/certbot \
    $STAGING_ARG \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN

if [ $? -eq 0 ]; then
    echo -e "${GREEN}¡Certificado obtenido exitosamente!${NC}"
    
    # Restaurar configuración SSL de nginx
    echo "Activando configuración SSL de nginx..."
    cp ./docker/nginx-ssl.conf.bak ./docker/nginx.conf 2>/dev/null || true
    
    echo "Iniciando servicio certbot para renovaciones automáticas..."
    $COMPOSE_CMD up -d certbot
    
    echo "Reiniciando nginx con configuración SSL..."
    $COMPOSE_CMD restart proxy
    
    echo -e "${GREEN}¡Configuración completada! Tu sitio ahora está accesible en https://$DOMAIN${NC}"
else
    echo -e "${RED}Error al obtener el certificado.${NC}"
    
    # Restaurar configuración original si falló
    cp ./docker/nginx-ssl.conf.bak ./docker/nginx.conf 2>/dev/null || true
    
    echo "Verifica que:"
    echo "  1. El dominio $DOMAIN apunte correctamente a este servidor"
    echo "  2. Los puertos 80 y 443 estén abiertos en el firewall"
    echo "  3. No haya otro servicio usando los puertos 80 o 443"
    exit 1
fi
