-- Grant permissions to user _8f5cae57941ad7f3 for LMS database
-- This script grants INSERT, UPDATE, DELETE permissions on all tables

-- Grant all privileges on existing objects in public schema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "_8f5cae57941ad7f3";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "_8f5cae57941ad7f3";
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO "_8f5cae57941ad7f3";
GRANT USAGE ON SCHEMA public TO "_8f5cae57941ad7f3";

-- Grant privileges on future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "_8f5cae57941ad7f3";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "_8f5cae57941ad7f3";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO "_8f5cae57941ad7f3";

-- Specifically grant INSERT, UPDATE, DELETE on all existing tables (redundant but explicit)
DO $$
DECLARE
    table_record RECORD;
BEGIN
    FOR table_record IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'GRANT INSERT, UPDATE, DELETE, SELECT ON ' || quote_ident(table_record.tablename) || ' TO "_8f5cae57941ad7f3";';
        RAISE NOTICE 'Granted permissions on table: %', table_record.tablename;
    END LOOP;
END $$;

-- Grant sequence permissions for auto-increment fields
DO $$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT sequencename 
        FROM pg_sequences 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'GRANT USAGE, SELECT, UPDATE ON SEQUENCE ' || quote_ident(seq_record.sequencename) || ' TO "_8f5cae57941ad7f3";';
        RAISE NOTICE 'Granted sequence permissions on: %', seq_record.sequencename;
    END LOOP;
END $$;

COMMIT;