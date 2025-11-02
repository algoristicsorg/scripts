-- Transfer ownership of all database objects to lms_super_admin

-- Grant lms_super_admin role to current user temporarily to allow ownership transfer
GRANT lms_super_admin TO CURRENT_USER;

-- Transfer ownership of all tables
DO $$
DECLARE
    table_record RECORD;
BEGIN
    FOR table_record IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident(table_record.tablename) || ' OWNER TO lms_super_admin;';
    END LOOP;
END $$;

-- Transfer ownership of all sequences
DO $$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT sequencename 
        FROM pg_sequences 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER SEQUENCE ' || quote_ident(seq_record.sequencename) || ' OWNER TO lms_super_admin;';
    END LOOP;
END $$;

-- Transfer ownership of all functions
DO $$
DECLARE
    func_record RECORD;
BEGIN
    FOR func_record IN 
        SELECT routine_name, specific_name
        FROM information_schema.routines 
        WHERE routine_schema = 'public' AND routine_type = 'FUNCTION'
    LOOP
        EXECUTE 'ALTER FUNCTION ' || func_record.specific_name || ' OWNER TO lms_super_admin;';
    END LOOP;
END $$;

-- Revoke the temporary grant
REVOKE lms_super_admin FROM CURRENT_USER;

COMMIT;