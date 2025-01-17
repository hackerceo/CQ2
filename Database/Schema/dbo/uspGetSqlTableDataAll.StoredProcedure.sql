SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspGetSqlTableDataAll]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	declare @x table (i int identity(1,1), x xml)
	insert into @x(x) exec uspGetSqlTableData 'CRC','CODE_LOOKUP'
	insert into @x(x) exec uspGetSqlTableData 'CRC','CQ2_PARAMS'
	insert into @x(x) exec uspGetSqlTableData 'CRC','PDO_OUTPUT_SET_METADATA'
	insert into @x(x) exec uspGetSqlTableData 'CRC','QT_BREAKDOWN_PATH'
	insert into @x(x) exec uspGetSqlTableData 'CRC','QT_PRIVILEGE'
	insert into @x(x) exec uspGetSqlTableData 'CRC','QT_QUERY_RESULT_TYPE'
	insert into @x(x) exec uspGetSqlTableData 'CRC','QT_QUERY_STATUS_TYPE'
	insert into @x(x) exec uspGetSqlTableData 'HIVE','CRC_DB_LOOKUP'
	insert into @x(x) exec uspGetSqlTableData 'HIVE','ONT_DB_LOOKUP'
	insert into @x(x) exec uspGetSqlTableData 'HIVE','SERVICE_LOOKUP'
	insert into @x(x) exec uspGetSqlTableData 'HIVE','WORK_DB_LOOKUP'
	insert into @x(x) exec uspGetSqlTableData 'ONT','SCHEMES'
	insert into @x(x) exec uspGetSqlTableData 'ONT','TABLE_ACCESS'
	insert into @x(x) exec uspGetSqlTableData 'PM','PM_CELL_DATA'
	--insert into @x(x) exec uspGetSqlTableData 'PM','PM_CELL_PARAMS' -- has identity column
	insert into @x(x) exec uspGetSqlTableData 'PM','PM_HIVE_DATA'
	insert into @x(x) exec uspGetSqlTableData 'PM','PM_PROJECT_DATA'
	insert into @x(x) exec uspGetSqlTableData 'PM','PM_PROJECT_USER_ROLES'
	insert into @x(x) exec uspGetSqlTableData 'PM','PM_ROLE_REQUIREMENT'
	insert into @x(x) exec uspGetSqlTableData 'PM','PM_USER_DATA'
	insert into @x(x) exec uspGetSqlTableData 'WORK','WORKPLACE_ACCESS'
	select (select x.value('.','nvarchar(max)')+CHAR(10) from @x order by i for xml path(''), type) TableDataXML

END
GO
