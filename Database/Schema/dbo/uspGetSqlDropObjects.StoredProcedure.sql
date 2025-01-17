SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspGetSqlDropObjects]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Drop objects

	SELECT *
		FROM (
			SELECT 0 dropOrder, '' objectType, '' schemaName, '' objectName, '' objectParent, '' sqlCode WHERE 1=0
			UNION ALL SELECT 1, 'procedure', schema_name(schema_id), name, null, 'drop procedure [' + schema_name(schema_id) + '].[' + name + ']' FROM sys.procedures
			UNION ALL SELECT 2, 'constraint', schema_name(schema_id), name, object_name(parent_object_id), 'alter table [' + schema_name(schema_id) + '].[' + object_name( parent_object_id ) + '] drop constraint [' + name + ']' FROM sys.check_constraints
			UNION ALL SELECT 3, 'function', schema_name(schema_id), name, null, 'drop function [' + schema_name(schema_id) + '].[' + name + ']' FROM sys.objects WHERE TYPE IN ('FN','IF','TF','FS','FT')
			UNION ALL SELECT 4, 'view', schema_name(schema_id), name, null, 'drop view [' + schema_name(schema_id) + '].[' + name + ']' FROM sys.views
			UNION ALL SELECT 5, 'fkey', schema_name(schema_id), name, object_name(parent_object_id), 'alter table [' + schema_name(schema_id) + '].[' + object_name( parent_object_id ) + '] drop constraint [' + name + ']' FROM sys.foreign_keys
			UNION ALL SELECT 6, 'table', schema_name(schema_id), name, null, 'drop table [' + schema_name(schema_id) + '].[' + name + ']' FROM sys.tables
			UNION ALL SELECT 7, 'type', schema_name(schema_id), name, null, 'drop type [' + schema_name(schema_id) + '].[' + name + ']' FROM sys.types WHERE is_user_defined = 1
		) t
		ORDER BY 1, 2, 3, 4, 5, 6

END
GO
