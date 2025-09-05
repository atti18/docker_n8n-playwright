#!/bin/sh

# Map Cloud Run's PORT to N8N_PORT if it exists
if [ -n "$PORT" ]; then
  export N8N_PORT=$PORT
fi

# Supabase configuration
if [ -n "$SUPABASE_URL" ]; then
  export DB_TYPE=postgresdb
  
  # Parse Supabase connection string
  # Format: postgresql://[user]:[password]@[host]:[port]/[database]
  SUPABASE_HOST=$(echo $SUPABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
  SUPABASE_PORT=$(echo $SUPABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
  SUPABASE_DATABASE=$(echo $SUPABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')
  SUPABASE_USER=$(echo $SUPABASE_URL | sed -n 's/.*\/\/\([^:]*\):.*/\1/p')
  SUPABASE_PASSWORD=$(echo $SUPABASE_URL | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
  
  export DB_POSTGRESDB_HOST=$SUPABASE_HOST
  export DB_POSTGRESDB_PORT=$SUPABASE_PORT
  export DB_POSTGRESDB_DATABASE=$SUPABASE_DATABASE
  export DB_POSTGRESDB_USER=$SUPABASE_USER
  export DB_POSTGRESDB_PASSWORD=$SUPABASE_PASSWORD
  export DB_POSTGRESDB_SSL_ENABLED=true
  export DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
fi

# Print environment variables for debugging
echo "Database settings:"
echo "DB_TYPE: $DB_TYPE"
echo "DB_POSTGRESDB_HOST: $DB_POSTGRESDB_HOST"
echo "DB_POSTGRESDB_PORT: $DB_POSTGRESDB_PORT"
echo "DB_POSTGRESDB_DATABASE: $DB_POSTGRESDB_DATABASE"
echo "N8N_PORT: $N8N_PORT"
echo "N8N startup script running..."

# Start n8n with its original entrypoint
exec /docker-entrypoint.sh
