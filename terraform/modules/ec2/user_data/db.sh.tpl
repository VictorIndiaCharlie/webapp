#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# Seed data (kept in sync with backend/db/init.sql — runs on first container init only)
cat << 'SEED' > init.sql
CREATE TABLE IF NOT EXISTS words (
    id             SERIAL PRIMARY KEY,
    word           VARCHAR(100) UNIQUE NOT NULL,
    sorted_letters VARCHAR(100) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_words_sorted_letters ON words (sorted_letters);

INSERT INTO words (word, sorted_letters)
SELECT w,
       (SELECT string_agg(c, '' ORDER BY c)
        FROM unnest(string_to_array(lower(w), '')) AS c)
FROM unnest(ARRAY[
    'andrei', 'andreea', 'alexandru', 'maria', 'elena', 'ioana',
    'mihai', 'gabriel', 'ana', 'cristian', 'daniel', 'luca',
    'stefan', 'ionut', 'alina', 'alexandra', 'bogdan', 'catalin',
    'dragos', 'florin', 'george', 'ion', 'laurentiu', 'marius',
    'nicolae', 'oana', 'paul', 'radu', 'sorin', 'tudor', 'vasile',
    'dumitru', 'gheorghe', 'constantin', 'adrian', 'cornel', 'vlad',
    'matteo', 'sophie', 'luis', 'pierre', 'giulia', 'hans',
    'klaus', 'nikola', 'olga', 'sven', 'ivan', 'lars', 'emma',
    'olivia', 'liam', 'noah', 'lucas', 'sofia', 'alice', 'hugo',
    'arthur', 'leo', 'adam', 'david', 'karl', 'franz', 'giovanni',
    'isabella', 'charlotte', 'amelia', 'mia', 'leon', 'felix',
    'maximilian', 'anna', 'lena', 'nina', 'clara', 'laura',
    'julia', 'sara', 'elisa', 'martina', 'francesca', 'chiara'
]) AS w
ON CONFLICT (word) DO NOTHING;
SEED

cat << 'COMPOSE' > docker-compose.yml
services:
  db:
    image: postgres:16-alpine
    container_name: anagram_db
    ports:
      - "5432:5432"
    restart: unless-stopped
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/10-seed.sql:ro
    environment:
      POSTGRES_DB: anagrams
      POSTGRES_USER: anagram
      POSTGRES_PASSWORD: ${postgres_password}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U anagram -d anagrams"]
      interval: 5s
      timeout: 5s
      retries: 10
COMPOSE

docker compose up -d --no-deps db