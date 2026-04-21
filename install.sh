#!/bin/bash

# ==========================================
# Colors & Formatting
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==========================================
# Splash Screen
# ==========================================
clear

echo -e "${CYAN}"
echo "   _____            _  _____ _    _       "
echo "  / ____|          | |/ ____| |  (_)      "
echo " | (___   ___  __ _| | (___ | | ___ _ __  "
echo "  \___ \ / _ \/ _\` | |\___ \| |/ / | '_ \ "
echo "  ____) |  __/ (_| | |____) |   <| | | | |"
echo " |_____/ \___|\__,_|_|_____/|_|\_\_|_| |_|"
echo -e "${NC}"

echo -e "${BOLD}Secure Remote Application Streaming & Browser Isolation${NC}"
echo -e "A self-hosted platform enabling powerful, containerized desktop"
echo -e "applications streamed directly to any web browser or device."
echo ""
echo -e "${YELLOW}----------------------------------------------------------------${NC}"
echo -e " ${GREEN}Project Home:${NC}   https://github.com/selkies-project/sealskin/"
echo -e " ${GREEN}Docker Image:${NC}   https://github.com/linuxserver/docker-sealskin"
echo -e "${YELLOW}----------------------------------------------------------------${NC}"
echo -e " ${BLUE}Browser Extensions:${NC}"
echo -e "   Chrome:  https://chromewebstore.google.com/detail/sealskin-isolation/lclgfmnljgacfdpmmmjmfpdelndbbfhk"
echo -e "   Firefox: https://addons.mozilla.org/en-US/firefox/addon/sealskin-isolation/"
echo ""
echo -e " ${BLUE}Mobile Apps:${NC}"
echo -e "   iOS:     https://apps.apple.com/us/app/sealskin/id6758210210"
echo -e "   Android: https://play.google.com/store/apps/details?id=io.linuxserver.sealskin"
echo -e "${YELLOW}----------------------------------------------------------------${NC}"
echo ""

# 1. Sanity Check: Docker Installation
echo -e "${BLUE}Checking for Docker installation...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed on this host.${NC}"
    echo -e "Please install Docker before continuing: ${YELLOW}https://docs.docker.com/engine/install/${NC}"
    exit 1
fi
echo -e "${GREEN}Docker is installed.${NC}"
echo ""

# ==========================================
# Existing Installation / Renewal Detection
# ==========================================
CURRENT_DIR=$(pwd)
DEFAULT_CERTS="$CURRENT_DIR/certs"

