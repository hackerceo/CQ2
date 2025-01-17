SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PM].[uspConvertToToken]
	@Request NVARCHAR(MAX),
	@UserID VARCHAR(50),
	@IPAddress VARCHAR(50) = NULL
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Define the token timeout period
	DECLARE @TokenTimeout INT
	SELECT @TokenTimeout = 15 -- minutes

	-- Get a session_id
	DECLARE @Password VARCHAR(MAX)
	EXEC HIVE.uspGetNewID 20, @Password OUTPUT
	SELECT @Password = 'SessionKey:'+@Password
	UPDATE PM.PM_USER_SESSION
		SET EXPIRED_DATE = GetDate()
		WHERE [USER_ID] = @UserID AND (EXPIRED_DATE IS NULL OR EXPIRED_DATE > GetDate())
	INSERT INTO PM.PM_USER_SESSION (USER_ID, SESSION_ID, EXPIRED_DATE)
		SELECT @UserID, @Password, DATEADD(mi,@TokenTimeout,GetDate())

	-- Record the successful authentication
	INSERT INTO HIVE.AuthenticateLog (Username,RequestDate,IPAddress,Success)
		SELECT @UserID, GetDate(), @IPAddress, 1

	-- Create the new password tag
	DECLARE @PasswordTag VARCHAR(MAX)
	SELECT @PasswordTag = '<password token_ms_timeout="' + CAST(@TokenTimeout*60*1000 AS VARCHAR(MAX)) + '" is_token="true">'+@Password

	-- Return the new request with the password token
	SELECT (CASE WHEN Pos3 > Pos2 + 1 THEN STUFF(@Request,Pos1,Pos3-Pos1,@PasswordTag) ELSE @Request END) RequestWithToken
		FROM (SELECT CHARINDEX('<password',@Request) Pos1) t1
		CROSS APPLY (SELECT (CASE WHEN Pos1 > 0 THEN CHARINDEX('>',@Request,Pos1+1) ELSE 0 END) Pos2) t2
		CROSS APPLY (SELECT (CASE WHEN Pos2 > 0 THEN CHARINDEX('<',@Request,Pos2+1) ELSE 0 END) Pos3) t3

END
GO
