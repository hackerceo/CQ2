SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PM].[uspGetServices]
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

	-- Declare variables
	DECLARE @Domain NVARCHAR(MAX)
	DECLARE @Username VARCHAR(MAX)
	DECLARE @Password VARCHAR(MAX)
	DECLARE @PasswordToken BIT
	DECLARE @PasswordTimeout INT
	DECLARE @ProjectID VARCHAR(50)

	-- Extract variables from the request message_header
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as i2b2
	)
	SELECT	@Domain = x.value('security[1]/domain[1]','NVARCHAR(MAX)'),
			@Username = x.value('security[1]/username[1]','VARCHAR(MAX)'),
			@Password = x.value('security[1]/password[1]','VARCHAR(MAX)'),
			@PasswordToken = HIVE.fnStr2Bit(x.value('security[1]/password[1]/@is_token[1]','VARCHAR(10)')),
			@PasswordTimeout = x.value('security[1]/password[1]/@token_ms_timeout[1]','INT'),
			@ProjectID = @RequestXML.value('i2b2:request[1]/message_header[1]/project_id[1]','VARCHAR(50)')
	FROM @RequestXML.nodes('i2b2:request[1]/message_header[1]') AS R(x)

	-- Authenticate username and password
	IF NOT EXISTS (
		SELECT USER_ID
			FROM ..PM_USER_DATA 
			WHERE [USER_ID] = @Username 
				AND [PASSWORD] = SubString(master.dbo.fn_varbintohexstr(HashBytes('SHA2_256', @Password)),3,32)
				AND @PasswordToken = 0 
				AND [PASSWORD] <> '' 
				AND [STATUS_CD]='A'
		UNION ALL
		SELECT s.USER_ID
			FROM ..PM_USER_SESSION s, ..PM_USER_DATA u
			WHERE s.[USER_ID] = @Username 
				AND s.SESSION_ID = @Password
				AND (@PasswordToken = 1 OR u.[PASSWORD] = '')
				AND s.EXPIRED_DATE > GetDate()
				AND s.[USER_ID] = u.[USER_ID]
				AND u.[STATUS_CD] = 'A'
	)
	BEGIN
		-- Return error message
		SELECT @StatusType = 'ERROR', @StatusText = 'Username or password does not exist', @MessageBody = NULL
		RETURN
	END
	
	-- Update session
	IF @PasswordToken = 1
	BEGIN
		UPDATE ..PM_USER_SESSION
			SET EXPIRED_DATE = DATEADD(ms,ISNULL(@PasswordTimeout,0),GetDate())
			WHERE [USER_ID] = @Username AND SESSION_ID = @Password AND 1 = 0
	END
	ELSE
	BEGIN
		EXEC HIVE.uspGetNewID 20, @Password OUTPUT
		SELECT @Password = 'SessionKey:'+@Password, @PasswordTimeout = 1800000
		UPDATE ..PM_USER_SESSION
			SET EXPIRED_DATE = GetDate()
			WHERE [USER_ID] = @Username AND (EXPIRED_DATE IS NULL OR EXPIRED_DATE > GetDate()) AND 1 = 0
		INSERT INTO ..PM_USER_SESSION (USER_ID, SESSION_ID, EXPIRED_DATE)
			SELECT @Username, @Password, DATEADD(ms,@PasswordTimeout,GetDate())
	END

	-- Get project list
	DECLARE @ProjectList TABLE (ProjectID VARCHAR(50))
	INSERT INTO @ProjectList (ProjectID)
		SELECT DISTINCT r.PROJECT_ID
			FROM ..PM_PROJECT_USER_ROLES r, ..PM_PROJECT_DATA p
			WHERE r.USER_ID = @Username
				AND r.PROJECT_ID = (CASE WHEN ISNULL(NULLIF(@ProjectID,''),'undefined') = 'undefined' THEN r.PROJECT_ID ELSE @ProjectID END)
				AND r.PROJECT_ID = p.PROJECT_ID
				AND r.STATUS_CD = 'A'
				AND p.STATUS_CD = 'A'

	-- Form MessageBody
	SELECT	@StatusType = 'DONE',
			@StatusText = 'PM processing completed',
			@MessageBody = 
				'<message_body>'
				+ '<ns4:configure>'
				+ CAST((
					SELECT TOP 1
						ENVIRONMENT_CD "environment",
						HELPURL "helpURL",
						(
							SELECT	FULL_NAME "full_name",
									@Username "user_name",
									@PasswordTimeout "password/@token_ms_timeout",
									'true' "password/@is_token",
									@Password "password",
									@Domain "domain",
									'false' "is_admin",
									(
										SELECT	PROJECT_ID "@id",
												PROJECT_NAME "name",
												PROJECT_WIKI "wiki",
												PROJECT_PATH "path",
												(
													SELECT USER_ROLE_CD "role"
														FROM ..PM_PROJECT_USER_ROLES r
														WHERE r.PROJECT_ID = d.PROJECT_ID AND USER_ID = @Username
															AND r.STATUS_CD = 'A'
														FOR XML PATH(''), TYPE
												),
												(
													SELECT	PARAM_NAME_CD "param/@name",
															VALUE "param"
													FROM ..PM_PROJECT_PARAMS p
													WHERE p.PROJECT_ID = d.PROJECT_ID
														AND p.STATUS_CD = 'A'
													FOR XML PATH(''), TYPE
												)
											FROM ..PM_PROJECT_DATA d
											WHERE PROJECT_ID IN (SELECT ProjectID FROM @ProjectList)
											FOR XML PATH('project'), TYPE
									),
									(
										SELECT	PARAM_NAME_CD "param/@name",
												VALUE "param"
										FROM ..PM_USER_PARAMS
										WHERE USER_ID = @Username
											AND STATUS_CD = 'A'
										FOR XML PATH(''), TYPE
									)
								FROM ..PM_USER_DATA
								WHERE USER_ID = @Username
								FOR XML PATH(''), TYPE
						) "user",
						DOMAIN_NAME "domain_name",
						DOMAIN_ID "domain_id",
						'true' "active",
						(
							SELECT	PARAM_NAME_CD "param/@name",
									VALUE "param"
							FROM ..PM_HIVE_PARAMS p
							WHERE p.DOMAIN_ID = h.DOMAIN_ID
								AND p.STATUS_CD = 'A'
							FOR XML PATH(''), TYPE
						),
						(
							SELECT	CELL_ID "cell_data/@id",
									NAME "cell_data/name",
									URL "cell_data/url",
									PROJECT_PATH "cell_data/project_path",
									METHOD_CD "cell_data/method",
									(CASE WHEN CAN_OVERRIDE = 1 THEN 'true' ELSE 'false' END) "cell_data/can_override",
									(
										SELECT	PARAM_NAME_CD "param/@name",
												VALUE "param"
										FROM ..PM_CELL_PARAMS p
										WHERE p.CELL_ID = t.CELL_ID
											--PROJECT_PATH
											AND STATUS_CD = 'A'
										FOR XML PATH(''), TYPE
									) "cell_data"
								FROM (
									SELECT	c.CELL_ID, c.PROJECT_PATH, c.NAME, c.METHOD_CD, c.URL, c.CAN_OVERRIDE,
										ROW_NUMBER() OVER (PARTITION BY c.CELL_ID ORDER BY c.PROJECT_PATH DESC) k
									FROM ..PM_CELL_DATA c, ..PM_PROJECT_DATA p
									WHERE p.PROJECT_ID IN (SELECT ProjectID FROM @ProjectList)
										AND p.PROJECT_PATH LIKE c.PROJECT_PATH+'%'
										AND c.STATUS_CD = 'A'
								) t
								WHERE k = 1
								FOR XML PATH(''), TYPE
						) "cell_datas"
					FROM ..PM_HIVE_DATA h
					WHERE ACTIVE = 1 AND STATUS_CD = 'A'
					FOR XML PATH(''), TYPE
				) AS NVARCHAR(MAX))
				+ '</ns4:configure>'
				+ '</message_body>'

END
GO
