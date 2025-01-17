SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [CRC].[CQ2_FACT_COUNTS_PATH](
	[CONCEPT_PATH_ID] [int] NOT NULL,
	[NUM_PATIENTS] [int] NULL,
	[NUM_ENCOUNTERS] [bigint] NULL,
	[NUM_INSTANCES] [bigint] NULL,
	[NUM_FACTS] [bigint] NULL,
	[FIRST_START] [datetime] NULL,
	[LAST_START] [datetime] NULL,
	[LAST_END] [datetime] NULL,
	[MIN_NVAL_NUM] [decimal](18, 5) NULL,
	[MAX_NVAL_NUM] [decimal](18, 5) NULL,
	[MIN_NVAL_L] [bit] NULL,
	[MAX_NVAL_G] [bit] NULL,
	[MAX_OCCURS] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[CONCEPT_PATH_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
