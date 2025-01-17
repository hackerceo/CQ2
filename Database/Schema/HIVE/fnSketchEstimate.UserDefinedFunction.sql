SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [HIVE].[fnSketchEstimate]
(
	@V FLOAT,
	@N INT,
	@J INT,
	@Bins INT,
	@Scale INT
)
RETURNS FLOAT
AS
BEGIN
	
	DECLARE @Estimate FLOAT

	SELECT @Estimate = FLOOR(M*F+0.5)
		FROM (
			SELECT 
				(CASE WHEN (E >= 5*@Bins) OR (@N = @Bins) THEN E*@Scale ELSE -fBins*LOG((fBins-fN)/fBins)*@Scale END) M, 
				(CASE WHEN @N=0 THEN 1 ELSE @J/fN END) F
			FROM (
				SELECT fN, fBins,
					fN/(@V/CAST(1073741824 AS FLOAT))*fN E
				FROM (
					SELECT CAST(@N AS FLOAT) fN, CAST(@Bins AS FLOAT) fBins
				) t
			) t
		) t

	RETURN @Estimate

END
GO
