SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunGetNameInfo]
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
	DECLARE @GetNameInfoCategory VARCHAR(100)
	DECLARE @GetNameInfoMax INT
	DECLARE @GetNameInfoStrategy VARCHAR(100)
	DECLARE @GetNameInfoMatchStr VARCHAR(MAX)
	DECLARE @GetNameInfoCreateDateStr VARCHAR(100)
	DECLARE @GetNameInfoCreateDate DATETIME
	DECLARE @GetNameInfoAscending VARCHAR(50)
	DECLARE @SortAsc INT
	
	-- Declare response variables
	DECLARE @Response VARCHAR(MAX)
	DECLARE @ConditionType VARCHAR(100)
	DECLARE @ConditionText VARCHAR(1000)
	
	-- Declare processing variables
	DECLARE @ProcName VARCHAR(100)
	DECLARE @HaltTime DATETIME
	DECLARE @DelayMS FLOAT
	DECLARE @DelayTime VARCHAR(20)


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
			-- message_body - get_name_info
			@GetNameInfoCategory = x.value('message_body[1]/ns4:get_name_info[1]/@category[1]','VARCHAR(100)'),
			@GetNameInfoMax = x.value('message_body[1]/ns4:get_name_info[1]/@max[1]','INT'),
			@GetNameInfoStrategy = x.value('message_body[1]/ns4:get_name_info[1]/match_str[1]/@strategy[1]','VARCHAR(100)'),
			@GetNameInfoMatchStr = x.value('message_body[1]/ns4:get_name_info[1]/match_str[1]','VARCHAR(MAX)'),
			@GetNameInfoCreateDateStr = x.value('message_body[1]/ns4:get_name_info[1]/create_date[1]','VARCHAR(100)'),
			@GetNameInfoAscending = x.value('message_body[1]/ns4:get_name_info[1]/ascending[1]','VARCHAR(50)')
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
	-- **** Return Results
	-- ***************************************************************************
	-- ***************************************************************************

	SELECT @UserID = ISNULL(@UserID,@Username),
		 @FetchSize = ISNULL(@GetNameInfoMax, @FetchSize),
		 @SortAsc=(CASE WHEN @GetNameInfoAscending='true' THEN 1 ELSE -1 END),
		 @GetNameInfoCreateDate = (CASE WHEN ISNULL(@GetNameInfoCreateDateStr,'')='' THEN NULL ELSE CAST(LEFT(@GetNameInfoCreateDateStr,LEN(@GetNameInfoCreateDateStr)-6) AS DATETIME) END)

	DECLARE @HasManagerRole BIT
	SELECT @HasManagerRole = HIVE.fnHasUserRole(@ProjectID,@UserID,'MANAGER')

	SELECT @Response = CAST((
		SELECT	@ConditionType 'status/condition/@type',
 				@ConditionText 'status/condition',
				( -- Query Master
					SELECT
						m.QUERY_MASTER_ID 'query_master_id',
						REPLACE(REPLACE(REPLACE(m.NAME,'&','&amp;'),'<','&lt;'),'>','&gt;') 'name',
						m.USER_ID 'user_id',
						m.GROUP_ID 'group_id',
						m.MASTER_TYPE_CD 'master_type_cd',
						m.PLUGIN_ID 'plugin_id',
						HIVE.fnDate2Str(m.CREATE_DATE) 'create_date'
					FROM ..QT_QUERY_MASTER m
					WHERE m.QUERY_MASTER_ID IN (
						SELECT TOP(@FetchSize) m.QUERY_MASTER_ID
						FROM ..QT_QUERY_MASTER m
						WHERE ISNULL(m.DELETE_FLAG,'A') <> 'D'
							AND m.USER_ID = (CASE WHEN @HasManagerRole = 1 THEN m.USER_ID ELSE ISNULL(@UserID,m.USER_ID) END)
							AND m.GROUP_ID = ISNULL(@GroupID,m.GROUP_ID)
							AND m.NAME LIKE (CASE 
								WHEN ISNULL(@GetNameInfoMatchStr,'')='' THEN m.NAME
								WHEN @GetNameInfoStrategy='contains' THEN '%'+@GetNameInfoMatchStr+'%'
								WHEN @GetNameInfoStrategy='exact' THEN @GetNameInfoMatchStr
								WHEN @GetNameInfoStrategy='right' THEN '%'+@GetNameInfoMatchStr
								ELSE @GetNameInfoMatchStr+'%'
								END)
							AND DATEDIFF(ss,CREATE_DATE,ISNULL(@GetNameInfoCreateDate,CREATE_DATE))*@SortAsc <= 0
						ORDER BY QUERY_MASTER_ID*@SortAsc
					)
					ORDER BY m.QUERY_MASTER_ID DESC
					FOR XML PATH('query_master'), TYPE
				)
 			FROM (SELECT '' A) A
 			FOR XML PATH(''), TYPE
 		) AS NVARCHAR(MAX) )

	SELECT	@MessageBody = 
				'<message_body>'
				+ '<ns4:response xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="ns4:master_responseType">'
				+ @Response
				+ '</ns4:response>'
				+ '</message_body>'

END
GO
