SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [HIVE].[uspGetStandardResponse]
	@RequestXML XML,
	@SendingAppName VARCHAR(MAX),
	@SendingAppVersion VARCHAR(MAX),
	@ReceivingAppName VARCHAR(MAX),
	@ReceivingAppVersion VARCHAR(MAX),
	@Operation VARCHAR(MAX),
	@OperationProcedure VARCHAR(MAX),
	@MessageTag VARCHAR(MAX),
	@MessageNamespaces VARCHAR(MAX),
	@RequestType VARCHAR(100) = NULL OUTPUT,
	@ResponseXML XML = NULL OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Declare variables
	DECLARE @MessageHeader NVARCHAR(MAX)
	DECLARE @ResponseHeader NVARCHAR(MAX)
	DECLARE @MessageBody NVARCHAR(MAX)
	DECLARE @StatusType NVARCHAR(100)
	DECLARE @StatusText NVARCHAR(MAX)

	-- Get the message header
	EXEC HIVE.uspGetMessageHeader	@RequestXML = @RequestXML,
									@SendingAppName = @SendingAppName,
									@SendingAppVersion = @SendingAppVersion,
									@ReceivingAppName = @ReceivingAppName,
									@ReceivingAppVersion = @ReceivingAppVersion,
									@MessageHeader = @MessageHeader OUTPUT
		
	-- Get the message body
	IF @OperationProcedure IS NOT NULL
		EXEC @OperationProcedure	@Operation = @Operation,
									@RequestXML = @RequestXML,
									@RequestType = @RequestType OUTPUT,
									@StatusType = @StatusType OUTPUT,
									@StatusText = @StatusText OUTPUT,
									@MessageBody = @MessageBody OUTPUT
	ELSE
		SELECT @StatusType = 'ERROR', @StatusText = 'The requested operation is not supported'

	-- Get the response header
	EXEC HIVE.uspGetResponseHeader	@StatusType = @StatusType,
									@StatusText = @StatusText,
									@ResponseHeader = @ResponseHeader OUTPUT

	-- Form the response message
	SELECT @ResponseXML = CAST(
								'<' + @MessageTag + ' ' + @MessageNamespaces + '>'
								+ ISNULL(@MessageHeader,'')
								+ ISNULL(@ResponseHeader,'')
								+ ISNULL(@MessageBody,'')
								+ '</' + @MessageTag + '>'
							AS XML)

END
GO
