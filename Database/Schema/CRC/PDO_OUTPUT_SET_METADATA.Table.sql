SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [CRC].[PDO_OUTPUT_SET_METADATA](
	[PDOSet] [varchar](50) NOT NULL,
	[ColumnName] [varchar](50) NOT NULL,
	[DataColumn] [varchar](50) NULL,
	[SortOrder] [int] NULL,
	[IsKey] [bit] NULL,
	[IsParam] [bit] NULL,
	[IsBlob] [bit] NULL,
	[IsTechData] [bit] NULL,
	[DataType] [varchar](50) NULL,
	[XmlEscape] [bit] NULL,
	[Description] [varchar](250) NULL,
	[CodeNameLookup] [bit] NULL,
	[CodeNameColumn] [varchar](50) NULL,
	[SourceColumn] [varchar](50) NULL,
	[StatusColumn] [varchar](50) NULL,
PRIMARY KEY CLUSTERED 
(
	[PDOSet] ASC,
	[ColumnName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
