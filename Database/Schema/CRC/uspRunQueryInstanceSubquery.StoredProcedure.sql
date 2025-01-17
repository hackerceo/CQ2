SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunQueryInstanceSubquery]
	@QueryMasterID INT,
	@DomainID VARCHAR(50),
	@UserID VARCHAR(50),
	@ProjectID VARCHAR(50),
	@GetConstraints BIT = 0,
	@QueryDefinition XML = NULL
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	------------------------------------------------------------------------------
	-- Declare variables
	------------------------------------------------------------------------------

	DECLARE @QueryStartTime DATETIME
	SELECT @QueryStartTime = GETDATE()

	DECLARE @Schema VARCHAR(100)

	-- Get the schema
	SELECT @Schema = OBJECT_SCHEMA_NAME(@@PROCID)
	--SELECT @Schema = OBJECT_SCHEMA_NAME(187147712, DB_ID ( 'i2b2_demo' ) )
	DECLARE @uspRunQueryInstanceQM VARCHAR(100)
	SELECT @uspRunQueryInstanceQM = @Schema+'.uspRunQueryInstanceQM'


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Parse subquery constraints from query definition, then exit proc
	-- ***************************************************************************
	-- ***************************************************************************

	IF @GetConstraints = 1
	BEGIN

		-- Get subquery data
		INSERT INTO #GlobalSubqueryList(query_type,query_id,query_definition)
			SELECT x.value('subquery[1]/query_type[1]','VARCHAR(MAX)'), x.value('subquery[1]/query_id[1]','VARCHAR(MAX)'), x
			FROM (
				SELECT x.query('.') x
				FROM @QueryDefinition.nodes('query_definition[1]/subquery') AS R(x)
			) t

		-- Get subquery constraints
		INSERT INTO #GlobalSubqueryConstraintList (
				subquery_id1,join_column1,aggregate_operator1,
				operator,
				subquery_id2,join_column2,aggregate_operator2,
				span_operator1,span_value1,span_units1,
				span_operator2,span_value2,span_units2
			)
		SELECT	(SELECT subquery_id FROM #GlobalSubqueryList WHERE query_id = x.value('first_query[1]/query_id[1]','VARCHAR(MAX)')),
				x.value('first_query[1]/join_column[1]','VARCHAR(MAX)'),
				x.value('first_query[1]/aggregate_operator[1]','VARCHAR(MAX)'),
				x.value('operator[1]','VARCHAR(MAX)'),
				(SELECT subquery_id FROM #GlobalSubqueryList WHERE query_id = x.value('second_query[1]/query_id[1]','VARCHAR(MAX)')),
				x.value('second_query[1]/join_column[1]','VARCHAR(MAX)'),
				x.value('second_query[1]/aggregate_operator[1]','VARCHAR(MAX)'),
				x.value('span[1]/operator[1]','VARCHAR(MAX)'),
				x.value('span[1]/span_value[1]','INT'),
				x.value('span[1]/units[1]','VARCHAR(MAX)'),
				x.value('span[2]/operator[1]','VARCHAR(MAX)'),
				x.value('span[2]/span_value[1]','INT'),
				x.value('span[2]/units[1]','VARCHAR(MAX)')
		FROM (
			SELECT x.query('./*') x
			FROM @QueryDefinition.nodes('query_definition[1]/subquery_constraint') AS R(x)
		) t

		-- Validate subquery constraints
		DELETE 
			FROM #GlobalSubqueryConstraintList
			WHERE (subquery_id1 IS NULL) OR (ISNULL(join_column1,'') NOT IN ('STARTDATE','ENDDATE')) OR (ISNULL(aggregate_operator1,'') NOT IN ('FIRST','LAST','ANY'))
				OR (subquery_id2 IS NULL) OR (ISNULL(join_column2,'') NOT IN ('STARTDATE','ENDDATE')) OR (ISNULL(aggregate_operator2,'') NOT IN ('FIRST','LAST','ANY'))
				OR (ISNULL(operator,'') NOT IN ('LESS','LESSEQUAL','EQUAL','GREATEREQUAL','GREATER'))
		UPDATE #GlobalSubqueryConstraintList
			SET span_operator1 = NULL
			WHERE (ISNULL(span_operator1,'') NOT IN ('LESS','LESSEQUAL','EQUAL','GREATEREQUAL','GREATER'))
				OR (span_value1 IS NULL)
				OR (ISNULL(span_units1,'') NOT IN ('HOUR','DAY','MONTH','YEAR'))
		UPDATE #GlobalSubqueryConstraintList
			SET span_operator2 = NULL
			WHERE (ISNULL(span_operator2,'') NOT IN ('LESS','LESSEQUAL','EQUAL','GREATEREQUAL','GREATER'))
				OR (span_value2 IS NULL)
				OR (ISNULL(span_units2,'') NOT IN ('HOUR','DAY','MONTH','YEAR'))
		UPDATE #GlobalSubqueryConstraintList
			SET	operator = (CASE operator WHEN 'LESS' THEN '<' WHEN 'LESSEQUAL' THEN '<=' WHEN 'EQUAL' THEN '=' WHEN 'GREATEREQUAL' THEN '>=' WHEN 'GREATER' THEN '>' ELSE NULL END),
				span_operator1 = (CASE span_operator1 WHEN 'LESS' THEN '<' WHEN 'LESSEQUAL' THEN '<=' WHEN 'EQUAL' THEN '=' WHEN 'GREATEREQUAL' THEN '>=' WHEN 'GREATER' THEN '>' ELSE NULL END),
				span_operator2 = (CASE span_operator2 WHEN 'LESS' THEN '<' WHEN 'LESSEQUAL' THEN '<=' WHEN 'EQUAL' THEN '=' WHEN 'GREATEREQUAL' THEN '>=' WHEN 'GREATER' THEN '>' ELSE NULL END),
				span_units1 = (CASE span_units1 WHEN 'HOUR' THEN 'hh' WHEN 'DAY' THEN 'dd' WHEN 'MONTH' THEN 'mm' WHEN 'YEAR' THEN 'yy' ELSE NULL END),
				span_units2 = (CASE span_units2 WHEN 'HOUR' THEN 'hh' WHEN 'DAY' THEN 'dd' WHEN 'MONTH' THEN 'mm' WHEN 'YEAR' THEN 'yy' ELSE NULL END)

		-- Join each subquery to the initial results of the main query definition
		UPDATE a
			SET a.query_definition = (
				SELECT
					query_definition.query('subquery[1]/*'),
					CAST('<panel>
								<panel_number>-1</panel_number>
								<panel_accuracy_scale>100</panel_accuracy_scale>
								<invert>0</invert>
								<panel_timing>ANY</panel_timing>
								<total_item_occurrences>1</total_item_occurrences>
								<item>
									<item_key>masterid:'+CAST(@QueryMasterID AS VARCHAR(50))+'</item_key>
								</item>
							</panel>' AS XML)
				FROM #GlobalSubqueryList b
				WHERE a.subquery_id = b.subquery_id
				FOR XML PATH('query_definition'), TYPE
			)
			FROM #GlobalSubqueryList a

		-- Exit the proc
		RETURN

	END

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Apply the subquery constraints
	-- ***************************************************************************
	-- ***************************************************************************

	------------------------------------------------------------------------------
	-- Declare variables
	------------------------------------------------------------------------------

	DECLARE @subquery_id INT
	DECLARE @ReturnTemporalListStart VARCHAR(50)
	DECLARE @ReturnTemporalListEnd VARCHAR(50)

	DECLARE @i INT
	DECLARE @MaxI INT

	DECLARE @sql NVARCHAR(MAX)

	CREATE TABLE #ConstraintPatient (
		constraint_id INT NOT NULL,
		patient_num INT NOT NULL
	)

	CREATE TABLE #CombinedConstraintPatient (
		patient_num INT NOT NULL
	)

	------------------------------------------------------------------------------
	-- Run each subquery
	------------------------------------------------------------------------------

	SELECT @MaxI = ISNULL((SELECT MIN(subquery_id) FROM #GlobalSubqueryList),0)
	SELECT @i = -1
	WHILE (@i >= @MaxI)
	BEGIN
		IF EXISTS (SELECT * FROM #GlobalSubqueryConstraintList WHERE subquery_id1 = @i OR subquery_id2 = @i)
		BEGIN
			-- Determine if start/end and first/any/last dates need to be returned
			SELECT @ReturnTemporalListStart = NULL, @ReturnTemporalListEnd = NULL
			;WITH a AS (
				SELECT	MAX(CASE WHEN (subquery_id1 = @i AND join_column1 = 'STARTDATE' AND aggregate_operator1 = 'ANY')
									OR (subquery_id2 = @i AND join_column2 = 'STARTDATE' AND aggregate_operator2 = 'ANY')
									THEN 1 ELSE 0 END) Start_Any,
						MAX(CASE WHEN (subquery_id1 = @i AND join_column1 = 'STARTDATE' AND aggregate_operator1 = 'FIRST')
									OR (subquery_id2 = @i AND join_column2 = 'STARTDATE' AND aggregate_operator2 = 'FIRST')
									THEN 1 ELSE 0 END) Start_First,
						MAX(CASE WHEN (subquery_id1 = @i AND join_column1 = 'STARTDATE' AND aggregate_operator1 = 'LAST')
									OR (subquery_id2 = @i AND join_column2 = 'STARTDATE' AND aggregate_operator2 = 'LAST')
									THEN 1 ELSE 0 END) Start_Last,
						MAX(CASE WHEN (subquery_id1 = @i AND join_column1 = 'ENDDATE' AND aggregate_operator1 = 'ANY')
									OR (subquery_id2 = @i AND join_column2 = 'ENDDATE' AND aggregate_operator2 = 'ANY')
									THEN 1 ELSE 0 END) End_Any,
						MAX(CASE WHEN (subquery_id1 = @i AND join_column1 = 'ENDDATE' AND aggregate_operator1 = 'FIRST')
									OR (subquery_id2 = @i AND join_column2 = 'ENDDATE' AND aggregate_operator2 = 'FIRST')
									THEN 1 ELSE 0 END) End_First,
						MAX(CASE WHEN (subquery_id1 = @i AND join_column1 = 'ENDDATE' AND aggregate_operator1 = 'LAST')
									OR (subquery_id2 = @i AND join_column2 = 'ENDDATE' AND aggregate_operator2 = 'LAST')
									THEN 1 ELSE 0 END) End_Last
					FROM #GlobalSubqueryConstraintList
			)
			SELECT	@ReturnTemporalListStart =
						(CASE	WHEN Start_Any = 1 THEN 'ANY'
								WHEN Start_First + Start_Last > 1 THEN 'ANY'
								WHEN Start_First > 0 THEN 'FIRST'
								WHEN Start_Last > 0 THEN 'LAST'
								END),
					@ReturnTemporalListEnd =
						(CASE	WHEN End_Any = 1 THEN 'ANY'
								WHEN End_First + End_Last > 1 THEN 'ANY'
								WHEN End_First > 0 THEN 'FIRST'
								WHEN End_Last > 0 THEN 'LAST'
								END)
				FROM a

			-- Run the subquery
			EXEC @uspRunQueryInstanceQM
				@QueryMasterID = @i,
				@DomainID = @DomainID,
				@UserID = @UserID,
				@ProjectID = @ProjectID,
				@ReturnTemporalListStart = @ReturnTemporalListStart,
				@ReturnTemporalListEnd = @ReturnTemporalListEnd
				
		END
		SELECT @i = @i - 1
	END

	------------------------------------------------------------------------------
	-- Determine the patients who pass each constraint
	------------------------------------------------------------------------------

	SELECT @MaxI = ISNULL((SELECT MAX(constraint_id) FROM #GlobalSubqueryConstraintList),0)
	SELECT @i = 1
	WHILE (@i <= @MaxI)
	BEGIN
		SELECT @SQL = 
			';WITH a AS ('
			+'SELECT patient_num, '
			+(CASE aggregate_operator1 WHEN 'FIRST' THEN 'MIN(the_date)' WHEN 'LAST' THEN 'MAX(the_date)' ELSE '' END)
			+' the_date '
			+' FROM #GlobalTemporalList '
			+' WHERE subquery_id = '+CAST(subquery_id1 AS VARCHAR(50))
			+' AND is_start = '+(CASE WHEN join_column1 = 'STARTDATE' THEN '1' ELSE '0' END)
			+(CASE aggregate_operator1 WHEN 'ANY' THEN '' ELSE ' GROUP BY patient_num ' END)
			+'), b AS ('
			+'SELECT patient_num, '
			+(CASE aggregate_operator2 WHEN 'FIRST' THEN 'MIN(the_date)' WHEN 'LAST' THEN 'MAX(the_date)' ELSE '' END)
			+' the_date '
			+' FROM #GlobalTemporalList '
			+' WHERE subquery_id = '+CAST(subquery_id2 AS VARCHAR(50))
			+' AND is_start = '+(CASE WHEN join_column2 = 'STARTDATE' THEN '1' ELSE '0' END)
			+(CASE aggregate_operator2 WHEN 'ANY' THEN '' ELSE ' GROUP BY patient_num ' END)
			+')'
			+'INSERT INTO #ConstraintPatient(constraint_id,patient_num) '
			+' SELECT DISTINCT '+CAST(constraint_id AS VARCHAR(50))+', a.patient_num '
			+' FROM a INNER JOIN b ON a.patient_num = b.patient_num '
			+' WHERE a.the_date '+operator+' b.the_date'
			+(CASE	WHEN span_operator1 IS NOT NULL AND operator IN ('<','<=','=')
					THEN ' AND DATEDIFF('+span_units1+',a.the_date,b.the_date) '+span_operator1+' '+CAST(span_value1 AS VARCHAR(50))
					WHEN span_operator1 IS NOT NULL AND operator IN ('>','>=')
					THEN ' AND DATEDIFF('+span_units1+',b.the_date,a.the_date) '+span_operator1+' '+CAST(span_value1 AS VARCHAR(50))
					ELSE '' END)
			+(CASE	WHEN span_operator2 IS NOT NULL AND operator IN ('<','<=','=')
					THEN ' AND DATEDIFF('+span_units2+',a.the_date,b.the_date) '+span_operator2+' '+CAST(span_value2 AS VARCHAR(50))
					WHEN span_operator2 IS NOT NULL AND operator IN ('>','>=')
					THEN ' AND DATEDIFF('+span_units2+',b.the_date,a.the_date) '+span_operator2+' '+CAST(span_value2 AS VARCHAR(50))
					ELSE '' END)
			FROM #GlobalSubqueryConstraintList
			WHERE constraint_id = @i

		EXEC sp_executesql @sql

		UPDATE #GlobalSubqueryConstraintList
			SET constraint_sql = @sql, num_patients = @@ROWCOUNT
			WHERE constraint_id = @i

		SELECT @i = @i + 1
	END

	------------------------------------------------------------------------------
	-- Get patients who pass all constraints
	------------------------------------------------------------------------------

	INSERT INTO #CombinedConstraintPatient
		SELECT patient_num
		FROM #ConstraintPatient
		GROUP BY patient_num
		HAVING COUNT(*) = @MaxI

	ALTER TABLE #CombinedConstraintPatient ADD PRIMARY KEY (patient_num)

	------------------------------------------------------------------------------
	-- Delete patients who do not pass all constraints
	------------------------------------------------------------------------------

	DELETE FROM #GlobalPatientList WHERE query_master_id = @QueryMasterID AND patient_num NOT IN (SELECT patient_num FROM #CombinedConstraintPatient)
	DELETE FROM #GlobalEncounterList WHERE query_master_id = @QueryMasterID AND patient_num NOT IN (SELECT patient_num FROM #CombinedConstraintPatient)
	DELETE FROM #GlobalInstanceList WHERE query_master_id = @QueryMasterID AND patient_num NOT IN (SELECT patient_num FROM #CombinedConstraintPatient)

	UPDATE #GlobalQueryCounts
		SET	num_patients = (SELECT COUNT(*) FROM #GlobalPatientList WHERE query_master_id = @QueryMasterID),
			num_encounters = (SELECT COUNT(*) FROM #GlobalEncounterList WHERE query_master_id = @QueryMasterID),
			num_instances = (SELECT COUNT(*) FROM #GlobalInstanceList WHERE query_master_id = @QueryMasterID)
		WHERE query_master_id = @QueryMasterID


	-- SELECT * FROM #CombinedConstraintPatient

END
GO
