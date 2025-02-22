read -p "Soll das Grundsystem aufgesetzt werden?: (ja/nein): " GRUND_SYSTEM

if [ "$GRUND_SYSTEM" == "ja" ]; then
  echo "Installiere Grundsystem (Java, Mariadb und so)..."

  apt install unzip mariadb-server -y

  wget https://sourceforge.net/projects/symmetricds/files/symmetricds/symmetricds-3.15/symmetric-server-3.15.13.zip
  unzip symmetric-server-3.15.13.zip
  rm symmetric-server-3.15.13.zip
  mv symmetric-server-3.15.13 /opt/symmetricds

  apt install openjdk-17-jre -y

  cd /opt/symmetricds/lib

  wget https://dlm.mariadb.com/4174416/Connectors/java/connector-java-3.5.2/mariadb-java-client-3.5.2.jar
  #ggf läuft die url ab

  cd /opt/symmetricds
fi

# Eingaben abfragen
read -p "Gib die Sync-URL ein (z.B. http://ap.db.host-conductor.com:31416/sync): " SYNC_URL
read -p "Gib die Registration-URL ein (z.B. http://eu.db.host-conductor.com:31415/sync oder leer lassen): " REGISTRATION_URL
read -p "Gib die Group-ID ein (z.B. global): " GROUP_ID
read -p "Gib die External-ID ein (z.B. eu): " EXTERNAL_ID
read -p "Gib den Datenbank-Namen ein (z.B. test_base): " DB_NAME
read -p "Gib den Datenbank-Benutzer ein: " DB_USER
read -s -p "Gib das Passwort für den Datenbank-Benutzer ein: " DB_PASSWORD
echo ""

# MariaDB-Benutzer und Datenbank erstellen
echo "Erstelle die MariaDB-Datenbank und den Benutzer..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Zielverzeichnis sicherstellen
ENGINE_DIR="/opt/symmetricds/engines"
mkdir -p "$ENGINE_DIR"

# Datei erstellen
ENGINE_FILE="$ENGINE_DIR/$EXTERNAL_ID.properties"

cat > "$ENGINE_FILE" <<EOL
engine.name=$EXTERNAL_ID
db.driver=org.mariadb.jdbc.Driver
db.url=jdbc:mariadb://localhost:3306/$DB_NAME?serverTimezone=UTC
db.user=$DB_USER
db.password=$DB_PASSWORD
sync.url=$SYNC_URL
group.id=$GROUP_ID
external.id=$EXTERNAL_ID
job.purge.period.time.ms=86400000
job.routing.period.time.ms=10000
job.push.period.time.ms=10000
job.pull.period.time.ms=10000
EOL

# Frage, ob der aktuelle Node der Primary Node sein soll
read -p "Soll dieser Node der Primary Node sein? (ja/nein): " IS_PRIMARY

if [ "$IS_PRIMARY" == "ja" ]; then
  echo "Der Node wird als Primary Node konfiguriert..."
else
  echo "Wird als normaler node konfiguriert..."
  echo "registration.url=$REGISTRATION_URL" >> "$ENGINE_FILE"
fi

echo "Konfigurationsdatei erstellt: $ENGINE_FILE"

/opt/symmetricds/bin/symadmin --engine $EXTERNAL_ID create-sym-tables
#/opt/symmetricds/bin/sym --engine $EXTERNAL_ID

read -p "Soll ein Service erstellt werden? (ja/nein): " CREATE_SERVICE

if [ "$CREATE_SERVICE" != "ja" ]; then
  exit 1
fi

# Service-Datei für Systemd erstellen
SERVICE_FILE="/etc/systemd/system/symmetricds.service"

  # shellcheck disable=SC1073
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=SymmetricDS Service
After=network.target

[Service]
ExecStart=/opt/symmetricds/bin/sym
WorkingDirectory=/opt/symmetricds
User=root
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOL

echo "Systemd-Service-Datei erstellt: $SERVICE_FILE"

# Systemd neu laden, Service starten und aktivieren
echo "Lade Systemd und starte den Service..."
sudo systemctl daemon-reload
sudo systemctl start symmetricds.service
sudo systemctl enable symmetricds.service

echo "SymmetricDS läuft jetzt als Service!"