# If docker-compose.yml and the certs/live directory exist, intercept the script
if [ -f "$CURRENT_DIR/docker-compose.yml" ] && [ -d "$DEFAULT_CERTS/live" ]; then
    echo -e "${BLUE}Existing installation detected in this directory.${NC}"

    # Find the domain directory inside live
    DOMAIN_DIR=$(find "$DEFAULT_CERTS/live" -mindepth 1 -maxdepth 1 -type d | head -n 1)

    if [ -n "$DOMAIN_DIR" ]; then
        DUCKDNS_DOMAIN=$(basename "$DOMAIN_DIR")
        FULLCHAIN="$DOMAIN_DIR/fullchain.pem"
        PRIVKEY="$DOMAIN_DIR/privkey.pem"

        if [ -f "$FULLCHAIN" ]; then
            # Extract expiration date
            EXP_DATE=$(openssl x509 -enddate -noout -in "$FULLCHAIN" | cut -d= -f2)
            echo -e "${CYAN}Domain: ${BOLD}$DUCKDNS_DOMAIN${NC}"
            echo -e "${CYAN}Current Certificate Expiration Date: ${BOLD}$EXP_DATE${NC}"
            echo ""

            read -p "Do you want to renew your certificates now? [y/N]: " RENEW_CONFIRM
            RENEW_CONFIRM=${RENEW_CONFIRM:-N}

            if [[ "$RENEW_CONFIRM" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Renewing SSL Certificates via Certbot...${NC}"

                # Run Certbot renewal
                sudo docker run --rm -it \
                  -v "$DEFAULT_CERTS:/etc/letsencrypt" \
                  infinityofspace/certbot_dns_duckdns:latest \
                    renew --force-renewal

                if [ $? -eq 0 ]; then
                    NEW_EXP_DATE=$(openssl x509 -enddate -noout -in "$FULLCHAIN" | cut -d= -f2)
                    echo -e "${GREEN}Certificates renewed successfully.${NC}"
                    echo -e "${CYAN}New Certificate Expiration Date: ${BOLD}$NEW_EXP_DATE${NC}"
                    echo ""
                    EXISTING_PUID=$(grep -oP '(?<=PUID=)[0-9]+' docker-compose.yml || id -u)
                    EXISTING_PGID=$(grep -oP '(?<=PGID=)[0-9]+' docker-compose.yml || id -g)
                    sudo chown -R "$EXISTING_PUID":"$EXISTING_PGID" "$DEFAULT_CERTS"
                    echo -e "${BLUE}Staging new certificates...${NC}"
                    # Dynamically find the config path from the existing docker-compose.yml
                    CONFIG_PATH=$(grep ":/config" docker-compose.yml | awk -F'- ' '{print $2}' | awk -F':' '{print $1}' | tr -d ' "')

                    if [ -n "$CONFIG_PATH" ] && [ -d "$CONFIG_PATH/ssl" ]; then
                        cp "$FULLCHAIN" "$CONFIG_PATH/ssl/proxy_cert.pem"
                        cp "$PRIVKEY" "$CONFIG_PATH/ssl/proxy_key.pem"
                        echo -e "${GREEN}Certificates staged to $CONFIG_PATH/ssl/${NC}"
                        echo ""
                        echo -e "${BLUE}Restarting the Docker Compose stack to apply changes...${NC}"
                        sudo docker compose restart

                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}Stack restarted successfully! New certificates are now live.${NC}"
                        else
                            echo -e "${RED}Failed to restart the stack. Please run 'sudo docker compose restart' manually.${NC}"
                        fi
                    else
                        echo -e "${RED}Could not automatically determine the config path to stage certs.${NC}"
                        echo -e "${YELLOW}Please manually copy the certs to your config/ssl folder and restart the stack.${NC}"
                    fi
                else
                    echo -e "${RED}Certificate renewal failed.${NC}"
                fi
            else
                echo -e "${BLUE}Skipping renewal.${NC}"
            fi
        fi
    fi

    echo ""
    echo -e "${GREEN}Exiting script. (To run a fresh setup, run this script in an empty directory).${NC}"
    exit 0
fi

# ==========================================
# User Configuration
# ==========================================

echo -e "${BLUE}Configuration Setup${NC}"
echo "Press ENTER to accept the [default] values."
echo ""

# --- PUID / PGID ---
DEFAULT_PUID=$(id -u)
DEFAULT_PGID=$(id -g)

read -p "Enter PUID [$DEFAULT_PUID]: " PUID
PUID=${PUID:-$DEFAULT_PUID}

read -p "Enter PGID [$DEFAULT_PGID]: " PGID
PGID=${PGID:-$DEFAULT_PGID}

# --- Paths ---
CURRENT_DIR=$(pwd)
DEFAULT_STORAGE="$CURRENT_DIR/storage"
DEFAULT_CONFIG="$CURRENT_DIR/config"
DEFAULT_CERTS="$CURRENT_DIR/certs"

read -p "Enter Sealskin Storage Path [$DEFAULT_CONFIG]: " SEALSKIN_STORAGE
SEALSKIN_STORAGE=${SEALSKIN_STORAGE:-$DEFAULT_CONFIG}

read -p "Enter Sealskin Config/Data Path [$DEFAULT_STORAGE]: " SEALSKIN_CONFIG
SEALSKIN_CONFIG=${SEALSKIN_CONFIG:-$DEFAULT_STORAGE}

read -p "Enter Certificate Storage Path [$DEFAULT_CERTS]: " CERTS_PATH
CERTS_PATH=${CERTS_PATH:-$DEFAULT_CERTS}

# --- Port ---
DEFAULT_PORT="8443"
read -p "Enter Port to expose [$DEFAULT_PORT]: " PORT
PORT=${PORT:-$DEFAULT_PORT}

echo ""
echo -e "${YELLOW}The following fields are required and will be validated.${NC}"

# --- DuckDNS Domain Validation ---
echo -e "${BLUE}Note on Domains:${NC} We will generate a wildcard certificate for your domain."
echo -e "This means if you enter 'example.duckdns.org', the cert covers '*.example.duckdns.org'."
echo -e "While the stack defaults to 'sealskin.example.duckdns.org', you can access it via 'anything.example.duckdns.org'."
echo ""

while true; do
    read -p "Enter DuckDNS Domain (e.g., example.duckdns.org): " DUCKDNS_DOMAIN
    # Basic regex for domain validation
    if [[ "$DUCKDNS_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        break
    else
        echo -e "${RED}Invalid domain format. Please try again.${NC}"
    fi
done

# --- DuckDNS Token Validation ---
while true; do
    read -p "Enter DuckDNS Token (UUID format): " DUCKDNS_TOKEN
    # Regex for UUID
    if [[ "$DUCKDNS_TOKEN" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        break
    else
        echo -e "${RED}Invalid token format. It should look like d5535353-4a28-4828-2828-282828282828.${NC}"
    fi
done

# --- Email Validation ---
while true; do
    read -p "Enter Email Address (for Let's Encrypt): " EMAIL
    # Basic regex for email
    if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo -e "${RED}Invalid email format. Please try again.${NC}"
    fi
done

echo ""
echo -e "${BLUE}Configuration gathered. Proceeding with setup...${NC}"
echo ""

# ==========================================
# Certificate Generation
# ==========================================

# Define where the specific certs will land inside the user defined path
CERT_ARCHIVE_PATH="$CERTS_PATH/archive/$DUCKDNS_DOMAIN"
FULLCHAIN="$CERT_ARCHIVE_PATH/fullchain1.pem"
PRIVKEY="$CERT_ARCHIVE_PATH/privkey1.pem"

if [ -f "$FULLCHAIN" ] && [ -f "$PRIVKEY" ]; then
    echo -e "${YELLOW}Certificates already exist at $CERT_ARCHIVE_PATH. Skipping generation.${NC}"
else
    echo -e "${BLUE}Generating SSL Certificates via Certbot...${NC}"
    echo -e "${BLUE}You will be prompted for sudo credentials to run Docker...${NC}"
    
    # Run the certbot container
    # Mapping the user defined CERTS_PATH to /etc/letsencrypt
    sudo docker run --rm -it \
      -v "$CERTS_PATH:/etc/letsencrypt" \
      infinityofspace/certbot_dns_duckdns:latest \
        certonly \
          --non-interactive \
          --agree-tos \
          --email "$EMAIL" \
          --preferred-challenges dns \
          --authenticator dns-duckdns \
          --dns-duckdns-token "$DUCKDNS_TOKEN" \
          --dns-duckdns-propagation-seconds 60 \
          -d "*.$DUCKDNS_DOMAIN"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Certificates generated successfully.${NC}"
    else
        echo -e "${RED}Certificate generation failed. Please check your token and domain.${NC}"
        exit 1
    fi
fi

# Chown the certs directory to the user's PUID/PGID so we can manipulate them
echo -e "${BLUE}Setting permissions on certificates...${NC}"
sudo chown -R "$PUID":"$PGID" "$CERTS_PATH"

# ==========================================
# Staging Files
# ==========================================

echo -e "${BLUE}Staging configuration files...${NC}"

# Create directories
mkdir -p config/ssl storage

# Copy certificates to the config location expected by Sealskin
if [ -f "$FULLCHAIN" ]; then
    cp "$FULLCHAIN" config/ssl/proxy_cert.pem
    cp "$PRIVKEY" config/ssl/proxy_key.pem
    echo -e "${GREEN}Certificates staged to config/ssl/${NC}"
else
    echo -e "${RED}Error: Certificates not found at $FULLCHAIN after generation step.${NC}"
    exit 1
fi

# ==========================================
# Create Docker Compose
# ==========================================

echo -e "${BLUE}Generating docker-compose.yml...${NC}"

cat <<EOF > docker-compose.yml
---
services:
  sealskin:
    image: lscr.io/linuxserver/sealskin:latest
    container_name: sealskin
    environment:
      - PUID=$PUID
      - PGID=$PGID
      - TZ=Etc/UTC
      - HOST_URL=sealskin.$DUCKDNS_DOMAIN
    volumes:
      - $SEALSKIN_STORAGE:/config
      - $SEALSKIN_CONFIG:/storage
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - $PORT:8443
    restart: unless-stopped
  duckdns:
    image: lscr.io/linuxserver/duckdns:latest
    container_name: duckdns
    environment:
      - TZ=Etc/UTC
      - SUBDOMAINS=$DUCKDNS_DOMAIN
      - TOKEN=$DUCKDNS_TOKEN
      - UPDATE_IP=ipv4
      - LOG_FILE=false
    restart: unless-stopped
EOF

echo -e "${GREEN}docker-compose.yml created.${NC}"
echo ""

# ==========================================
# Final Execution
# ==========================================

read -p "Do you want to start the stack now? [Y/n] " START_CONFIRM
START_CONFIRM=${START_CONFIRM:-Y}

if [[ "$START_CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Starting Docker Compose stack...${NC}"
    sudo docker compose up -d
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}==============================================${NC}"
        echo -e "${GREEN}       INSTALLATION COMPLETE                  ${NC}"
        echo -e "${GREEN}==============================================${NC}"
        echo ""
        echo -e "Sealskin is now running."
        echo ""
        echo -e "${YELLOW}IMPORTANT SECURITY NOTICE:${NC}"
        echo -e "1. Admin credentials have been generated in: ${BLUE}config/admin.json${NC}"
        echo -e "   Please use these to log in, then ${RED}DELETE${NC} that file immediately to keep it safe."
        echo ""
        echo -e "${YELLOW}NETWORKING:${NC}"
        echo -e "Ensure you forward port ${BLUE}$PORT${NC} (TCP) on your router to this machine's IP."
        echo -e "If you are inside your home network, you may need to set up Split DNS (dnsmasq) to resolve the domain locally."
        echo ""
        echo -e "Access your instance here:"
        echo -e "${BLUE}https://sealskin.$DUCKDNS_DOMAIN:$PORT${NC}"
        echo ""
    else
        echo -e "${RED}Failed to start docker compose stack.${NC}"
    fi
else
    echo -e "${YELLOW}Skipping start. You can run 'sudo docker compose up -d' manually later.${NC}"
fi
