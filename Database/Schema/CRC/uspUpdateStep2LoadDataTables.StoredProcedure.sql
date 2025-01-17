SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspUpdateStep2LoadDataTables]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- **********************************************************
	-- **********************************************************
	-- **** Load tables (Customize for your ETL...)
	-- **********************************************************
	-- **********************************************************

	INSERT INTO [CRC].[PATIENT_DIMENSION_NEW] WITH (TABLOCK)
		SELECT * FROM [CRC].[PATIENT_DIMENSION] WITH (NOLOCK)

	INSERT INTO [CRC].[VISIT_DIMENSION_NEW] WITH (TABLOCK)
		SELECT * FROM [CRC].[VISIT_DIMENSION] WITH (NOLOCK)

	INSERT INTO [CRC].[OBSERVATION_FACT_NEW] WITH (TABLOCK)
		SELECT * FROM [CRC].[OBSERVATION_FACT] WITH (NOLOCK)

	INSERT INTO [CRC].[CONCEPT_DIMENSION_NEW] WITH (TABLOCK)
		SELECT * FROM [CRC].[CONCEPT_DIMENSION] WITH (NOLOCK)


END
GO
