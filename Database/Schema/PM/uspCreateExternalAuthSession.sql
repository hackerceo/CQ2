SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PM].[uspCreateExternalAuthSession]

	@json varchar(max) = null
AS
BEGIN
	declare @UserID VARCHAR(50) = null,	@Secret VARCHAR(50) = null,	@IPAddress VARCHAR(50) = NULL

	if @json is not null
	BEGIN
		set nocount on
		SELECT * into #tmpJson FROM OpenJson(@json);
		select @Secret=isnull([value], @Secret) from #tmpJson where [key] = 'secret'
		select @UserID=isnull([value], @userID) from #tmpJson where [key] = 'username'
		select @IPAddress=isnull([value], @IPAddress) from #tmpJson where [key] = 'clientIP'

	END



	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	if @Secret <> '<Enter Secret here>' BEGIN  select '{"error":"bad secret"}' as result; return END
	if not exists (select 1 from [PM].[PM_USER_DATA] where USER_ID = @UserID and [STATUS_CD]='A') BEGIN select '{"error":"Invalid UserID"}' as result return END

	-- Define the token timeout period
	DECLARE @TokenTimeout INT
	SELECT @TokenTimeout = 30 -- minutes

	-- Get a session_id
	DECLARE @Password VARCHAR(MAX)
	EXEC HIVE.uspGetNewID 20, @Password OUTPUT
	SELECT @Password = 'SessionKey:'+@Password
--	UPDATE PM.PM_USER_SESSION
--		SET EXPIRED_DATE = GetDate()
--		WHERE [USER_ID] = @UserID AND (EXPIRED_DATE IS NULL OR EXPIRED_DATE > GetDate())
	INSERT INTO PM.PM_USER_SESSION (USER_ID, SESSION_ID, EXPIRED_DATE)
		SELECT @UserID, @Password, DATEADD(mi,@TokenTimeout,GetDate())

	-- Record the successful authentication
	INSERT INTO HIVE.AuthenticateLog (Username,RequestDate,IPAddress,Success)
		SELECT @UserID, GetDate(), @IPAddress, 1

	SELECT cast('{"session":"' + @Password +'"}' as varchar(1000)) as result

END
GO
