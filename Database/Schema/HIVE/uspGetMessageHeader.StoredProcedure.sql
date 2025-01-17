SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [HIVE].[uspGetMessageHeader]
	@RequestXML XML,
	@SendingAppName NVARCHAR(MAX),
	@SendingAppVersion NVARCHAR(MAX),
	@ReceivingAppName NVARCHAR(MAX),
	@ReceivingAppVersion NVARCHAR(MAX),
	@MessageHeader NVARCHAR(MAX) OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @MessageNum NVARCHAR(100)
	DECLARE @InstanceNum NVARCHAR(100)
	DECLARE @ProjectID NVARCHAR(MAX)

	DECLARE @Domain NVARCHAR(MAX)
	DECLARE @Username NVARCHAR(MAX)
	DECLARE @Password NVARCHAR(MAX)

	-- Extract variables from the request message_header
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as i2b2
	)
	SELECT	@Domain = x.value('security[1]/domain[1]','NVARCHAR(MAX)'),
			@Username = x.value('security[1]/username[1]','NVARCHAR(MAX)'),
			@Password = x.value('security[1]/password[1]','NVARCHAR(MAX)'),
			@MessageNum = @RequestXML.value('i2b2:request[1]/message_header[1]/message_control_id[1]/message_num[1]','NVARCHAR(100)'),
			@InstanceNum = @RequestXML.value('i2b2:request[1]/message_header[1]/message_control_id[1]/instance_num[1]','NVARCHAR(100)'),
			@ProjectID = @RequestXML.value('i2b2:request[1]/message_header[1]/project_id[1]','NVARCHAR(100)')
	FROM @RequestXML.nodes('i2b2:request[1]/message_header[1]') AS R(x)

	-- Generate a message_num if one doesn't exist in the request	
	IF @MessageNum IS NULL
		EXEC HIVE.uspGetNewID 20, @MessageNum OUTPUT

	-- Add one to the instance_num
	SELECT @InstanceNum = (CASE WHEN IsNumeric(@InstanceNum) = 1 THEN CAST(CAST(@InstanceNum AS INT)+1 AS NVARCHAR(100)) ELSE '1' END)

	-- Form the response message_header	
	SELECT @MessageHeader = 
		'	<message_header>
				<i2b2_version_compatible>1.1</i2b2_version_compatible>
				<hl7_version_compatible>2.4</hl7_version_compatible>
				<sending_application>
					<application_name>' + ISNULL(@SendingAppName,'') + '</application_name>
					<application_version>' + ISNULL(@SendingAppVersion,'') + '</application_version>
				</sending_application>
				<sending_facility>
					<facility_name>i2b2 Hive</facility_name>
				</sending_facility>
				<receiving_application>
					<application_name>' + ISNULL(@ReceivingAppName,'') + '</application_name>
					<application_version>' + ISNULL(@ReceivingAppVersion,'') + '</application_version>
				</receiving_application>
				<receiving_facility>
					<facility_name>i2b2 Hive</facility_name>
				</receiving_facility>
				<datetime_of_message>' + CONVERT(NVARCHAR(MAX),GetDate(),127) + 'Z</datetime_of_message>
				<message_control_id>
					<message_num>' + @MessageNum + '</message_num>
					<instance_num>' + @InstanceNum + '</instance_num>
				</message_control_id>
				<processing_id>
					<processing_id>P</processing_id>
					<processing_mode>I</processing_mode>
				</processing_id>
				<accept_acknowledgement_type>AL</accept_acknowledgement_type>
				<application_acknowledgement_type>AL</application_acknowledgement_type>
				<country_code>US</country_code>
				<project_id>' + ISNULL(NULLIF(@ProjectID,''),'undefined') + '</project_id>
			</message_header>
		'

END
GO
