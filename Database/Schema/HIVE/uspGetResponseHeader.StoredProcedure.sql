SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [HIVE].[uspGetResponseHeader]
	@Info NVARCHAR(MAX) = NULL,
	@StatusType NVARCHAR(MAX) = NULL,
	@StatusText NVARCHAR(MAX) = NULL,
	@PollingInterval NVARCHAR(MAX) = NULL,
	@PollingURL NVARCHAR(MAX) = NULL,
	@ResponseHeader NVARCHAR(MAX) OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	SELECT @ResponseHeader =	'<response_header>'
								+ ISNULL('<info>' + @Info + '</info>','')
								+ '<result_status>'
								+ '<status type="' + ISNULL(@StatusType,'ERROR') + '"' + HIVE.fnXMLValue('status',@StatusText)
								+ ISNULL('<polling_url interval_ms="' + @PollingInterval + '">' + @PollingURL + '</polling_url>','')
								+ '</result_status>'
								+ '</response_header>'

END
GO
