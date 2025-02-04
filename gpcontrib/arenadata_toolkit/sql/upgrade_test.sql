-- start_ignore
-- Prepare DB for the test
DROP FUNCTION IF EXISTS do_upgrade_test_for_arenadata_toolkit(TEXT);
DROP EXTERNAL TABLE IF EXISTS toolkit_versions;
DROP EXTENSION IF EXISTS arenadata_toolkit;
DROP SCHEMA IF EXISTS arenadata_toolkit CASCADE;
-- end_ignore

-- Change log level to disable notice messages from PL/pgSQL and dropped objects
-- from "DROP SCHEMA arenadata_toolkit CASCADE;"
SET client_min_messages=WARNING;

-- We have only first and last versions of arenadata_toolkit and scripts to update
-- it to intermediate versions.
-- At this test we will be use first version and upgrade scripts.
-- Field tablespace_location was added at version 1.4 of arenadata_toolkit
-- Function returns set of successful checks.
CREATE FUNCTION do_upgrade_test_for_arenadata_toolkit(from_version TEXT)
RETURNS setof TEXT
AS $$
BEGIN

-- Simple check: only create and alter extension:
	CREATE EXTENSION arenadata_toolkit VERSION '1.0';
	IF from_version != '1.0'
	THEN
		EXECUTE FORMAT($fmt$ALTER EXTENSION arenadata_toolkit
							UPDATE TO %1$I;$fmt$, from_version);
	END IF;
	ALTER EXTENSION arenadata_toolkit UPDATE;

-- Check the result
	IF (SELECT default_version = installed_version
		FROM pg_available_extensions
		WHERE name='arenadata_toolkit')
	THEN
		RETURN NEXT from_version || ': only alter check';
	END IF;

-- Cleanup before next step
	DROP EXTENSION arenadata_toolkit;
	DROP SCHEMA arenadata_toolkit CASCADE;

-- Create, adb_create_tables and alter extension:
	CREATE EXTENSION arenadata_toolkit VERSION '1.0';
	IF from_version != '1.0'
	THEN
		EXECUTE FORMAT($fmt$ALTER EXTENSION arenadata_toolkit
							UPDATE TO %1$I;$fmt$, from_version);
	END IF;
	PERFORM arenadata_toolkit.adb_create_tables();
	ALTER EXTENSION arenadata_toolkit UPDATE;

-- Check the result
	IF (SELECT default_version = installed_version
		FROM pg_available_extensions
		WHERE name='arenadata_toolkit')
	THEN
		RETURN NEXT from_version || ': alter and create_tables check';
	END IF;

-- Cleanup before next step
	DROP EXTENSION arenadata_toolkit;
	DROP SCHEMA arenadata_toolkit CASCADE;

-- Create, adb_create_tables, adb_collect_table_stats and alter extension:
	CREATE EXTENSION arenadata_toolkit VERSION '1.0';
	IF from_version != '1.0'
	THEN
		EXECUTE FORMAT($fmt$ALTER EXTENSION arenadata_toolkit
						UPDATE TO %1$I;$fmt$, from_version);
	END IF;
	PERFORM arenadata_toolkit.adb_create_tables();
	PERFORM arenadata_toolkit.adb_collect_table_stats();
	ALTER EXTENSION arenadata_toolkit UPDATE;

-- Check the result
	IF (SELECT default_version = installed_version
		FROM pg_available_extensions
		WHERE name='arenadata_toolkit')
	THEN
		RETURN NEXT from_version || ': alter, create_tables and collect_table_stats check';
	END IF;

-- Check field "tablespace_location" and table "db_files_history_backup_YYYYMMDDtHHMMSS"
-- which were added at version 1.4
	PERFORM arenadata_toolkit.adb_create_tables();

	IF 4 = (SELECT count(1)
			FROM (VALUES ('arenadata_toolkit.db_files_current'),
			             ('arenadata_toolkit.__db_files_current'),
			             ('arenadata_toolkit.__db_files_current_unmapped'),
			             ('arenadata_toolkit.db_files_history')) AS tables(relname)
			JOIN pg_attribute a ON a.attrelid = relname::regclass AND
			                       a.attname = 'tablespace_location')
	THEN
		RETURN NEXT from_version || ': column tablespace_location check';
	END IF;

-- Table "db_files_history_backup_YYYYMMDDtHHMMSS" must be created only if
-- from_version is less than 1.4
	IF EXISTS (SELECT
			   FROM pg_tables
			   WHERE schemaname='arenadata_toolkit' AND
			         tablename SIMILAR TO 'db_files_history_backup_[0-9]{8}t[0-9]{6}')
	THEN
		RETURN NEXT from_version || ': db_files_history_backup check';
	END IF;

-- Cleanup before next step
	DROP EXTENSION arenadata_toolkit;
	DROP SCHEMA arenadata_toolkit CASCADE;

-- Check create extension with the latest version after current was installed and dropped
	CREATE EXTENSION arenadata_toolkit VERSION '1.0';
	IF from_version != '1.0'
	THEN
		EXECUTE FORMAT($fmt$ALTER EXTENSION arenadata_toolkit
						UPDATE TO %1$I;$fmt$, from_version);
	END IF;
	PERFORM arenadata_toolkit.adb_create_tables();
	PERFORM arenadata_toolkit.adb_collect_table_stats();
	DROP EXTENSION arenadata_toolkit;

	CREATE EXTENSION arenadata_toolkit;
	PERFORM arenadata_toolkit.adb_create_tables();
	PERFORM arenadata_toolkit.adb_collect_table_stats();

-- Check the result
	IF (SELECT default_version = installed_version
		FROM pg_available_extensions
		WHERE name='arenadata_toolkit')
	THEN
		RETURN NEXT from_version || ': create the latest check';
	END IF;

-- Cleanup
	DROP EXTENSION arenadata_toolkit;
	DROP SCHEMA arenadata_toolkit CASCADE;

END$$
LANGUAGE plpgsql;

CREATE EXTERNAL WEB TABLE toolkit_versions(version text)
	execute
	E'find $(pg_config --sharedir) -name "arenadata_toolkit--*--*.sql" -type f -printf "%f\\n" \\
	 | grep -oP "arenadata_toolkit--(\\d+\\.\\d+)" | grep -oP "(\\d+\\.\\d+)"'
	on master format 'text';
SELECT do_upgrade_test_for_arenadata_toolkit(version)
FROM toolkit_versions
ORDER BY 1;

-- Cleanup
DROP FUNCTION do_upgrade_test_for_arenadata_toolkit(TEXT);
DROP EXTERNAL TABLE toolkit_versions;
RESET client_min_messages;
