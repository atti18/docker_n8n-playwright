#!/bin/sh

# Map Cloud Run's PORT to N8N_PORT if it exists
if [ -n "$PORT" ]; then
  export N8N_PORT=$PORT
fi

# Use SQLite as default database (no external database required)
# Supabase will be used only as a workflow node, not for n8n's internal database
export DB_TYPE=sqlite

# Print environment variables for debugging
echo "Database settings:"
echo "DB_TYPE: $DB_TYPE"
echo "N8N_PORT: $N8N_PORT"
echo "N8N startup script running..."

# Start n8n with its original entrypoint
exec /docker-entrypoint.sh
