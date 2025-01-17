SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspUpdateStep4CreateCQ2Tables]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- **********************************************************
	-- **********************************************************
	-- **** Load ontology
	-- **********************************************************
	-- **********************************************************

	-------------------------------------------------------------
	-- Get ontology paths and assign numeric IDs
	-------------------------------------------------------------

	-- Get a list of paths from the ontology
	SELECT DISTINCT ISNULL(C_FULLNAME,'') C_FULLNAME
		INTO #Paths
		FROM CRC.vwCQ2_Ontology
	ALTER TABLE #Paths ADD PRIMARY KEY (C_FULLNAME)

	-- Get a list of path parents
	;WITH a AS (
		SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
	), n AS (
		SELECT a.n+10*b.n+100*c.n n FROM a, a b, a c
	)
	SELECT C_FULLNAME, ISNULL(n,0) PATH_LENGTH, ISNULL(LEFT(C_FULLNAME,n+2),'') PARENT_PATH
		INTO #PathParents
		FROM (
			SELECT C_FULLNAME, n
			FROM #Paths, n
			WHERE n.n <= LEN(C_FULLNAME)
		) t
		WHERE SUBSTRING(C_FULLNAME,n+2,1)='\'
	ALTER TABLE #PathParents ADD PRIMARY KEY (C_FULLNAME,PATH_LENGTH)

	-- Generate path IDs
	CREATE TABLE #CRC_CQ2_CONCEPT_PATH (
		CONCEPT_PATH_ID INT NOT NULL,
		C_FULLNAME VARCHAR(700) NOT NULL,
		NUM_CONCEPTS INT NOT NULL,
		CONCEPT_CD VARCHAR(50) NOT NULL,
		SUBTREE_END_ID INT NOT NULL
	)
	;WITH a AS (
		SELECT ROW_NUMBER() OVER (ORDER BY C_FULLNAME) CONCEPT_PATH_ID, C_FULLNAME
		FROM #Paths
	), b AS (
		SELECT p.PARENT_PATH, MAX(a.CONCEPT_PATH_ID) SUBTREE_END_ID
		FROM #PathParents p
			INNER JOIN a ON p.C_FULLNAME=a.C_FULLNAME
		GROUP BY p.PARENT_PATH
	)
	INSERT INTO #CRC_CQ2_CONCEPT_PATH WITH (TABLOCK)
		SELECT a.CONCEPT_PATH_ID, a.C_FULLNAME, 0, '', ISNULL(b.SUBTREE_END_ID,a.CONCEPT_PATH_ID)
		FROM a LEFT OUTER JOIN b ON a.C_FULLNAME=b.PARENT_PATH
	ALTER TABLE #CRC_CQ2_CONCEPT_PATH ADD PRIMARY KEY (C_FULLNAME)

	-------------------------------------------------------------
	-- Get concepts mapping to each ontology path
	-------------------------------------------------------------

	-- Lookup path concepts
	;WITH a AS (
		SELECT DISTINCT p.PARENT_PATH, c.CONCEPT_CD
		FROM CRC.vwCQ2_ConceptDimension c
			INNER JOIN #PathParents p
				ON c.CONCEPT_PATH=p.C_FULLNAME
	)
	SELECT b.CONCEPT_PATH_ID, b.C_FULLNAME, ISNULL(a.CONCEPT_CD,'') CONCEPT_CD
		INTO #CRC_CQ2_CONCEPT_PATH_CODE
		FROM a INNER JOIN #CRC_CQ2_CONCEPT_PATH b
			ON a.PARENT_PATH=b.C_FULLNAME
		WHERE b.CONCEPT_CD IS NOT NULL
	ALTER TABLE #CRC_CQ2_CONCEPT_PATH_CODE ADD PRIMARY KEY (C_FULLNAME, CONCEPT_CD)

	-- Update the path IDs with the number of concepts
	;WITH a AS (
		SELECT C_FULLNAME, COUNT(*) NUM_CONCEPTS, MAX(CONCEPT_CD) CONCEPT_CD
		FROM #CRC_CQ2_CONCEPT_PATH_CODE
		GROUP BY C_FULLNAME
	)
	UPDATE p
		SET p.NUM_CONCEPTS=a.NUM_CONCEPTS, p.CONCEPT_CD=(CASE WHEN a.NUM_CONCEPTS=1 THEN a.CONCEPT_CD ELSE '' END)
		FROM #CRC_CQ2_CONCEPT_PATH p
			INNER JOIN a
				ON p.C_FULLNAME=a.C_FULLNAME

	-------------------------------------------------------------
	-- Create the tables
	-------------------------------------------------------------
				
	-- Save CQ2_CONCEPT_PATH
	CREATE TABLE [CRC].[CQ2_CONCEPT_PATH_NEW] (
		CONCEPT_PATH_ID INT NOT NULL,
		C_FULLNAME VARCHAR(700) NOT NULL,
		NUM_CONCEPTS INT NOT NULL,
		CONCEPT_CD VARCHAR(50) NOT NULL,
		SUBTREE_END_ID INT NOT NULL
	)
	INSERT INTO [CRC].[CQ2_CONCEPT_PATH_NEW]
		SELECT CONCEPT_PATH_ID, C_FULLNAME, NUM_CONCEPTS, CONCEPT_CD, SUBTREE_END_ID
		FROM #CRC_CQ2_CONCEPT_PATH
	ALTER TABLE [CRC].[CQ2_CONCEPT_PATH_NEW] ADD PRIMARY KEY (CONCEPT_PATH_ID)
	CREATE UNIQUE NONCLUSTERED INDEX IDX_FULLNAME ON CRC.CQ2_CONCEPT_PATH_NEW (C_FULLNAME)
	CREATE NONCLUSTERED INDEX IDX_CONCEPT ON CRC.CQ2_CONCEPT_PATH_NEW (CONCEPT_CD)

	-- Save CQ2_CONCEPT_PATH_CODE
	CREATE TABLE [CRC].[CQ2_CONCEPT_PATH_CODE_NEW] (
		CONCEPT_PATH_ID INT NOT NULL,
		C_FULLNAME VARCHAR(700) NOT NULL,
		CONCEPT_CD VARCHAR(50) NOT NULL
	)
	INSERT INTO [CRC].[CQ2_CONCEPT_PATH_CODE_NEW] WITH (TABLOCK)
		SELECT CONCEPT_PATH_ID, C_FULLNAME, CONCEPT_CD
		FROM #CRC_CQ2_CONCEPT_PATH_CODE
	ALTER TABLE [CRC].[CQ2_CONCEPT_PATH_CODE_NEW] ADD PRIMARY KEY (CONCEPT_PATH_ID, CONCEPT_CD)
	CREATE UNIQUE NONCLUSTERED INDEX IDX_CONCEPT_CD_PATH_ID ON CRC.CQ2_CONCEPT_PATH_CODE_NEW (CONCEPT_CD, CONCEPT_PATH_ID)
	CREATE UNIQUE NONCLUSTERED INDEX IDX_FULLNAME_CONCEPT ON CRC.CQ2_CONCEPT_PATH_CODE_NEW (C_FULLNAME, CONCEPT_CD)

	-- Drop temp tables
	DROP TABLE #Paths
	DROP TABLE #PathParents
	DROP TABLE #CRC_CQ2_CONCEPT_PATH
	DROP TABLE #CRC_CQ2_CONCEPT_PATH_CODE

	-- **********************************************************
	-- **********************************************************
	-- **** Ontology concept (leaf) rollup
	-- **********************************************************
	-- **********************************************************

	-------------------------------------------------------------
	-- Fact counts by concept and patient
	-------------------------------------------------------------

	CREATE TABLE [CRC].[CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW] (
		CONCEPT_CD VARCHAR(50) NOT NULL,
		PATIENT_NUM INT NOT NULL,
		NUM_ENCOUNTERS INT,
		NUM_INSTANCES INT,
		NUM_FACTS INT,
		FIRST_START DATETIME,
		LAST_START DATETIME,
		LAST_END DATETIME,
		MIN_NVAL_NUM DECIMAL(18, 5),
		MAX_NVAL_NUM DECIMAL(18, 5),
		MIN_NVAL_L BIT,
		MAX_NVAL_G BIT
	)
	;WITH a AS (
		SELECT CONCEPT_CD,				
			PATIENT_NUM,
			ENCOUNTER_NUM,
			START_DATE,
			PROVIDER_ID,
			INSTANCE_NUM,
			COUNT(*) NUM_FACTS,
			MIN(START_DATE) FIRST_START,
			MAX(START_DATE) LAST_START,
			MAX(END_DATE) LAST_END,
			MIN(NVAL_NUM) MIN_NVAL_NUM,
			MAX(NVAL_NUM) MAX_NVAL_NUM,
			MAX(CASE WHEN VALTYPE_CD='N' AND TVAL_CHAR IN ('L','LE','NE') THEN 1 ELSE 0 END) MIN_NVAL_L,
			MAX(CASE WHEN VALTYPE_CD='N' AND TVAL_CHAR IN ('G','GE','NE') THEN 1 ELSE 0 END) MAX_NVAL_G
		FROM CRC.OBSERVATION_FACT_NEW
		GROUP BY CONCEPT_CD, PATIENT_NUM, ENCOUNTER_NUM, START_DATE, PROVIDER_ID, INSTANCE_NUM
	)
	INSERT INTO [CRC].[CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW] WITH (TABLOCK)
		SELECT CONCEPT_CD,
			PATIENT_NUM,
			COUNT(DISTINCT ENCOUNTER_NUM) NUM_ENCOUNTERS,
			COUNT(*) NUM_INSTANCES,
			SUM(NUM_FACTS) NUM_FACTS,
			MIN(FIRST_START) FIRST_START,
			MAX(LAST_START) LAST_START,
			MAX(LAST_END) LAST_END,
			MIN(MIN_NVAL_NUM) MIN_NVAL_NUM,
			MAX(MAX_NVAL_NUM) MAX_NVAL_NUM,
			MAX(MIN_NVAL_L*1) MIN_NVAL_L,
			MAX(MAX_NVAL_G*1) MAX_NVAL_G
		FROM a
		GROUP BY CONCEPT_CD, PATIENT_NUM
	ALTER TABLE [CRC].[CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW] ADD PRIMARY KEY (CONCEPT_CD, PATIENT_NUM) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)
	CREATE UNIQUE NONCLUSTERED INDEX IDX_PATIENT_CONCEPT ON CRC.CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW (PATIENT_NUM, CONCEPT_CD) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)

	-------------------------------------------------------------
	-- Fact counts by concept
	-------------------------------------------------------------

	CREATE TABLE [CRC].[CQ2_FACT_COUNTS_CONCEPT_NEW] (
		CONCEPT_CD VARCHAR(50) NOT NULL,
		NUM_PATIENTS INT,
		NUM_ENCOUNTERS BIGINT,
		NUM_INSTANCES BIGINT,
		NUM_FACTS BIGINT,
		FIRST_START DATETIME,
		LAST_START DATETIME,
		LAST_END DATETIME,
		MIN_NVAL_NUM DECIMAL(18, 5),
		MAX_NVAL_NUM DECIMAL(18, 5),
		MIN_NVAL_L BIT,
		MAX_NVAL_G BIT,
		MAX_OCCURS INT
	)
	INSERT INTO [CRC].[CQ2_FACT_COUNTS_CONCEPT_NEW] WITH (TABLOCK)
		SELECT CONCEPT_CD,
			COUNT(DISTINCT PATIENT_NUM) NUM_PATIENTS,
			SUM(NUM_ENCOUNTERS) NUM_ENCOUNTERS,
			SUM(NUM_INSTANCES) NUM_INSTANCES,
			SUM(NUM_FACTS) NUM_FACTS,
			MIN(FIRST_START) FIRST_START,
			MAX(LAST_START) LAST_START,
			MAX(LAST_END) LAST_END,
			MIN(MIN_NVAL_NUM) MIN_NVAL_NUM,
			MAX(MAX_NVAL_NUM) MAX_NVAL_NUM,
			MAX(MIN_NVAL_L*1) MIN_NVAL_L,
			MAX(MAX_NVAL_G*1) MAX_NVAL_G,
			MAX(NUM_INSTANCES) MAX_OCCURS
		FROM [CRC].[CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW]
		GROUP BY concept_cd
	ALTER TABLE [CRC].[CQ2_FACT_COUNTS_CONCEPT_NEW] ADD PRIMARY KEY (CONCEPT_CD)

	-- **********************************************************
	-- **********************************************************
	-- **** Ontology path (folder) rollup
	-- **********************************************************
	-- **********************************************************

	-------------------------------------------------------------
	-- Fact counts by path and patient
	-------------------------------------------------------------

	-- Get the concepts of folder paths
	SELECT c.CONCEPT_PATH_ID, c.CONCEPT_CD
		INTO #FolderConcepts
		FROM [CRC].[CQ2_CONCEPT_PATH_NEW] p
			INNER JOIN [CRC].[CQ2_CONCEPT_PATH_CODE_NEW] c
				ON p.CONCEPT_PATH_ID=c.CONCEPT_PATH_ID
		WHERE p.NUM_CONCEPTS>1
	ALTER TABLE #FolderConcepts ADD PRIMARY KEY (CONCEPT_CD, CONCEPT_PATH_ID)

	-- Caculate fact counts by path and patient
	CREATE TABLE [CRC].[CQ2_FACT_COUNTS_PATH_PATIENT_NEW] (
		CONCEPT_PATH_ID INT NOT NULL,
		PATIENT_NUM INT NOT NULL,
		NUM_ENCOUNTERS INT,
		NUM_INSTANCES INT,
		NUM_FACTS INT,
		FIRST_START DATETIME,
		LAST_START DATETIME,
		LAST_END DATETIME,
		MIN_NVAL_NUM DECIMAL(18, 5),
		MAX_NVAL_NUM DECIMAL(18, 5),
		MIN_NVAL_L BIT,
		MAX_NVAL_G BIT
	)
	INSERT INTO [CRC].[CQ2_FACT_COUNTS_PATH_PATIENT_NEW] WITH (TABLOCK)
		SELECT c.CONCEPT_PATH_ID, 
			p.PATIENT_NUM,
			SUM(NUM_ENCOUNTERS) NUM_ENCOUNTERS, -- Doesn't consider duplicates
			SUM(NUM_INSTANCES) NUM_INSTANCES,
			SUM(NUM_FACTS) NUM_FACTS,
			MIN(FIRST_START) FIRST_START,
			MAX(LAST_START) LAST_START,
			MAX(LAST_END) LAST_END,
			MIN(MIN_NVAL_NUM) MIN_NVAL_NUM,
			MAX(MAX_NVAL_NUM) MAX_NVAL_NUM,
			MAX(MIN_NVAL_L*1.0) MIN_NVAL_L,
			MAX(MAX_NVAL_G*1.0) MAX_NVAL_G
		FROM #FolderConcepts c
			INNER JOIN [CRC].[CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW] p
				ON c.CONCEPT_CD=p.CONCEPT_CD
		GROUP BY c.CONCEPT_PATH_ID, p.PATIENT_NUM
	ALTER TABLE [CRC].[CQ2_FACT_COUNTS_PATH_PATIENT_NEW] ADD PRIMARY KEY (CONCEPT_PATH_ID, PATIENT_NUM) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)
	CREATE UNIQUE NONCLUSTERED INDEX IDX_PATIENT_PATH_ID ON [CRC].[CQ2_FACT_COUNTS_PATH_PATIENT_NEW] (PATIENT_NUM, CONCEPT_PATH_ID) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)

	-- Drop temp table
	DROP TABLE #FolderConcepts

	-------------------------------------------------------------
	-- Fact counts by path
	-------------------------------------------------------------

	CREATE TABLE [CRC].[CQ2_FACT_COUNTS_PATH_NEW] (
		CONCEPT_PATH_ID INT NOT NULL,
		NUM_PATIENTS INT,
		NUM_ENCOUNTERS BIGINT,
		NUM_INSTANCES BIGINT,
		NUM_FACTS BIGINT,
		FIRST_START DATETIME,
		LAST_START DATETIME,
		LAST_END DATETIME,
		MIN_NVAL_NUM DECIMAL(18, 5),
		MAX_NVAL_NUM DECIMAL(18, 5),
		MIN_NVAL_L BIT,
		MAX_NVAL_G BIT,
		MAX_OCCURS INT
	)
	INSERT INTO [CRC].[CQ2_FACT_COUNTS_PATH_NEW] WITH (TABLOCK)
		SELECT CONCEPT_PATH_ID,
			COUNT(*) NUM_PATIENTS,
			SUM(NUM_ENCOUNTERS) NUM_ENCOUNTERS, -- Doesn't consider duplicates
			SUM(NUM_INSTANCES) NUM_INSTANCES,
			SUM(NUM_FACTS) NUM_FACTS,
			MIN(FIRST_START) FIRST_START,
			MAX(LAST_START) LAST_START,
			MAX(LAST_END) LAST_END,
			MIN(MIN_NVAL_NUM) MIN_NVAL_NUM,
			MAX(MAX_NVAL_NUM) MAX_NVAL_NUM,
			MAX(MIN_NVAL_L*1.0) MIN_NVAL_L,
			MAX(MAX_NVAL_G*1.0) MAX_NVAL_G,
			MAX(NUM_INSTANCES) MAX_OCCURS
		FROM CRC.CQ2_FACT_COUNTS_PATH_PATIENT_NEW
		GROUP BY CONCEPT_PATH_ID
	ALTER TABLE [CRC].[CQ2_FACT_COUNTS_PATH_NEW] ADD PRIMARY KEY (CONCEPT_PATH_ID)

	-- **********************************************************
	-- **********************************************************
	-- **** Sketches
	-- **********************************************************
	-- **********************************************************

	-------------------------------------------------------------
	-- Patient sketch hashes
	-------------------------------------------------------------

	-- Create two binary hash values per patient
	SELECT PATIENT_NUM, LEFT(H,12) B, RIGHT(H,20) V
		INTO #PatientHash
		FROM (
			SELECT PATIENT_NUM, 
				HASHBYTES('SHA2_256', cast(NEWID() AS VARCHAR(50))) H
			FROM CRC.PATIENT_DIMENSION_NEW
		) t
	CREATE UNIQUE CLUSTERED INDEX IDX_PK ON #PatientHash(V,PATIENT_NUM)

	-- Convert hash values to bin (B) and value (V) integers
	SELECT PATIENT_NUM, 
			CAST(CAST(B AS BINARY(3)) AS INT) % 32768 B,
			FLOOR(ROW_NUMBER() OVER (ORDER BY V)*n) V
		INTO #CQ2_SKETCH_PATIENT
		FROM #PatientHash
			CROSS JOIN (SELECT POWER(2,30)/CAST(COUNT(*)+1 AS FLOAT) n FROM #PatientHash) n

	-- Save the bin and value (split the bin into rows B and columns C)
	CREATE TABLE [CRC].[CQ2_SKETCH_PATIENT_NEW] (
		PATIENT_NUM INT NOT NULL,
		B15 SMALLINT NOT NULL,
		B TINYINT NOT NULL,
		C TINYINT NOT NULL,
		V INT NOT NULL
	)
	INSERT INTO [CRC].[CQ2_SKETCH_PATIENT_NEW] WITH (TABLOCK)
		SELECT PATIENT_NUM, B, B/256, B%256, V
		FROM #CQ2_SKETCH_PATIENT
	ALTER TABLE [CRC].[CQ2_SKETCH_PATIENT_NEW] ADD PRIMARY KEY (PATIENT_NUM) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)
	CREATE UNIQUE NONCLUSTERED INDEX IDX_V ON [CRC].[CQ2_SKETCH_PATIENT_NEW] (V) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)

	-- Drop the temp tables
	DROP TABLE #PatientHash
	DROP TABLE #CQ2_SKETCH_PATIENT

	-------------------------------------------------------------
	-- Path sketches
	-------------------------------------------------------------

	-- Create 2^15 (32768) row x 1 column sketch table
	CREATE TABLE #CQ2_SKETCH_PATH15 (
		CONCEPT_PATH_ID INT NOT NULL,
		B TINYINT NOT NULL,
		C TINYINT NOT NULL,
		V INT NOT NULL
	)
	-- Load multi-concept paths
	INSERT INTO #CQ2_SKETCH_PATH15 WITH (TABLOCK)
		SELECT p.CONCEPT_PATH_ID, s.B, s.C, MIN(V) V
			FROM [CRC].[CQ2_FACT_COUNTS_PATH_PATIENT_NEW] p
				INNER JOIN [CRC].[CQ2_SKETCH_PATIENT_NEW] s
					ON p.PATIENT_NUM = s.PATIENT_NUM
			GROUP BY p.CONCEPT_PATH_ID, s.B, s.C
	-- Load single-concept paths
	INSERT INTO #CQ2_SKETCH_PATH15 WITH (TABLOCK)
		SELECT c.CONCEPT_PATH_ID, s.B, s.C, MIN(V) V
			FROM [CRC].[CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW] p
				INNER JOIN [CRC].[CQ2_SKETCH_PATIENT_NEW] s
					ON p.PATIENT_NUM = s.PATIENT_NUM
				INNER JOIN [CRC].[CQ2_CONCEPT_PATH_NEW] c
					ON p.CONCEPT_CD = c.CONCEPT_CD AND c.CONCEPT_CD<>''
			GROUP BY c.CONCEPT_PATH_ID, s.B, s.C
	-- Add a primary key to the table
	ALTER TABLE #CQ2_SKETCH_PATH15 ADD PRIMARY KEY (CONCEPT_PATH_ID, B, C)

	-- Create 128 row x 256 column sketch table
	CREATE TABLE [CRC].[CQ2_SKETCH_PATH15x256_NEW] (
		CONCEPT_PATH_ID INT NOT NULL,
		B TINYINT NOT NULL,
		V0 INT, V1 INT, V2 INT, V3 INT, V4 INT, V5 INT, V6 INT, V7 INT, V8 INT, V9 INT, V10 INT, V11 INT, V12 INT, V13 INT, V14 INT, V15 INT,
		V16 INT, V17 INT, V18 INT, V19 INT, V20 INT, V21 INT, V22 INT, V23 INT, V24 INT, V25 INT, V26 INT, V27 INT, V28 INT, V29 INT, V30 INT, V31 INT, 
		V32 INT, V33 INT, V34 INT, V35 INT, V36 INT, V37 INT, V38 INT, V39 INT, V40 INT, V41 INT, V42 INT, V43 INT, V44 INT, V45 INT, V46 INT, V47 INT, 
		V48 INT, V49 INT, V50 INT, V51 INT, V52 INT, V53 INT, V54 INT, V55 INT, V56 INT, V57 INT, V58 INT, V59 INT, V60 INT, V61 INT, V62 INT, V63 INT, 
		V64 INT, V65 INT, V66 INT, V67 INT, V68 INT, V69 INT, V70 INT, V71 INT, V72 INT, V73 INT, V74 INT, V75 INT, V76 INT, V77 INT, V78 INT, V79 INT, 
		V80 INT, V81 INT, V82 INT, V83 INT, V84 INT, V85 INT, V86 INT, V87 INT, V88 INT, V89 INT, V90 INT, V91 INT, V92 INT, V93 INT, V94 INT, V95 INT, 
		V96 INT, V97 INT, V98 INT, V99 INT, V100 INT, V101 INT, V102 INT, V103 INT, V104 INT, V105 INT, V106 INT, V107 INT, V108 INT, V109 INT, V110 INT, V111 INT, 
		V112 INT, V113 INT, V114 INT, V115 INT, V116 INT, V117 INT, V118 INT, V119 INT, V120 INT, V121 INT, V122 INT, V123 INT, V124 INT, V125 INT, V126 INT, V127 INT, 
		V128 INT, V129 INT, V130 INT, V131 INT, V132 INT, V133 INT, V134 INT, V135 INT, V136 INT, V137 INT, V138 INT, V139 INT, V140 INT, V141 INT, V142 INT, V143 INT, 
		V144 INT, V145 INT, V146 INT, V147 INT, V148 INT, V149 INT, V150 INT, V151 INT, V152 INT, V153 INT, V154 INT, V155 INT, V156 INT, V157 INT, V158 INT, V159 INT, 
		V160 INT, V161 INT, V162 INT, V163 INT, V164 INT, V165 INT, V166 INT, V167 INT, V168 INT, V169 INT, V170 INT, V171 INT, V172 INT, V173 INT, V174 INT, V175 INT, 
		V176 INT, V177 INT, V178 INT, V179 INT, V180 INT, V181 INT, V182 INT, V183 INT, V184 INT, V185 INT, V186 INT, V187 INT, V188 INT, V189 INT, V190 INT, V191 INT, 
		V192 INT, V193 INT, V194 INT, V195 INT, V196 INT, V197 INT, V198 INT, V199 INT, V200 INT, V201 INT, V202 INT, V203 INT, V204 INT, V205 INT, V206 INT, V207 INT, 
		V208 INT, V209 INT, V210 INT, V211 INT, V212 INT, V213 INT, V214 INT, V215 INT, V216 INT, V217 INT, V218 INT, V219 INT, V220 INT, V221 INT, V222 INT, V223 INT, 
		V224 INT, V225 INT, V226 INT, V227 INT, V228 INT, V229 INT, V230 INT, V231 INT, V232 INT, V233 INT, V234 INT, V235 INT, V236 INT, V237 INT, V238 INT, V239 INT, 
		V240 INT, V241 INT, V242 INT, V243 INT, V244 INT, V245 INT, V246 INT, V247 INT, V248 INT, V249 INT, V250 INT, V251 INT, V252 INT, V253 INT, V254 INT, V255 INT
	)
	-- Load 128 row x 256 column sketch table
	INSERT INTO [CRC].[CQ2_SKETCH_PATH15x256_NEW] WITH (TABLOCK)
		SELECT CONCEPT_PATH_ID, B, 
			MAX(CASE WHEN C = 0 THEN V ELSE NULL END) V0, MAX(CASE WHEN C = 1 THEN V ELSE NULL END) V1, MAX(CASE WHEN C = 2 THEN V ELSE NULL END) V2, MAX(CASE WHEN C = 3 THEN V ELSE NULL END) V3, 
			MAX(CASE WHEN C = 4 THEN V ELSE NULL END) V4, MAX(CASE WHEN C = 5 THEN V ELSE NULL END) V5, MAX(CASE WHEN C = 6 THEN V ELSE NULL END) V6, MAX(CASE WHEN C = 7 THEN V ELSE NULL END) V7, 
			MAX(CASE WHEN C = 8 THEN V ELSE NULL END) V8, MAX(CASE WHEN C = 9 THEN V ELSE NULL END) V9, MAX(CASE WHEN C = 10 THEN V ELSE NULL END) V10, MAX(CASE WHEN C = 11 THEN V ELSE NULL END) V11, 
			MAX(CASE WHEN C = 12 THEN V ELSE NULL END) V12, MAX(CASE WHEN C = 13 THEN V ELSE NULL END) V13, MAX(CASE WHEN C = 14 THEN V ELSE NULL END) V14, MAX(CASE WHEN C = 15 THEN V ELSE NULL END) V15, 
			MAX(CASE WHEN C = 16 THEN V ELSE NULL END) V16, MAX(CASE WHEN C = 17 THEN V ELSE NULL END) V17, MAX(CASE WHEN C = 18 THEN V ELSE NULL END) V18, MAX(CASE WHEN C = 19 THEN V ELSE NULL END) V19, 
			MAX(CASE WHEN C = 20 THEN V ELSE NULL END) V20, MAX(CASE WHEN C = 21 THEN V ELSE NULL END) V21, MAX(CASE WHEN C = 22 THEN V ELSE NULL END) V22, MAX(CASE WHEN C = 23 THEN V ELSE NULL END) V23, 
			MAX(CASE WHEN C = 24 THEN V ELSE NULL END) V24, MAX(CASE WHEN C = 25 THEN V ELSE NULL END) V25, MAX(CASE WHEN C = 26 THEN V ELSE NULL END) V26, MAX(CASE WHEN C = 27 THEN V ELSE NULL END) V27, 
			MAX(CASE WHEN C = 28 THEN V ELSE NULL END) V28, MAX(CASE WHEN C = 29 THEN V ELSE NULL END) V29, MAX(CASE WHEN C = 30 THEN V ELSE NULL END) V30, MAX(CASE WHEN C = 31 THEN V ELSE NULL END) V31, 
			MAX(CASE WHEN C = 32 THEN V ELSE NULL END) V32, MAX(CASE WHEN C = 33 THEN V ELSE NULL END) V33, MAX(CASE WHEN C = 34 THEN V ELSE NULL END) V34, MAX(CASE WHEN C = 35 THEN V ELSE NULL END) V35, 
			MAX(CASE WHEN C = 36 THEN V ELSE NULL END) V36, MAX(CASE WHEN C = 37 THEN V ELSE NULL END) V37, MAX(CASE WHEN C = 38 THEN V ELSE NULL END) V38, MAX(CASE WHEN C = 39 THEN V ELSE NULL END) V39, 
			MAX(CASE WHEN C = 40 THEN V ELSE NULL END) V40, MAX(CASE WHEN C = 41 THEN V ELSE NULL END) V41, MAX(CASE WHEN C = 42 THEN V ELSE NULL END) V42, MAX(CASE WHEN C = 43 THEN V ELSE NULL END) V43, 
			MAX(CASE WHEN C = 44 THEN V ELSE NULL END) V44, MAX(CASE WHEN C = 45 THEN V ELSE NULL END) V45, MAX(CASE WHEN C = 46 THEN V ELSE NULL END) V46, MAX(CASE WHEN C = 47 THEN V ELSE NULL END) V47, 
			MAX(CASE WHEN C = 48 THEN V ELSE NULL END) V48, MAX(CASE WHEN C = 49 THEN V ELSE NULL END) V49, MAX(CASE WHEN C = 50 THEN V ELSE NULL END) V50, MAX(CASE WHEN C = 51 THEN V ELSE NULL END) V51, 
			MAX(CASE WHEN C = 52 THEN V ELSE NULL END) V52, MAX(CASE WHEN C = 53 THEN V ELSE NULL END) V53, MAX(CASE WHEN C = 54 THEN V ELSE NULL END) V54, MAX(CASE WHEN C = 55 THEN V ELSE NULL END) V55, 
			MAX(CASE WHEN C = 56 THEN V ELSE NULL END) V56, MAX(CASE WHEN C = 57 THEN V ELSE NULL END) V57, MAX(CASE WHEN C = 58 THEN V ELSE NULL END) V58, MAX(CASE WHEN C = 59 THEN V ELSE NULL END) V59, 
			MAX(CASE WHEN C = 60 THEN V ELSE NULL END) V60, MAX(CASE WHEN C = 61 THEN V ELSE NULL END) V61, MAX(CASE WHEN C = 62 THEN V ELSE NULL END) V62, MAX(CASE WHEN C = 63 THEN V ELSE NULL END) V63, 
			MAX(CASE WHEN C = 64 THEN V ELSE NULL END) V64, MAX(CASE WHEN C = 65 THEN V ELSE NULL END) V65, MAX(CASE WHEN C = 66 THEN V ELSE NULL END) V66, MAX(CASE WHEN C = 67 THEN V ELSE NULL END) V67, 
			MAX(CASE WHEN C = 68 THEN V ELSE NULL END) V68, MAX(CASE WHEN C = 69 THEN V ELSE NULL END) V69, MAX(CASE WHEN C = 70 THEN V ELSE NULL END) V70, MAX(CASE WHEN C = 71 THEN V ELSE NULL END) V71, 
			MAX(CASE WHEN C = 72 THEN V ELSE NULL END) V72, MAX(CASE WHEN C = 73 THEN V ELSE NULL END) V73, MAX(CASE WHEN C = 74 THEN V ELSE NULL END) V74, MAX(CASE WHEN C = 75 THEN V ELSE NULL END) V75, 
			MAX(CASE WHEN C = 76 THEN V ELSE NULL END) V76, MAX(CASE WHEN C = 77 THEN V ELSE NULL END) V77, MAX(CASE WHEN C = 78 THEN V ELSE NULL END) V78, MAX(CASE WHEN C = 79 THEN V ELSE NULL END) V79, 
			MAX(CASE WHEN C = 80 THEN V ELSE NULL END) V80, MAX(CASE WHEN C = 81 THEN V ELSE NULL END) V81, MAX(CASE WHEN C = 82 THEN V ELSE NULL END) V82, MAX(CASE WHEN C = 83 THEN V ELSE NULL END) V83, 
			MAX(CASE WHEN C = 84 THEN V ELSE NULL END) V84, MAX(CASE WHEN C = 85 THEN V ELSE NULL END) V85, MAX(CASE WHEN C = 86 THEN V ELSE NULL END) V86, MAX(CASE WHEN C = 87 THEN V ELSE NULL END) V87, 
			MAX(CASE WHEN C = 88 THEN V ELSE NULL END) V88, MAX(CASE WHEN C = 89 THEN V ELSE NULL END) V89, MAX(CASE WHEN C = 90 THEN V ELSE NULL END) V90, MAX(CASE WHEN C = 91 THEN V ELSE NULL END) V91, 
			MAX(CASE WHEN C = 92 THEN V ELSE NULL END) V92, MAX(CASE WHEN C = 93 THEN V ELSE NULL END) V93, MAX(CASE WHEN C = 94 THEN V ELSE NULL END) V94, MAX(CASE WHEN C = 95 THEN V ELSE NULL END) V95, 
			MAX(CASE WHEN C = 96 THEN V ELSE NULL END) V96, MAX(CASE WHEN C = 97 THEN V ELSE NULL END) V97, MAX(CASE WHEN C = 98 THEN V ELSE NULL END) V98, MAX(CASE WHEN C = 99 THEN V ELSE NULL END) V99, 
			MAX(CASE WHEN C = 100 THEN V ELSE NULL END) V100, MAX(CASE WHEN C = 101 THEN V ELSE NULL END) V101, MAX(CASE WHEN C = 102 THEN V ELSE NULL END) V102, MAX(CASE WHEN C = 103 THEN V ELSE NULL END) V103, 
			MAX(CASE WHEN C = 104 THEN V ELSE NULL END) V104, MAX(CASE WHEN C = 105 THEN V ELSE NULL END) V105, MAX(CASE WHEN C = 106 THEN V ELSE NULL END) V106, MAX(CASE WHEN C = 107 THEN V ELSE NULL END) V107, 
			MAX(CASE WHEN C = 108 THEN V ELSE NULL END) V108, MAX(CASE WHEN C = 109 THEN V ELSE NULL END) V109, MAX(CASE WHEN C = 110 THEN V ELSE NULL END) V110, MAX(CASE WHEN C = 111 THEN V ELSE NULL END) V111, 
			MAX(CASE WHEN C = 112 THEN V ELSE NULL END) V112, MAX(CASE WHEN C = 113 THEN V ELSE NULL END) V113, MAX(CASE WHEN C = 114 THEN V ELSE NULL END) V114, MAX(CASE WHEN C = 115 THEN V ELSE NULL END) V115, 
			MAX(CASE WHEN C = 116 THEN V ELSE NULL END) V116, MAX(CASE WHEN C = 117 THEN V ELSE NULL END) V117, MAX(CASE WHEN C = 118 THEN V ELSE NULL END) V118, MAX(CASE WHEN C = 119 THEN V ELSE NULL END) V119, 
			MAX(CASE WHEN C = 120 THEN V ELSE NULL END) V120, MAX(CASE WHEN C = 121 THEN V ELSE NULL END) V121, MAX(CASE WHEN C = 122 THEN V ELSE NULL END) V122, MAX(CASE WHEN C = 123 THEN V ELSE NULL END) V123, 
			MAX(CASE WHEN C = 124 THEN V ELSE NULL END) V124, MAX(CASE WHEN C = 125 THEN V ELSE NULL END) V125, MAX(CASE WHEN C = 126 THEN V ELSE NULL END) V126, MAX(CASE WHEN C = 127 THEN V ELSE NULL END) V127, 
			MAX(CASE WHEN C = 128 THEN V ELSE NULL END) V128, MAX(CASE WHEN C = 129 THEN V ELSE NULL END) V129, MAX(CASE WHEN C = 130 THEN V ELSE NULL END) V130, MAX(CASE WHEN C = 131 THEN V ELSE NULL END) V131, 
			MAX(CASE WHEN C = 132 THEN V ELSE NULL END) V132, MAX(CASE WHEN C = 133 THEN V ELSE NULL END) V133, MAX(CASE WHEN C = 134 THEN V ELSE NULL END) V134, MAX(CASE WHEN C = 135 THEN V ELSE NULL END) V135, 
			MAX(CASE WHEN C = 136 THEN V ELSE NULL END) V136, MAX(CASE WHEN C = 137 THEN V ELSE NULL END) V137, MAX(CASE WHEN C = 138 THEN V ELSE NULL END) V138, MAX(CASE WHEN C = 139 THEN V ELSE NULL END) V139, 
			MAX(CASE WHEN C = 140 THEN V ELSE NULL END) V140, MAX(CASE WHEN C = 141 THEN V ELSE NULL END) V141, MAX(CASE WHEN C = 142 THEN V ELSE NULL END) V142, MAX(CASE WHEN C = 143 THEN V ELSE NULL END) V143, 
			MAX(CASE WHEN C = 144 THEN V ELSE NULL END) V144, MAX(CASE WHEN C = 145 THEN V ELSE NULL END) V145, MAX(CASE WHEN C = 146 THEN V ELSE NULL END) V146, MAX(CASE WHEN C = 147 THEN V ELSE NULL END) V147, 
			MAX(CASE WHEN C = 148 THEN V ELSE NULL END) V148, MAX(CASE WHEN C = 149 THEN V ELSE NULL END) V149, MAX(CASE WHEN C = 150 THEN V ELSE NULL END) V150, MAX(CASE WHEN C = 151 THEN V ELSE NULL END) V151, 
			MAX(CASE WHEN C = 152 THEN V ELSE NULL END) V152, MAX(CASE WHEN C = 153 THEN V ELSE NULL END) V153, MAX(CASE WHEN C = 154 THEN V ELSE NULL END) V154, MAX(CASE WHEN C = 155 THEN V ELSE NULL END) V155, 
			MAX(CASE WHEN C = 156 THEN V ELSE NULL END) V156, MAX(CASE WHEN C = 157 THEN V ELSE NULL END) V157, MAX(CASE WHEN C = 158 THEN V ELSE NULL END) V158, MAX(CASE WHEN C = 159 THEN V ELSE NULL END) V159, 
			MAX(CASE WHEN C = 160 THEN V ELSE NULL END) V160, MAX(CASE WHEN C = 161 THEN V ELSE NULL END) V161, MAX(CASE WHEN C = 162 THEN V ELSE NULL END) V162, MAX(CASE WHEN C = 163 THEN V ELSE NULL END) V163, 
			MAX(CASE WHEN C = 164 THEN V ELSE NULL END) V164, MAX(CASE WHEN C = 165 THEN V ELSE NULL END) V165, MAX(CASE WHEN C = 166 THEN V ELSE NULL END) V166, MAX(CASE WHEN C = 167 THEN V ELSE NULL END) V167, 
			MAX(CASE WHEN C = 168 THEN V ELSE NULL END) V168, MAX(CASE WHEN C = 169 THEN V ELSE NULL END) V169, MAX(CASE WHEN C = 170 THEN V ELSE NULL END) V170, MAX(CASE WHEN C = 171 THEN V ELSE NULL END) V171, 
			MAX(CASE WHEN C = 172 THEN V ELSE NULL END) V172, MAX(CASE WHEN C = 173 THEN V ELSE NULL END) V173, MAX(CASE WHEN C = 174 THEN V ELSE NULL END) V174, MAX(CASE WHEN C = 175 THEN V ELSE NULL END) V175, 
			MAX(CASE WHEN C = 176 THEN V ELSE NULL END) V176, MAX(CASE WHEN C = 177 THEN V ELSE NULL END) V177, MAX(CASE WHEN C = 178 THEN V ELSE NULL END) V178, MAX(CASE WHEN C = 179 THEN V ELSE NULL END) V179, 
			MAX(CASE WHEN C = 180 THEN V ELSE NULL END) V180, MAX(CASE WHEN C = 181 THEN V ELSE NULL END) V181, MAX(CASE WHEN C = 182 THEN V ELSE NULL END) V182, MAX(CASE WHEN C = 183 THEN V ELSE NULL END) V183, 
			MAX(CASE WHEN C = 184 THEN V ELSE NULL END) V184, MAX(CASE WHEN C = 185 THEN V ELSE NULL END) V185, MAX(CASE WHEN C = 186 THEN V ELSE NULL END) V186, MAX(CASE WHEN C = 187 THEN V ELSE NULL END) V187, 
			MAX(CASE WHEN C = 188 THEN V ELSE NULL END) V188, MAX(CASE WHEN C = 189 THEN V ELSE NULL END) V189, MAX(CASE WHEN C = 190 THEN V ELSE NULL END) V190, MAX(CASE WHEN C = 191 THEN V ELSE NULL END) V191, 
			MAX(CASE WHEN C = 192 THEN V ELSE NULL END) V192, MAX(CASE WHEN C = 193 THEN V ELSE NULL END) V193, MAX(CASE WHEN C = 194 THEN V ELSE NULL END) V194, MAX(CASE WHEN C = 195 THEN V ELSE NULL END) V195, 
			MAX(CASE WHEN C = 196 THEN V ELSE NULL END) V196, MAX(CASE WHEN C = 197 THEN V ELSE NULL END) V197, MAX(CASE WHEN C = 198 THEN V ELSE NULL END) V198, MAX(CASE WHEN C = 199 THEN V ELSE NULL END) V199, 
			MAX(CASE WHEN C = 200 THEN V ELSE NULL END) V200, MAX(CASE WHEN C = 201 THEN V ELSE NULL END) V201, MAX(CASE WHEN C = 202 THEN V ELSE NULL END) V202, MAX(CASE WHEN C = 203 THEN V ELSE NULL END) V203, 
			MAX(CASE WHEN C = 204 THEN V ELSE NULL END) V204, MAX(CASE WHEN C = 205 THEN V ELSE NULL END) V205, MAX(CASE WHEN C = 206 THEN V ELSE NULL END) V206, MAX(CASE WHEN C = 207 THEN V ELSE NULL END) V207, 
			MAX(CASE WHEN C = 208 THEN V ELSE NULL END) V208, MAX(CASE WHEN C = 209 THEN V ELSE NULL END) V209, MAX(CASE WHEN C = 210 THEN V ELSE NULL END) V210, MAX(CASE WHEN C = 211 THEN V ELSE NULL END) V211, 
			MAX(CASE WHEN C = 212 THEN V ELSE NULL END) V212, MAX(CASE WHEN C = 213 THEN V ELSE NULL END) V213, MAX(CASE WHEN C = 214 THEN V ELSE NULL END) V214, MAX(CASE WHEN C = 215 THEN V ELSE NULL END) V215, 
			MAX(CASE WHEN C = 216 THEN V ELSE NULL END) V216, MAX(CASE WHEN C = 217 THEN V ELSE NULL END) V217, MAX(CASE WHEN C = 218 THEN V ELSE NULL END) V218, MAX(CASE WHEN C = 219 THEN V ELSE NULL END) V219, 
			MAX(CASE WHEN C = 220 THEN V ELSE NULL END) V220, MAX(CASE WHEN C = 221 THEN V ELSE NULL END) V221, MAX(CASE WHEN C = 222 THEN V ELSE NULL END) V222, MAX(CASE WHEN C = 223 THEN V ELSE NULL END) V223, 
			MAX(CASE WHEN C = 224 THEN V ELSE NULL END) V224, MAX(CASE WHEN C = 225 THEN V ELSE NULL END) V225, MAX(CASE WHEN C = 226 THEN V ELSE NULL END) V226, MAX(CASE WHEN C = 227 THEN V ELSE NULL END) V227, 
			MAX(CASE WHEN C = 228 THEN V ELSE NULL END) V228, MAX(CASE WHEN C = 229 THEN V ELSE NULL END) V229, MAX(CASE WHEN C = 230 THEN V ELSE NULL END) V230, MAX(CASE WHEN C = 231 THEN V ELSE NULL END) V231, 
			MAX(CASE WHEN C = 232 THEN V ELSE NULL END) V232, MAX(CASE WHEN C = 233 THEN V ELSE NULL END) V233, MAX(CASE WHEN C = 234 THEN V ELSE NULL END) V234, MAX(CASE WHEN C = 235 THEN V ELSE NULL END) V235, 
			MAX(CASE WHEN C = 236 THEN V ELSE NULL END) V236, MAX(CASE WHEN C = 237 THEN V ELSE NULL END) V237, MAX(CASE WHEN C = 238 THEN V ELSE NULL END) V238, MAX(CASE WHEN C = 239 THEN V ELSE NULL END) V239, 
			MAX(CASE WHEN C = 240 THEN V ELSE NULL END) V240, MAX(CASE WHEN C = 241 THEN V ELSE NULL END) V241, MAX(CASE WHEN C = 242 THEN V ELSE NULL END) V242, MAX(CASE WHEN C = 243 THEN V ELSE NULL END) V243, 
			MAX(CASE WHEN C = 244 THEN V ELSE NULL END) V244, MAX(CASE WHEN C = 245 THEN V ELSE NULL END) V245, MAX(CASE WHEN C = 246 THEN V ELSE NULL END) V246, MAX(CASE WHEN C = 247 THEN V ELSE NULL END) V247, 
			MAX(CASE WHEN C = 248 THEN V ELSE NULL END) V248, MAX(CASE WHEN C = 249 THEN V ELSE NULL END) V249, MAX(CASE WHEN C = 250 THEN V ELSE NULL END) V250, MAX(CASE WHEN C = 251 THEN V ELSE NULL END) V251, 
			MAX(CASE WHEN C = 252 THEN V ELSE NULL END) V252, MAX(CASE WHEN C = 253 THEN V ELSE NULL END) V253, MAX(CASE WHEN C = 254 THEN V ELSE NULL END) V254, MAX(CASE WHEN C = 255 THEN V ELSE NULL END) V255
		FROM #CQ2_SKETCH_PATH15
		GROUP BY CONCEPT_PATH_ID, B
	-- Add a primary key to the 128 row x 256 column sketch table
	ALTER TABLE [CRC].[CQ2_SKETCH_PATH15x256_NEW] ADD PRIMARY KEY (CONCEPT_PATH_ID, B) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)

	-- Create 1 row x 256 column sketch table
	CREATE TABLE [CRC].[CQ2_SKETCH_PATH8x256_NEW] (
		CONCEPT_PATH_ID INT NOT NULL,
		V0 INT, V1 INT, V2 INT, V3 INT, V4 INT, V5 INT, V6 INT, V7 INT, V8 INT, V9 INT, V10 INT, V11 INT, V12 INT, V13 INT, V14 INT, V15 INT, 
		V16 INT, V17 INT, V18 INT, V19 INT, V20 INT, V21 INT, V22 INT, V23 INT, V24 INT, V25 INT, V26 INT, V27 INT, V28 INT, V29 INT, V30 INT, V31 INT, 
		V32 INT, V33 INT, V34 INT, V35 INT, V36 INT, V37 INT, V38 INT, V39 INT, V40 INT, V41 INT, V42 INT, V43 INT, V44 INT, V45 INT, V46 INT, V47 INT, 
		V48 INT, V49 INT, V50 INT, V51 INT, V52 INT, V53 INT, V54 INT, V55 INT, V56 INT, V57 INT, V58 INT, V59 INT, V60 INT, V61 INT, V62 INT, V63 INT, 
		V64 INT, V65 INT, V66 INT, V67 INT, V68 INT, V69 INT, V70 INT, V71 INT, V72 INT, V73 INT, V74 INT, V75 INT, V76 INT, V77 INT, V78 INT, V79 INT, 
		V80 INT, V81 INT, V82 INT, V83 INT, V84 INT, V85 INT, V86 INT, V87 INT, V88 INT, V89 INT, V90 INT, V91 INT, V92 INT, V93 INT, V94 INT, V95 INT, 
		V96 INT, V97 INT, V98 INT, V99 INT, V100 INT, V101 INT, V102 INT, V103 INT, V104 INT, V105 INT, V106 INT, V107 INT, V108 INT, V109 INT, V110 INT, V111 INT, 
		V112 INT, V113 INT, V114 INT, V115 INT, V116 INT, V117 INT, V118 INT, V119 INT, V120 INT, V121 INT, V122 INT, V123 INT, V124 INT, V125 INT, V126 INT, V127 INT, 
		V128 INT, V129 INT, V130 INT, V131 INT, V132 INT, V133 INT, V134 INT, V135 INT, V136 INT, V137 INT, V138 INT, V139 INT, V140 INT, V141 INT, V142 INT, V143 INT, 
		V144 INT, V145 INT, V146 INT, V147 INT, V148 INT, V149 INT, V150 INT, V151 INT, V152 INT, V153 INT, V154 INT, V155 INT, V156 INT, V157 INT, V158 INT, V159 INT, 
		V160 INT, V161 INT, V162 INT, V163 INT, V164 INT, V165 INT, V166 INT, V167 INT, V168 INT, V169 INT, V170 INT, V171 INT, V172 INT, V173 INT, V174 INT, V175 INT, 
		V176 INT, V177 INT, V178 INT, V179 INT, V180 INT, V181 INT, V182 INT, V183 INT, V184 INT, V185 INT, V186 INT, V187 INT, V188 INT, V189 INT, V190 INT, V191 INT, 
		V192 INT, V193 INT, V194 INT, V195 INT, V196 INT, V197 INT, V198 INT, V199 INT, V200 INT, V201 INT, V202 INT, V203 INT, V204 INT, V205 INT, V206 INT, V207 INT, 
		V208 INT, V209 INT, V210 INT, V211 INT, V212 INT, V213 INT, V214 INT, V215 INT, V216 INT, V217 INT, V218 INT, V219 INT, V220 INT, V221 INT, V222 INT, V223 INT, 
		V224 INT, V225 INT, V226 INT, V227 INT, V228 INT, V229 INT, V230 INT, V231 INT, V232 INT, V233 INT, V234 INT, V235 INT, V236 INT, V237 INT, V238 INT, V239 INT, 
		V240 INT, V241 INT, V242 INT, V243 INT, V244 INT, V245 INT, V246 INT, V247 INT, V248 INT, V249 INT, V250 INT, V251 INT, V252 INT, V253 INT, V254 INT, V255 INT
	)
	-- Load 1 row x 256 column sketch table
	INSERT INTO [CRC].[CQ2_SKETCH_PATH8x256_NEW] WITH (TABLOCK)
		SELECT CONCEPT_PATH_ID, 
			MIN(V0) V0, MIN(V1) V1, MIN(V2) V2, MIN(V3) V3, MIN(V4) V4, MIN(V5) V5, MIN(V6) V6, MIN(V7) V7, MIN(V8) V8, MIN(V9) V9, MIN(V10) V10, MIN(V11) V11, MIN(V12) V12, MIN(V13) V13, MIN(V14) V14, MIN(V15) V15, 
			MIN(V16) V16, MIN(V17) V17, MIN(V18) V18, MIN(V19) V19, MIN(V20) V20, MIN(V21) V21, MIN(V22) V22, MIN(V23) V23, MIN(V24) V24, MIN(V25) V25, MIN(V26) V26, MIN(V27) V27, MIN(V28) V28, MIN(V29) V29, MIN(V30) V30, MIN(V31) V31, 
			MIN(V32) V32, MIN(V33) V33, MIN(V34) V34, MIN(V35) V35, MIN(V36) V36, MIN(V37) V37, MIN(V38) V38, MIN(V39) V39, MIN(V40) V40, MIN(V41) V41, MIN(V42) V42, MIN(V43) V43, MIN(V44) V44, MIN(V45) V45, MIN(V46) V46, MIN(V47) V47, 
			MIN(V48) V48, MIN(V49) V49, MIN(V50) V50, MIN(V51) V51, MIN(V52) V52, MIN(V53) V53, MIN(V54) V54, MIN(V55) V55, MIN(V56) V56, MIN(V57) V57, MIN(V58) V58, MIN(V59) V59, MIN(V60) V60, MIN(V61) V61, MIN(V62) V62, MIN(V63) V63, 
			MIN(V64) V64, MIN(V65) V65, MIN(V66) V66, MIN(V67) V67, MIN(V68) V68, MIN(V69) V69, MIN(V70) V70, MIN(V71) V71, MIN(V72) V72, MIN(V73) V73, MIN(V74) V74, MIN(V75) V75, MIN(V76) V76, MIN(V77) V77, MIN(V78) V78, MIN(V79) V79, 
			MIN(V80) V80, MIN(V81) V81, MIN(V82) V82, MIN(V83) V83, MIN(V84) V84, MIN(V85) V85, MIN(V86) V86, MIN(V87) V87, MIN(V88) V88, MIN(V89) V89, MIN(V90) V90, MIN(V91) V91, MIN(V92) V92, MIN(V93) V93, MIN(V94) V94, MIN(V95) V95, 
			MIN(V96) V96, MIN(V97) V97, MIN(V98) V98, MIN(V99) V99, MIN(V100) V100, MIN(V101) V101, MIN(V102) V102, MIN(V103) V103, MIN(V104) V104, MIN(V105) V105, MIN(V106) V106, MIN(V107) V107, MIN(V108) V108, MIN(V109) V109, MIN(V110) V110, MIN(V111) V111, 
			MIN(V112) V112, MIN(V113) V113, MIN(V114) V114, MIN(V115) V115, MIN(V116) V116, MIN(V117) V117, MIN(V118) V118, MIN(V119) V119, MIN(V120) V120, MIN(V121) V121, MIN(V122) V122, MIN(V123) V123, MIN(V124) V124, MIN(V125) V125, MIN(V126) V126, MIN(V127) V127, 
			MIN(V128) V128, MIN(V129) V129, MIN(V130) V130, MIN(V131) V131, MIN(V132) V132, MIN(V133) V133, MIN(V134) V134, MIN(V135) V135, MIN(V136) V136, MIN(V137) V137, MIN(V138) V138, MIN(V139) V139, MIN(V140) V140, MIN(V141) V141, MIN(V142) V142, MIN(V143) V143, 
			MIN(V144) V144, MIN(V145) V145, MIN(V146) V146, MIN(V147) V147, MIN(V148) V148, MIN(V149) V149, MIN(V150) V150, MIN(V151) V151, MIN(V152) V152, MIN(V153) V153, MIN(V154) V154, MIN(V155) V155, MIN(V156) V156, MIN(V157) V157, MIN(V158) V158, MIN(V159) V159, 
			MIN(V160) V160, MIN(V161) V161, MIN(V162) V162, MIN(V163) V163, MIN(V164) V164, MIN(V165) V165, MIN(V166) V166, MIN(V167) V167, MIN(V168) V168, MIN(V169) V169, MIN(V170) V170, MIN(V171) V171, MIN(V172) V172, MIN(V173) V173, MIN(V174) V174, MIN(V175) V175, 
			MIN(V176) V176, MIN(V177) V177, MIN(V178) V178, MIN(V179) V179, MIN(V180) V180, MIN(V181) V181, MIN(V182) V182, MIN(V183) V183, MIN(V184) V184, MIN(V185) V185, MIN(V186) V186, MIN(V187) V187, MIN(V188) V188, MIN(V189) V189, MIN(V190) V190, MIN(V191) V191, 
			MIN(V192) V192, MIN(V193) V193, MIN(V194) V194, MIN(V195) V195, MIN(V196) V196, MIN(V197) V197, MIN(V198) V198, MIN(V199) V199, MIN(V200) V200, MIN(V201) V201, MIN(V202) V202, MIN(V203) V203, MIN(V204) V204, MIN(V205) V205, MIN(V206) V206, MIN(V207) V207, 
			MIN(V208) V208, MIN(V209) V209, MIN(V210) V210, MIN(V211) V211, MIN(V212) V212, MIN(V213) V213, MIN(V214) V214, MIN(V215) V215, MIN(V216) V216, MIN(V217) V217, MIN(V218) V218, MIN(V219) V219, MIN(V220) V220, MIN(V221) V221, MIN(V222) V222, MIN(V223) V223, 
			MIN(V224) V224, MIN(V225) V225, MIN(V226) V226, MIN(V227) V227, MIN(V228) V228, MIN(V229) V229, MIN(V230) V230, MIN(V231) V231, MIN(V232) V232, MIN(V233) V233, MIN(V234) V234, MIN(V235) V235, MIN(V236) V236, MIN(V237) V237, MIN(V238) V238, MIN(V239) V239, 
			MIN(V240) V240, MIN(V241) V241, MIN(V242) V242, MIN(V243) V243, MIN(V244) V244, MIN(V245) V245, MIN(V246) V246, MIN(V247) V247, MIN(V248) V248, MIN(V249) V249, MIN(V250) V250, MIN(V251) V251, MIN(V252) V252, MIN(V253) V253, MIN(V254) V254, MIN(V255) V255
		FROM [CRC].[CQ2_SKETCH_PATH15x256_NEW] WITH (NOLOCK)
		GROUP BY CONCEPT_PATH_ID
	-- Add a primary key to the 1 row x 256 column sketch table
	ALTER TABLE [CRC].[CQ2_SKETCH_PATH8x256_NEW] ADD PRIMARY KEY (CONCEPT_PATH_ID) WITH (SORT_IN_TEMPDB=ON, DATA_COMPRESSION=PAGE)

	-- Drop temp table
	DROP TABLE #CQ2_SKETCH_PATH15

END
GO
