SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunQueryInstance]
	@QueryInstanceID INT,
	@DomainID VARCHAR(50),
	@UserID VARCHAR(50),
	@ProjectID VARCHAR(50)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Set the status to indicate the query has started
	-- ***************************************************************************
	-- ***************************************************************************

	-- Set the Query Instance status to Incomplete
	UPDATE ..QT_QUERY_INSTANCE
		SET STATUS_TYPE_ID = 5, -- Incomplete
			START_DATE = GetDate()
		WHERE QUERY_INSTANCE_ID = @QueryInstanceID
		
		
	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Declare variables
	-- ***************************************************************************
	-- ***************************************************************************

	--------------------------------------------------------------------
	-- These variables are used only by this procedure
	--------------------------------------------------------------------

	DECLARE @uspRunQueryInstanceQM VARCHAR(100)
	DECLARE @uspRunQueryInstanceSubquery VARCHAR(100)
	DECLARE @uspRunQueryInstanceBreakdown VARCHAR(100)

	DECLARE @QueryMasterID INT
	DECLARE @QueryDefinition XML
	DECLARE @I2B2_Request_XML XML

	DECLARE @i INT
	DECLARE @MaxI INT

	DECLARE	@ReturnPatientCount BIT
	DECLARE @ReturnPatientList BIT
	DECLARE @ReturnEncounterCount BIT
	DECLARE @ReturnEncounterList BIT

	DECLARE @QueryMethod VARCHAR(100)
	DECLARE @SketchError FLOAT

	DECLARE @set_size INT
	DECLARE @real_set_size INT
	DECLARE @obfusc_method VARCHAR(500)

	DECLARE @result_type_id INT
	DECLARE @result_instance_id INT
	DECLARE @result_name VARCHAR(100)

	DECLARE @ResultOutputList TABLE (
		name VARCHAR(100),
		priority INT,
		result_type_id INT,
		description varchar(200),
		process_order INT
	)

	/*
	CREATE TABLE #ResultCounts (
		result_type_id INT,
		c_name VARCHAR(2000),
		c_facttablecolumn VARCHAR(50),
		c_tablename VARCHAR(50),
		c_columnname VARCHAR(50),
		c_columndatatype VARCHAR(50),
		c_operator VARCHAR(10),
		c_dimcode VARCHAR(700),
		process_order INT,
		result_count INT,
		actual_count INT
	)
	*/

	--------------------------------------------------------------------
	-- These temp tables are populated by ..uspRunQueryInstanceQM
	--------------------------------------------------------------------

	CREATE TABLE #GlobalQueryCounts (
		query_master_id int primary key,
		num_patients int,
		num_encounters bigint,
		num_instances bigint,
		num_facts bigint,
		sketch_e int,
		sketch_n int,
		sketch_q int,
		sketch_m int
	)

	CREATE TABLE #GlobalPatientList (
		query_master_id INT NOT NULL,
		patient_num INT NOT NULL,
	)
	ALTER TABLE #GlobalPatientList ADD PRIMARY KEY (query_master_id, patient_num)
	
	CREATE TABLE #GlobalEncounterList (
		query_master_id INT NOT NULL,
		encounter_num BIGINT NOT NULL,
		patient_num INT NOT NULL
	)
	ALTER TABLE #GlobalEncounterList ADD PRIMARY KEY (query_master_id, encounter_num)

	CREATE TABLE #GlobalInstanceList (
		query_master_id INT NOT NULL,
		encounter_num BIGINT NOT NULL,
		patient_num INT NOT NULL,
		concept_cd VARCHAR(50) NOT NULL,
		provider_id VARCHAR(50) NOT NULL,
		start_date DATETIME NOT NULL,
		instance_num INT NOT NULL
	)
	ALTER TABLE #GlobalInstanceList ADD PRIMARY KEY (query_master_id, encounter_num, patient_num, concept_cd, provider_id, start_date, instance_num)

	CREATE TABLE #GlobalSubqueryList (
		subquery_id INT IDENTITY(-1,-1) PRIMARY KEY,
		query_type VARCHAR(50),
		query_id VARCHAR(255),
		query_definition XML,
		num_patients INT
	)

	CREATE TABLE #GlobalSubqueryConstraintList (
		constraint_id INT IDENTITY(1,1) PRIMARY KEY,
		subquery_id1 INT,
		join_column1 VARCHAR(50),
		aggregate_operator1 VARCHAR(50),
		operator VARCHAR(50),
		subquery_id2 INT,
		join_column2 VARCHAR(50),
		aggregate_operator2 VARCHAR(50),
		span_operator1 VARCHAR(50),
		span_value1 INT,
		span_units1 VARCHAR(50),
		span_operator2 VARCHAR(50),
		span_value2 INT,
		span_units2 VARCHAR(50),
		constraint_sql NVARCHAR(MAX),
		num_patients INT
	)

	CREATE TABLE #GlobalTemporalList (
		subquery_id INT NOT NULL,
		patient_num INT NOT NULL,
		is_start BIT NOT NULL,
		the_date DATETIME NOT NULL
	)
	ALTER TABLE #GlobalTemporalList ADD PRIMARY KEY (subquery_id, patient_num, is_start, the_date)

	CREATE TABLE #GlobalBreakdownCounts (
		breakdown_id INT IDENTITY(1,1) PRIMARY KEY,
		column_name VARCHAR(100),
		real_size INT,
		set_size INT
	)

	CREATE TABLE #GlobalResultPatientList (
		patient_num INT PRIMARY KEY
	)

	-- Get schema based procedure names
	SELECT @uspRunQueryInstanceQM = OBJECT_SCHEMA_NAME(@@PROCID)+'.uspRunQueryInstanceQM'
	SELECT @uspRunQueryInstanceSubquery = OBJECT_SCHEMA_NAME(@@PROCID)+'.uspRunQueryInstanceSubquery'
	SELECT @uspRunQueryInstanceBreakdown = OBJECT_SCHEMA_NAME(@@PROCID)+'.uspRunQueryInstanceBreakdown'


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Run the query
	-- ***************************************************************************
	-- ***************************************************************************

	-- Check for security
	IF HIVE.fnHasUserRole(@ProjectID,@UserID,'DATA_OBFSC') = 0
	BEGIN
		-- TODO: Add error handling
		RETURN
	END

	-- Get Query Master data
	SELECT	@QueryMasterID = m.QUERY_MASTER_ID,
			@QueryDefinition = m.REQUEST_XML,
			@I2B2_Request_XML = m.I2B2_REQUEST_XML
		FROM ..QT_QUERY_MASTER m, ..QT_QUERY_INSTANCE i
		WHERE m.QUERY_MASTER_ID = i.QUERY_MASTER_ID 
			AND i.QUERY_INSTANCE_ID = @QueryInstanceID

	-- Determine the query method
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as ns6,
		'http://www.i2b2.org/xsd/cell/crc/psm/1.1/' as ns4
	)
	SELECT @QueryMethod = @I2B2_Request_XML.value('ns6:request[1]/message_body[1]/ns4:psmheader[1]/query_method[1]','varchar(100)')

	-- Get any subquery constraints
	EXEC @uspRunQueryInstanceSubquery
		@QueryMasterID = @QueryMasterID,
		@DomainID = @DomainID,
		@UserID = @UserID,
		@ProjectID = @ProjectID,
		@GetConstraints = 1,
		@QueryDefinition = @QueryDefinition

	-- Change master_type_cd if needed
	IF EXISTS (SELECT * FROM #GlobalSubqueryConstraintList)
		UPDATE ..QT_QUERY_MASTER
			SET MASTER_TYPE_CD = 'TEMPORAL'
			WHERE QUERY_MASTER_ID = @QueryMasterID

	/*
	SELECT * FROM #GlobalSubqueryList
	SELECT * FROM #GlobalSubqueryConstraintList
	SELECT * FROM #GlobalTemporalList
	SELECT * FROM #GlobalQueryCounts
	*/

	-- Get the Result Output List
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as ns6,
		'http://www.i2b2.org/xsd/cell/crc/psm/1.1/' as ns4
	), RequestList as (
		SELECT x.value('@name','varchar(100)') name, x.value('@priority_index','int') priority
			FROM @I2B2_Request_XML.nodes('//ns6:request[1]/message_body[1]/ns4:request[1]/result_output_list[1]/result_output') AS R(x)
	), TypeList as (
		SELECT name, MIN(result_type_id) result_type_id
			FROM ..QT_QUERY_RESULT_TYPE
			GROUP BY name
	)
	INSERT INTO @ResultOutputList (name, priority, result_type_id, description, process_order)
		SELECT s.name, r.priority, s.result_type_id, s.description,
				ROW_NUMBER() OVER (ORDER BY r.priority, s.name)
			FROM RequestList r, TypeList t, ..QT_QUERY_RESULT_TYPE s
			WHERE r.name = t.name AND t.result_type_id = s.result_type_id

	IF NOT EXISTS (SELECT * FROM @ResultOutputList)
		INSERT INTO @ResultOutputList (name, priority, result_type_id, description, process_order)
			SELECT name, 15, result_type_id, description, 1
				FROM ..QT_QUERY_RESULT_TYPE
				WHERE name = 'PATIENT_COUNT_XML' -- result_type_id = 4

	-- Determine what type of data are needed
	SELECT 
		@ReturnPatientCount = 0,
		@ReturnPatientList = 0,
		@ReturnEncounterCount = 0,
		@ReturnEncounterList = 0
	IF EXISTS (SELECT * FROM @ResultOutputList WHERE name IN ('PATIENT_COUNT_XML')) --result_type_id in (4)
		SELECT @ReturnPatientCount = 1
	IF EXISTS (SELECT * FROM @ResultOutputList WHERE name NOT IN ('PATIENT_ENCOUNTER_SET','XML','PATIENT_COUNT_XML')) --result_type_id = 1 OR result_type_id > 4
		SELECT @ReturnPatientList = 1
	IF EXISTS (SELECT * FROM @ResultOutputList WHERE name IN ('PATIENT_ENCOUNTER_SET')) --result_type_id in (2)
		SELECT @ReturnEncounterCount = 1, @ReturnEncounterList = 1
	IF EXISTS (SELECT * FROM #GlobalSubqueryConstraintList)
		SELECT @ReturnPatientList = 1, @ReturnEncounterList = (CASE WHEN @ReturnEncounterCount = 1 OR @ReturnEncounterList = 1 THEN 1 ELSE 0 END)

	-- Run the query master
	EXEC @uspRunQueryInstanceQM
		@QueryMasterID = @QueryMasterID,
		@DomainID = @DomainID,
		@UserID = @UserID,
		@ProjectID = @ProjectID,
		@ReturnPatientCount = @ReturnPatientCount,
		@ReturnPatientList = @ReturnPatientList,
		@ReturnEncounterCount = @ReturnEncounterCount,
		@ReturnEncounterList = @ReturnEncounterList,
		@QueryMethod = @QueryMethod

	-- Apply any subquery constraints
	IF EXISTS (SELECT * FROM #GlobalSubqueryConstraintList WHERE 1=1)
		EXEC @uspRunQueryInstanceSubquery
			@QueryMasterID = @QueryMasterID,
			@DomainID = @DomainID,
			@UserID = @UserID,
			@ProjectID = @ProjectID
		
	/*
	SELECT * FROM #GlobalSubqueryList
	SELECT * FROM #GlobalSubqueryConstraintList
	SELECT * FROM #GlobalTemporalList
	SELECT * FROM #GlobalQueryCounts
	*/

	-- Get the real number of patients
	SELECT @real_set_size = num_patients
		FROM #GlobalQueryCounts
		WHERE query_master_id = @QueryMasterID

	-- Switch to EXACT query method if no sketch information was returned
	SELECT @QueryMethod = 'EXACT'
		FROM #GlobalQueryCounts
		WHERE query_master_id = @QueryMasterID AND sketch_n IS NULL
	--insert into x(d,s) select GetDate(), @QueryMethod

	-- Determine the obfuscation method
	SELECT @obfusc_method = 'OBSUBTOTAL'
	-- Not DATA_OBFSC
	IF HIVE.fnHasUserRole(@ProjectID,@UserID,'DATA_AGG') = 1
		SELECT @obfusc_method = NULL
		
	-- Determine the number of patients that will be reported (obfuscating if needed)	
	IF @obfusc_method IS NULL
		SELECT @set_size = @real_set_size
	ELSE
		SELECT @set_size = (CASE WHEN @real_set_size < 3 THEN 0 ELSE @real_set_size + FLOOR(RAND()*7) - 3 END)

	IF EXISTS (SELECT * FROM @ResultOutputList WHERE [name] IN (SELECT [NAME] FROM ..QT_BREAKDOWN_PATH))
	BEGIN
		INSERT INTO #GlobalResultPatientList WITH (TABLOCK)
			SELECT patient_num
			FROM #GlobalPatientList 
			WHERE query_master_id = @QueryMasterID
	END
	
	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Generate result sets
	-- ***************************************************************************
	-- ***************************************************************************

	-- Loop through result output list
	SELECT @i = 1, @MaxI = IsNull((SELECT MAX(process_order) FROM @ResultOutputList),0)
	WHILE @i <= @MaxI
	BEGIN
		-- Get the result_type_id
		SELECT @result_type_id = result_type_id, @result_name = name
			FROM @ResultOutputList
			WHERE process_order = @i
		-- Create the result instance, set status to processing
		INSERT INTO ..QT_QUERY_RESULT_INSTANCE (QUERY_INSTANCE_ID, RESULT_TYPE_ID, START_DATE, STATUS_TYPE_ID, DELETE_FLAG, DESCRIPTION)
			SELECT	i.QUERY_INSTANCE_ID,
					t.RESULT_TYPE_ID,
					GetDate(),
					2, -- Processing
					'A',
					t.DESCRIPTION + ' for "' + m.NAME + '"'
				FROM ..QT_QUERY_INSTANCE i, ..QT_QUERY_MASTER m, ..QT_QUERY_RESULT_TYPE t
				WHERE i.QUERY_INSTANCE_ID = @QueryInstanceID
					AND i.QUERY_MASTER_ID = m.QUERY_MASTER_ID
					AND t.RESULT_TYPE_ID = @result_type_id
		-- Get the new result_instance_id
		SELECT @result_instance_id = @@IDENTITY
		-- Process the Result Instance	
		IF @result_name in ('PATIENTSET')
		BEGIN
			INSERT INTO ..QT_PATIENT_SET_COLLECTION (RESULT_INSTANCE_ID, PATIENT_NUM)
				SELECT @result_instance_id, patient_num
					FROM #GlobalPatientList 
					WHERE query_master_id = @QueryMasterID
			--INSERT INTO AnotherDatabase.CRC.QT_PATIENT_SET_COLLECTION (RESULT_INSTANCE_ID, PATIENT_NUM)
			--	SELECT TOP 32768 @result_instance_id, patient_num
			--		FROM #GlobalPatientList 
			--		WHERE query_master_id = @QueryMasterID
		END
		IF @result_name in ('PATIENT_ENCOUNTER_SET')
		BEGIN
			INSERT INTO ..QT_PATIENT_ENC_COLLECTION (RESULT_INSTANCE_ID, PATIENT_NUM, ENCOUNTER_NUM)
				SELECT @result_instance_id, patient_num, encounter_num
					FROM #GlobalEncounterList 
					WHERE query_master_id = @QueryMasterID
			--INSERT INTO AnotherDatabase.CRC.QT_PATIENT_ENC_COLLECTION (RESULT_INSTANCE_ID, PATIENT_NUM, ENCOUNTER_NUM)
			--	SELECT TOP 32768 @result_instance_id, patient_num, encounter_num
			--		FROM #GlobalEncounterList 
			--		WHERE query_master_id = @QueryMasterID
		END
		IF (@result_name in ('PATIENT_COUNT_XML')) OR (EXISTS (SELECT * FROM ..QT_BREAKDOWN_PATH WHERE NAME = @result_name)) --BREAKDOWNS
		BEGIN
			TRUNCATE TABLE #GlobalBreakdownCounts
			SELECT @SketchError = 0
			IF @result_name in ('PATIENT_COUNT_XML')
			BEGIN
				INSERT INTO #GlobalBreakdownCounts(column_name,real_size,set_size)
					SELECT 'patient_count', @real_set_size, @set_size
				IF @QueryMethod IN ('MINHASH8','MINHASH15')
				BEGIN
					DELETE
						FROM CRC.QT_QUERY_RESULT_SKETCH
						WHERE RESULT_INSTANCE_ID = @result_instance_id
					INSERT INTO CRC.QT_QUERY_RESULT_SKETCH (RESULT_INSTANCE_ID, SKETCH_SIZE, ORIG_SIZE, FILTERED_SIZE, ORIG_ESTIMATE, FILTERED_ESTIMATE, ERROR_RELATIVE, ERROR_ABSOLUTE)
						SELECT @result_instance_id, sketch_m, sketch_n, sketch_q, sketch_e, num_patients, ERROR_RELATIVE, ERROR_ABSOLUTE
						FROM #GlobalQueryCounts g
							CROSS APPLY (SELECT CAST(sketch_n AS FLOAT) n, CAST(sketch_q AS FLOAT) q, CAST(sketch_e AS FLOAT) e, CAST(sketch_m AS FLOAT) m) f
							CROSS APPLY (
									SELECT (CASE WHEN n=0 THEN NULL ELSE 1/SQRT(n) END) Rc,
										(CASE WHEN q=0 or e=0 THEN NULL ELSE SQRT(n/(n-1))*SQRT((1/q)-(1/n))*SQRT(1-(n/m)) END) Rq
								) rx
							CROSS APPLY (
									SELECT (CASE WHEN Rc IS NULL OR Rq IS NULL THEN NULL ELSE 1.96*SQRT(Rc*Rc+Rq*Rq+Rc*Rc*Rq*Rq) END) R
								) r
							CROSS APPLY (
									SELECT (CASE WHEN n=0 or q=0 or e=0 or R IS NULL THEN 0 ELSE R END) ERROR_RELATIVE,
										(CASE WHEN n=0 THEN 0 WHEN q=0 or e=0 or R IS NULL THEN 3 ELSE R*num_patients END) ERROR_ABSOLUTE
								) e
						WHERE query_master_id = @QueryMasterID
					SELECT @SketchError = ERROR_RELATIVE
						FROM CRC.QT_QUERY_RESULT_SKETCH
						WHERE result_instance_id = @result_instance_id
				END
			END
			ELSE --BREAKDOWNS
			BEGIN
				-- Get the breakdown counts
				EXEC @uspRunQueryInstanceBreakdown
					@QueryMasterID = @QueryMasterID,
					@DomainID = @DomainID,
					@UserID = @UserID,
					@ProjectID = @ProjectID,
					@BreakdownName = @result_name
				-- Estimate
				IF @QueryMethod IN ('MINHASH8','MINHASH15')
				BEGIN
					DECLARE @SampledPatients INT
					SELECT @SampledPatients = COUNT(*) FROM #GlobalPatientList WHERE query_master_id=@QueryMasterID
					IF @SampledPatients>0
						UPDATE #GlobalBreakdownCounts
							SET real_size = FLOOR(@real_set_size * (real_size/CAST(@SampledPatients as float)) + 0.5)
				END
				-- Obfuscate the result if needed
				UPDATE #GlobalBreakdownCounts
					SET set_size = 
						(CASE WHEN @obfusc_method IS NULL THEN real_size
							ELSE real_size + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*7) - 3
							END)
				UPDATE #GlobalBreakdownCounts
					SET set_size = 0
					WHERE (real_size < 3 or set_size < 3)
						AND @obfusc_method IS NOT NULL
			END
			-- Create the XML Result
			INSERT INTO ..QT_XML_RESULT (RESULT_INSTANCE_ID, XML_VALUE)
				SELECT @result_instance_id,
					'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
					+'<ns10:i2b2_result_envelope xmlns:ns2="http://www.i2b2.org/xsd/hive/pdo/1.1/" xmlns:ns4="http://www.i2b2.org/xsd/cell/crc/psm/1.1/" xmlns:ns3="http://www.i2b2.org/xsd/cell/crc/pdo/1.1/" xmlns:ns9="http://www.i2b2.org/xsd/cell/ont/1.1/" xmlns:ns5="http://www.i2b2.org/xsd/hive/msg/1.1/" xmlns:ns6="http://www.i2b2.org/xsd/cell/crc/psm/querydefinition/1.1/" xmlns:ns10="http://www.i2b2.org/xsd/hive/msg/result/1.1/" xmlns:ns7="http://www.i2b2.org/xsd/cell/crc/psm/analysisdefinition/1.1/" xmlns:ns8="http://www.i2b2.org/xsd/cell/pm/1.1/">'
					+'<body>'
					+'<ns10:result name="'+REPLACE(@result_name,'''','''''')+'">'
					+CAST((
						SELECT 'int' "data/@type",
							column_name "data/@column",
							format(set_size,'N0')+(case when @SketchError>0 then ' &plusmn; '+format(@SketchError*100,'N2')+'%' else '' end) "data/@display",
							(CASE @QueryMethod
								WHEN 'MINHASH15' THEN 'Accurate Estimate'
								WHEN 'MINHASH8' THEN 'Fast Estimate'
								ELSE NULL END) "data/@comment",
							set_size "data"
						FROM #GlobalBreakdownCounts
						FOR XML PATH(''), TYPE
						) AS VARCHAR(MAX))
					+'</ns10:result>'
					+'</body>'
					+'</ns10:i2b2_result_envelope>'
		END
		-- Set the Result Instance status to finished
		UPDATE ..QT_QUERY_RESULT_INSTANCE
			SET	SET_SIZE = @set_size,
				REAL_SET_SIZE = @real_set_size,
				OBFUSC_METHOD = (case when @QueryMethod IN ('MINHASH8','MINHASH15') then 'SAMPLING' else @obfusc_method end),
				END_DATE = GetDate(),
				STATUS_TYPE_ID = 3 -- Finished
			WHERE RESULT_INSTANCE_ID = @result_instance_id
		-- Move to the next result output
		SELECT @i = @i + 1
	END

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Change status of Query Instance
	-- ***************************************************************************
	-- ***************************************************************************

	UPDATE ..QT_QUERY_INSTANCE
		SET	END_DATE = GetDate(),
			STATUS_TYPE_ID = 6 -- Completed
		WHERE QUERY_INSTANCE_ID = @QueryInstanceID

END
GO
