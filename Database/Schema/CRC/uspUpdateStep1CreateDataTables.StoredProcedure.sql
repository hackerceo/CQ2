SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspUpdateStep1CreateDataTables]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- **********************************************************
	-- **********************************************************
	-- **** Create new tables
	-- **********************************************************
	-- **********************************************************

	CREATE TABLE [CRC].[PATIENT_DIMENSION_NEW](
		[PATIENT_NUM] [int] NOT NULL,
		[VITAL_STATUS_CD] [varchar](50) NULL,
		[BIRTH_DATE] [datetime] NULL,
		[DEATH_DATE] [datetime] NULL,
		[SEX_CD] [varchar](50) NULL,
		[AGE_IN_YEARS_NUM] [int] NULL,
		[LANGUAGE_CD] [varchar](50) NULL,
		[RACE_CD] [varchar](50) NULL,
		[MARITAL_STATUS_CD] [varchar](50) NULL,
		[RELIGION_CD] [varchar](50) NULL,
		[ZIP_CD] [varchar](10) NULL,
		[STATECITYZIP_PATH] [varchar](700) NULL,
		[INCOME_CD] [varchar](50) NULL,
		[PATIENT_BLOB] [varchar](max) NULL,
		[UPDATE_DATE] [datetime] NULL,
		[DOWNLOAD_DATE] [datetime] NULL,
		[IMPORT_DATE] [datetime] NULL,
		[SOURCESYSTEM_CD] [varchar](50) NULL,
		[UPLOAD_ID] [int] NULL
	)

	CREATE TABLE [CRC].[VISIT_DIMENSION_NEW](
		[ENCOUNTER_NUM] [int] NOT NULL,
		[PATIENT_NUM] [int] NOT NULL,
		[ACTIVE_STATUS_CD] [varchar](50) NULL,
		[START_DATE] [datetime] NULL,
		[END_DATE] [datetime] NULL,
		[INOUT_CD] [varchar](50) NULL,
		[LOCATION_CD] [varchar](50) NULL,
		[LOCATION_PATH] [varchar](900) NULL,
		[LENGTH_OF_STAY] [int] NULL,
		[VISIT_BLOB] [varchar](max) NULL,
		[UPDATE_DATE] [datetime] NULL,
		[DOWNLOAD_DATE] [datetime] NULL,
		[IMPORT_DATE] [datetime] NULL,
		[SOURCESYSTEM_CD] [varchar](50) NULL,
		[UPLOAD_ID] [int] NULL
	)

	CREATE TABLE [CRC].[OBSERVATION_FACT_NEW](
		[ENCOUNTER_NUM] [int] NOT NULL,
		[PATIENT_NUM] [int] NOT NULL,
		[CONCEPT_CD] [varchar](50) NOT NULL,
		[PROVIDER_ID] [varchar](50) NOT NULL,
		[START_DATE] [datetime] NOT NULL,
		[MODIFIER_CD] [varchar](100) NOT NULL,
		[INSTANCE_NUM] [int] NOT NULL,
		[VALTYPE_CD] [varchar](50) NULL,
		[TVAL_CHAR] [varchar](255) NULL,
		[NVAL_NUM] [decimal](18, 5) NULL,
		[VALUEFLAG_CD] [varchar](50) NULL,
		[QUANTITY_NUM] [decimal](18, 5) NULL,
		[UNITS_CD] [varchar](50) NULL,
		[END_DATE] [datetime] NULL,
		[LOCATION_CD] [varchar](50) NULL,
		[OBSERVATION_BLOB] [varchar](max) NULL,
		[CONFIDENCE_NUM] [decimal](18, 5) NULL,
		[UPDATE_DATE] [datetime] NULL,
		[DOWNLOAD_DATE] [datetime] NULL,
		[IMPORT_DATE] [datetime] NULL,
		[SOURCESYSTEM_CD] [varchar](50) NULL,
		[UPLOAD_ID] [int] NULL,
		[TEXT_SEARCH_INDEX] [int] NULL
	)
	ALTER TABLE [CRC].[OBSERVATION_FACT_NEW] ADD DEFAULT ('@') FOR [MODIFIER_CD]
	ALTER TABLE [CRC].[OBSERVATION_FACT_NEW] ADD DEFAULT ((1)) FOR [INSTANCE_NUM]

	CREATE TABLE [CRC].[CONCEPT_DIMENSION_NEW](
		[CONCEPT_PATH] [varchar](700) NOT NULL,
		[CONCEPT_CD] [varchar](50) NULL,
		[NAME_CHAR] [varchar](2000) NULL,
		[CONCEPT_BLOB] [varchar](max) NULL,
		[UPDATE_DATE] [datetime] NULL,
		[DOWNLOAD_DATE] [datetime] NULL,
		[IMPORT_DATE] [datetime] NULL,
		[SOURCESYSTEM_CD] [varchar](50) NULL,
		[UPLOAD_ID] [int] NULL
	)


END
GO
