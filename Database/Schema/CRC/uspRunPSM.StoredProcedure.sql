SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunPSM]
	@Operation VARCHAR(100),
	@RequestXML XML,
	@RequestType VARCHAR(100) OUTPUT,
	@StatusType NVARCHAR(100) OUTPUT,
	@StatusText NVARCHAR(MAX) OUTPUT,
	@MessageBody NVARCHAR(MAX) OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Declare Variables
	-- ***************************************************************************
	-- ***************************************************************************

	-- Declare request variables
	DECLARE @DomainID VARCHAR(50)
	DECLARE @Username VARCHAR(50)
	DECLARE @ProjectID VARCHAR(50)
	DECLARE @ResultWaittimeMS BIGINT
	DECLARE @UserID VARCHAR(100)
	DECLARE @GroupID VARCHAR(100)
	DECLARE @FetchSize INT
	DECLARE @QueryMasterID INT
	DECLARE @QueryInstanceID INT
	DECLARE @QueryResultInstanceID INT
	DECLARE @QueryName	VARCHAR(250)
	DECLARE @QueryDefinition XML
	DECLARE @ResultOutputList XML
	
	-- Declare response variables
	DECLARE @Response VARCHAR(MAX)
	DECLARE @ConditionType VARCHAR(100)
	DECLARE @ConditionText VARCHAR(1000)
	
	-- Declare processing variables
	DECLARE @ProcName VARCHAR(100)
	DECLARE @HaltTime DATETIME
	DECLARE @DelayMS FLOAT
	DECLARE @DelayTime VARCHAR(20)
	
