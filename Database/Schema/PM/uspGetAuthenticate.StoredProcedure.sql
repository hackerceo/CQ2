SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PM].[uspGetAuthenticate]
	@Request NVARCHAR(MAX) = NULL,
	@IPAddress VARCHAR(50) = NULL
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	BEGIN TRY

		-- Declare variables
		DECLARE @RequestXML XML
		DECLARE @Username VARCHAR(50)
		DECLARE @Password VARCHAR(255)
		DECLARE @PasswordToken BIT
		DECLARE @Authenticated TINYINT
		DECLARE @TryCustomAuthenticate BIT
		
		SELECT @Authenticated = 0, @TryCustomAuthenticate = 0

		-- Convert the request message to XML
		SELECT @RequestXML = CAST(@Request AS XML)
		
		-- Extract username and password
		SELECT @Username = x.value('security[1]/username[1]','VARCHAR(50)'),
				@Password = x.value('security[1]/password[1]','VARCHAR(50)'),
				@PasswordToken = HIVE.fnStr2Bit(x.value('security[1]/password[1]/@is_token[1]','VARCHAR(10)'))
			FROM (SELECT @RequestXML.query('//security') x) t

		-- Try to authenticate
		IF @Username<>'' AND @Password<>''
		BEGIN
			SELECT @Authenticated = 1
				WHERE EXISTS (
					SELECT USER_ID
						FROM PM.PM_USER_DATA 
						WHERE [USER_ID] = @Username 
							AND [PASSWORD] = SubString(master.dbo.fn_varbintohexstr(HashBytes('SHA2_256', @Password)),3,32)
							AND @PasswordToken = 0 
							AND [PASSWORD] <> '' 
							AND [STATUS_CD]='A'
					UNION ALL
					SELECT s.USER_ID
						FROM PM.PM_USER_SESSION s, PM.PM_USER_DATA u
						WHERE s.[USER_ID] = @Username 
							AND s.SESSION_ID = @Password
							AND (@PasswordToken = 1 OR u.[PASSWORD] = '')
							AND s.EXPIRED_DATE > GetDate()
							AND s.[USER_ID] = u.[USER_ID]
							AND u.[STATUS_CD] = 'A'
				)
			SELECT @TryCustomAuthenticate = 1
				FROM PM.PM_USER_DATA
				WHERE @Authenticated = 0
					AND [USER_ID] = @Username
					AND [PASSWORD] = ''
		END
		
		IF @TryCustomAuthenticate = 0
		BEGIN
			INSERT INTO HIVE.AuthenticateLog (Username, RequestDate, IPAddress, Success)
				SELECT @Username, GETDATE(), @IPAddress, @Authenticated
		END
				
		SELECT 0 Error, @Authenticated Authenticated, @Username Username, @Password Password, @TryCustomAuthenticate TryCustomAuthenticate

	END TRY
	BEGIN CATCH

		INSERT INTO HIVE.AuthenticateLog (Username, RequestDate, IPAddress, Success)
			SELECT NULL, GETDATE(), @IPAddress, 0

		SELECT 1 Error, 0 Authenticated, '' Username, '' Password, 0 TryCustomAuthenticate

	END CATCH
	
	
END
GO
