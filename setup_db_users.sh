#!/bin/bash

# PostgreSQL Database Users Setup Script
# This script reads database credentials from .env file and sets up roles and users

# Load environment variables from .env file
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
else
    echo "Error: .env file not found"
    exit 1
fi

# Extract database connection details from DATABASE_URL
# Format: postgresql://username:password@host:port/database?sslmode=require
if [ -z "$DATABASE_URL" ]; then
    echo "Error: DATABASE_URL not found in .env file"
    exit 1
fi

# Parse the DATABASE_URL
DB_URL_REGEX="postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/([^?]+)"
if [[ $DATABASE_URL =~ $DB_URL_REGEX ]]; then
    DB_USER="${BASH_REMATCH[1]}"
    DB_PASSWORD="${BASH_REMATCH[2]}"
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_NAME="${BASH_REMATCH[5]}"
else
    echo "Error: Invalid DATABASE_URL format"
    exit 1
fi

echo "Connecting to PostgreSQL database..."
echo "Host: $DB_HOST"
echo "Port: $DB_PORT"
echo "Database: $DB_NAME"
echo "User: $DB_USER"

# Set PGPASSWORD environment variable for psql
export PGPASSWORD="$DB_PASSWORD"

# Check if we can connect to the database
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "Error: Unable to connect to the database"
    exit 1
fi

echo "Connection successful!"

# Execute the SQL script
echo "Creating super admin user..."
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$(dirname "$0")/setup_db_users.sql"; then
    echo "Database super admin user setup completed successfully!"
else
    echo "Error: Failed to execute SQL script"
    exit 1
fi

# Clean up
unset PGPASSWORD

echo "Setup complete!"
echo ""
echo "Created super admin user:"
echo "  - lms_super_admin (full database access with superuser privileges)"
echo ""
echo "User can now connect to the database with full administrative privileges."