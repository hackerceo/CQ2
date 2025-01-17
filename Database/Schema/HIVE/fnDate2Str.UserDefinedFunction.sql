SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [HIVE].[fnDate2Str]
(
	@Date DATETIME
)
RETURNS VARCHAR(100)
AS
BEGIN

	DECLARE @timezone_offset_string VARCHAR(8)
	DECLARE @timezone_offset VARCHAR(2)
	
    -- Get Timezone offset to create xml acceptable datetimes
	SELECT	@timezone_offset = DATEDIFF(hh,GETDATE(),GETUTCDATE()),
			@timezone_offset_string = CASE WHEN @timezone_offset<9 THEN '-0' ELSE '' END + @timezone_offset + ':00'
   
	RETURN convert(varchar(50),@Date,126)+@timezone_offset_string 

END
GO