/*
	DECLARE @ResultStatus INT
	DECLARE @MessageHeader XML
	DECLARE @ResultCount INT
	DECLARE @PatientSet BIT
	DECLARE @PatientCountXML BIT
	DECLARE @ThresholdTime	DATETIME
	DECLARE @EstTime INT
	DECLARE @QueryInstanceStatus INT
*/

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Parse Request Message
	-- ***************************************************************************
	-- ***************************************************************************


	-- Extract variables from the request message
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as ns6,
		'http://www.i2b2.org/xsd/cell/crc/psm/1.1/' as ns4
	)
	SELECT	-- message_header
			@DomainID = x.value('message_header[1]/security[1]/domain[1]','varchar(50)'),
			@Username = x.value('message_header[1]/security[1]/username[1]','VARCHAR(50)'),
			@ProjectID = x.value('message_header[1]/project_id[1]','VARCHAR(50)'),
			-- request_header
			@ResultWaittimeMS = x.value('request_header[1]/result_waittime_ms[1]','INT'),
			-- message_body - psmheader
			@RequestType = x.value('message_body[1]/ns4:psmheader[1]/request_type[1]','VARCHAR(100)'),
			-- message_body - request
			@UserID = x.value('message_body[1]/ns4:request[1]/user_id[1]','VARCHAR(100)'),
			@GroupID = x.value('message_body[1]/ns4:request[1]/group_id[1]','VARCHAR(100)'),
			@FetchSize = x.value('message_body[1]/ns4:request[1]/fetch_size[1]','INT'),
			--@QueryMasterID = x.value('message_body[1]/ns4:request[1]/query_master_id[1]','VARCHAR(100)'),
			@QueryMasterID = (CASE WHEN query_master_id='false' THEN NULL WHEN left(query_master_id,9)='masterid:' THEN substring(query_master_id,10,99) ELSE query_master_id END),
			@QueryInstanceID = x.value('message_body[1]/ns4:request[1]/query_instance_id[1]','VARCHAR(100)'),
			@QueryResultInstanceID = x.value('message_body[1]/ns4:request[1]/query_result_instance_id[1]','VARCHAR(100)'),
			@QueryName = x.value('message_body[1]/ns4:request[1]/query_name[1]','VARCHAR(250)'),
			@QueryDefinition = x.query('message_body[1]/ns4:request[1]/query_definition[1]'),
			@ResultOutputList = x.query('message_body[1]/ns4:request[1]/result_output_list[1]')
		FROM @RequestXML.nodes('ns6:request[1]') AS R(x)
			CROSS APPLY (SELECT x.value('message_body[1]/ns4:request[1]/query_master_id[1]','VARCHAR(100)') query_master_id) q

	-- Set default values
 	SELECT	@FetchSize = IsNull(@FetchSize,99999999),
  			@ResultWaittimeMS = IsNull(@ResultWaittimeMS,180000),
 			@HaltTime = DateAdd(ms,@ResultWaittimeMS,GetDate()),
 			@DelayMS = 100,
			@ConditionType = 'DONE',
 			@ConditionText = 'DONE',
 			@StatusType = 'DONE',
 			@StatusText = 'DONE'

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Security
	-- ***************************************************************************
	-- ***************************************************************************

	IF (IsNull(@Username,'') = '') OR (@Username <> @UserID)
	BEGIN
		RETURN;
	END

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Perform Actions
	-- ***************************************************************************
	-- ***************************************************************************

	IF @RequestType = 'CRC_QRY_renameQueryMaster'
	BEGIN
		UPDATE ..QT_QUERY_MASTER
			SET NAME = @QueryName
			WHERE QUERY_MASTER_ID = @QueryMasterID
	END
	
	IF @RequestType = 'CRC_QRY_deleteQueryMaster'
	BEGIN
		UPDATE ..QT_QUERY_MASTER
			SET DELETE_FLAG = 'D', DELETE_DATE = GetDate() 
			WHERE QUERY_MASTER_ID = @QueryMasterID
	END
	
	IF @RequestType = 'CRC_QRY_runQueryInstance_fromQueryDefinition'
	BEGIN
		-- Create the Query Master
		SELECT @QueryName = @QueryDefinition.value('query_definition[1]/query_name[1]','VARCHAR(250)')
		INSERT INTO ..QT_QUERY_MASTER (NAME, USER_ID, GROUP_ID, CREATE_DATE, DELETE_FLAG, REQUEST_XML, I2B2_REQUEST_XML)
			SELECT @QueryName, @Username, @ProjectID, GetDate(), 'A', CAST(@QueryDefinition AS VARCHAR(MAX)), CAST(@RequestXML AS VARCHAR(MAX))
		SELECT @QueryMasterID = @@IDENTITY
		-- Create the Query Instance
		INSERT INTO ..QT_QUERY_INSTANCE (QUERY_MASTER_ID, USER_ID, GROUP_ID, START_DATE, DELETE_FLAG, STATUS_TYPE_ID)
			SELECT @QueryMasterID, @Username, @ProjectID, GetDate(), 'A', 1
		SELECT @QueryInstanceID = @@IDENTITY
		-- Run the Query Instance
		IF 1=1
		BEGIN
			-- Run sychronously
			SELECT @ProcName = OBJECT_SCHEMA_NAME(@@PROCID)+'.uspRunQueryInstance'
			EXEC @ProcName @QueryInstanceID = @QueryInstanceID, @DomainID = @DomainID, @UserID = @Username, @ProjectID = @ProjectID
		END
		ELSE
		BEGIN
			-- Run asychronously
			-- Add Query Instance to Service Broker
			-- Loop until done or timeout
			WHILE EXISTS (
				SELECT * 
				FROM ..QT_QUERY_INSTANCE 
				WHERE GetDate() < @HaltTime AND @DelayMS < 24*60*60*1000 -- (Delay less than 24 hours)
					AND QUERY_INSTANCE_ID = @QueryInstanceID AND STATUS_TYPE_ID IN (1,5) -- (QUEUED, INCOMPLETE)
			)
			BEGIN
				SELECT	@DelayTime = CONVERT(VARCHAR,DateAdd(ms,@DelayMS,GetDate()),114),
						@DelayMS = @DelayMS * 0.25
				WAITFOR TIME @DelayTime ;
			END
		END
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Return Results
	-- ***************************************************************************
	-- ***************************************************************************

	DECLARE @ResponseItems TABLE (
		RequestType VARCHAR(100),
		QueryMaster BIT,
		QueryInstance BIT,
		QueryResultInstance BIT,
		ResultType BIT,
		ResultDocument BIT,
		QmName BIT,
		QmUserID BIT,
		QmGroupID BIT,
		QmCreateDate BIT,
		QmRequestXML BIT,
		QmEncodedRequestXML BIT,
		ns4Type VARCHAR(1000)
	)
	INSERT INTO @ResponseItems (RequestType,
								QueryMaster, QueryInstance, QueryResultInstance, ResultType, ResultDocument,
								QmName, QmUserID, QmGroupID, QmCreateDate, QmRequestXML, QmEncodedRequestXML,
								ns4Type)
		SELECT				'CRC_QRY_getResultType',									0,0,0,1,0,	0,0,0,0,0,0,	'result_type_responseType'
		UNION ALL SELECT	'CRC_QRY_getRequestXml_fromQueryMasterId',					1,0,0,0,0,	1,1,0,0,1,0,	'master_responseType'
		UNION ALL SELECT	'CRC_QRY_getQueryMasterList_fromUserId',					1,0,0,0,0,	1,1,1,1,0,0,	'master_responseType'
		UNION ALL SELECT	'CRC_QRY_getQueryMasterList_fromGroupId',					1,0,0,0,0,	1,1,1,1,0,0,	'master_responseType'
		UNION ALL SELECT	'CRC_QRY_renameQueryMaster',								1,0,0,0,0,	1,1,0,0,0,0,	'master_responseType'
		UNION ALL SELECT	'CRC_QRY_deleteQueryMaster',								1,0,0,0,0,	0,0,0,0,0,0,	'master_responseType'
		UNION ALL SELECT	'CRC_QRY_runQueryInstance_fromQueryDefinition',				1,1,1,0,0,	1,1,1,1,0,1,	'master_instance_result_responseType'
		UNION ALL SELECT	'CRC_QRY_runQueryInstance_fromQueryMasterId',				1,1,1,0,0,	1,1,1,1,0,1,	'master_instance_result_responseType'
		UNION ALL SELECT	'CRC_QRY_getQueryInstanceList_fromQueryMasterId',			0,1,0,0,0,	0,0,0,0,0,0,	'instance_responseType'
		UNION ALL SELECT	'CRC_QRY_getQueryResultInstanceList_fromQueryInstanceId',	0,0,1,0,0,	0,0,0,0,0,0,	'result_responseType'
		UNION ALL SELECT	'CRC_QRY_getResultDocument_fromResultInstanceId',			0,0,1,0,1,	0,0,0,0,0,0,	'crc_xml_result_responseType'

	DECLARE @HasManagerRole BIT
	SELECT @HasManagerRole = HIVE.fnHasUserRole(@ProjectID,@UserID,'MANAGER')

	SELECT @Response = CAST((
		SELECT	@ConditionType 'status/condition/@type',
 				@ConditionText 'status/condition',
				( -- Query Master
					SELECT TOP (@FetchSize)
						m.QUERY_MASTER_ID 'query_master_id',
						CASE WHEN i.QmName = 1 THEN REPLACE(REPLACE(REPLACE(m.NAME,'&','&amp;'),'<','&lt;'),'>','&gt;') END 'name',
						CASE WHEN i.QmUserID = 1 THEN m.USER_ID END 'user_id',
						CASE WHEN i.QmGroupID = 1 THEN m.GROUP_ID END 'group_id',
						m.MASTER_TYPE_CD 'master_type_cd',
						m.PLUGIN_ID 'plugin_id',
						CASE WHEN i.QmCreateDate = 1 THEN HIVE.fnDate2Str(m.CREATE_DATE) END 'create_date',
						CASE WHEN i.QmRequestXML = 1 THEN CAST(REQUEST_XML AS NVARCHAR(MAX)) ELSE NULL END 'request_xml',
						CASE WHEN i.QmEncodedRequestXML = 1 THEN REPLACE(REPLACE(REPLACE(CAST(REQUEST_XML AS NVARCHAR(MAX)),'&','&amp;'),'<','&lt;'),'>','&gt;') ELSE NULL END 'request_xml'
					FROM ..QT_QUERY_MASTER m, @ResponseItems i	
					WHERE i.RequestType = @RequestType AND i.QueryMaster = 1
						AND ISNULL(m.DELETE_FLAG,'A') <> 'D'
						AND m.QUERY_MASTER_ID = ISNULL(@QueryMasterID,m.QUERY_MASTER_ID)
						AND m.USER_ID = (CASE WHEN @HasManagerRole = 1 THEN m.USER_ID ELSE ISNULL(@UserID,m.USER_ID) END)
						AND m.GROUP_ID = ISNULL(@GroupID,m.GROUP_ID)
					ORDER BY m.QUERY_MASTER_ID DESC
					FOR XML PATH('query_master'), TYPE
				),
				( -- Query Instance
					SELECT
						i.QUERY_INSTANCE_ID 'query_instance_id',
						i.QUERY_MASTER_ID 'query_master_id',
						i.USER_ID 'user_id',
						i.GROUP_ID 'group_id',
						HIVE.fnDate2Str(START_DATE) 'start_date',
						HIVE.fnDate2Str(END_DATE) 'end_date',
						s.STATUS_TYPE_ID 'query_status_type/status_type_id',
						s.NAME 'query_status_type/name',
						s.DESCRIPTION 'query_status_type/description' 
					FROM ..QT_QUERY_INSTANCE i WITH(NOLOCK)
						JOIN ..QT_QUERY_STATUS_TYPE s WITH(NOLOCK) ON s.STATUS_TYPE_ID = i.STATUS_TYPE_ID
					WHERE EXISTS (SELECT * FROM @ResponseItems WHERE RequestType = @RequestType AND QueryInstance = 1)
						AND i.QUERY_INSTANCE_ID = ISNULL(@QueryInstanceID,i.QUERY_INSTANCE_ID)
						AND i.QUERY_MASTER_ID = ISNULL(@QueryMasterID,i.QUERY_MASTER_ID)
					ORDER BY i.QUERY_INSTANCE_ID
					FOR XML PATH('query_instance'), TYPE
				),
				( -- Query Result Instance	 							 
					SELECT
						r.RESULT_INSTANCE_ID 'result_instance_id',
						r.QUERY_INSTANCE_ID 'query_instance_id',
						REPLACE(REPLACE(REPLACE(CAST(r.DESCRIPTION AS NVARCHAR(MAX)),'&','&amp;'),'<','&lt;'),'>','&gt;') 'description',
						--r.DESCRIPTION 'description',
						t.RESULT_TYPE_ID 'query_result_type/result_type_id', 
						t.NAME 'query_result_type/name',
						t.DISPLAY_TYPE_ID 'query_result_type/display_type',
						t.VISUAL_ATTRIBUTE_TYPE_ID 'query_result_type/visual_attribute_type',
						t.DESCRIPTION 'query_result_type/description',
						r.SET_SIZE 'set_size',
						HIVE.fnDate2Str(r.START_DATE) 'start_date',
						HIVE.fnDate2Str(r.END_DATE) 'end_date',
						s.STATUS_TYPE_ID 'query_status_type/status_type_id',	
						s.NAME 'query_status_type/name',
						s.DESCRIPTION  'query_status_type/description'
					FROM ..QT_QUERY_RESULT_INSTANCE r WITH(NOLOCK)
						JOIN ..QT_QUERY_STATUS_TYPE s WITH(NOLOCK) ON s.STATUS_TYPE_ID = r.STATUS_TYPE_ID
						JOIN ..QT_QUERY_RESULT_TYPE t WITH(NOLOCK) ON t.RESULT_TYPE_ID = r.RESULT_TYPE_ID
					WHERE EXISTS (SELECT * FROM @ResponseItems WHERE RequestType = @RequestType AND QueryResultInstance = 1)
						AND r.QUERY_INSTANCE_ID = ISNULL(@QueryInstanceID,r.QUERY_INSTANCE_ID)
						AND r.RESULT_INSTANCE_ID = ISNULL(@QueryResultInstanceID,r.RESULT_INSTANCE_ID)
					ORDER BY r.RESULT_INSTANCE_ID
					FOR XML PATH('query_result_instance'), TYPE	 
				),
				( -- Result Type
					SELECT
						t.RESULT_TYPE_ID 'result_type_id',
						t.NAME 'name',
						t.DISPLAY_TYPE_ID 'display_type',
						t.VISUAL_ATTRIBUTE_TYPE_ID 'visual_attribute_type',
						t.DESCRIPTION 'description'
					FROM ..QT_QUERY_RESULT_TYPE t, @ResponseItems i
					WHERE i.RequestType = @RequestType AND i.ResultType = 1
						--AND t.RESULT_TYPE_ID = 4 -- Patient_Count_XML only
					ORDER BY t.RESULT_TYPE_ID
					FOR XML PATH('query_result_type'), TYPE	 
				),
				( -- Result Document
					SELECT
						r.XML_RESULT_ID 'xml_result_id',
						r.RESULT_INSTANCE_ID 'result_instance_id',
						REPLACE(REPLACE(REPLACE(CAST(r.XML_VALUE AS NVARCHAR(MAX)),'&','&amp;'),'<','&lt;'),'>','&gt;') 'xml_value'
					FROM ..QT_XML_RESULT r, @ResponseItems i
					WHERE r.RESULT_INSTANCE_ID = @QueryResultInstanceID AND i.ResultDocument = 1
					ORDER BY r.XML_RESULT_ID
					FOR XML PATH('crc_xml_result'), TYPE
				)  
 			FROM (SELECT '' A) A
 			FOR XML PATH(''), TYPE
 		) AS NVARCHAR(MAX) )

	SELECT	@MessageBody = 
				'<message_body>'
				+ '<ns4:response xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="ns4:'
				+ IsNull((SELECT TOP 1 ns4Type FROM @ResponseItems WHERE RequestType = @RequestType),'master_responseType')
				+ '">'
				+ @Response
				+ '</ns4:response>'
				+ '</message_body>'


/*
	CRC_QRY_getResultType

	CRC_QRY_getQueryMasterList_fromGroupId
	CRC_QRY_getQueryMasterList_fromUserId
	CRC_QRY_getQueryInstanceList_fromQueryMasterId
	CRC_QRY_getQueryResultInstanceList_fromQueryInstanceId
	CRC_QRY_getResultDocument_fromResultInstanceId

	CRC_QRY_runQueryInstance_fromQueryDefinition

	CRC_QRY_getRequestXml_fromQueryMasterId

	CRC_QRY_renameQueryMaster
	CRC_QRY_deleteQueryMaster
	
*/



END
GO
