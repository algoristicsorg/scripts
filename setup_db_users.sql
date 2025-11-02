-- Database Super Admin User Setup Script for LMS
-- This script creates a single admin user with maximum available privileges

-- Create admin user with maximum privileges available to non-superuser
CREATE USER lms_super_admin WITH 
    PASSWORD '7Hn3Waterfall#qwe'
    CREATEDB
    INHERIT
    LOGIN;

-- Grant all privileges on existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lms_super_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lms_super_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO lms_super_admin;
GRANT ALL PRIVILEGES ON SCHEMA public TO lms_super_admin;

-- Grant privileges on future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO lms_super_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lms_super_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO lms_super_admin;

COMMIT;