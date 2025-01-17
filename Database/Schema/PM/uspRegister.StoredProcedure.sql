SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PM].[uspRegister]
	@user_id VARCHAR(50),
	@project_id VARCHAR(50)='Demo'
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Quit if no user_id is defined
	IF ISNULL(@user_id,'') = ''
		RETURN

	-- Make sure the user exists and is associated with the project
	IF NOT EXISTS (SELECT * FROM PM.PM_USER_DATA WHERE USER_ID = @user_id)
	BEGIN
		INSERT INTO PM.PM_USER_DATA (USER_ID, FULL_NAME, PASSWORD, ENTRY_DATE, STATUS_CD)
			SELECT @user_id, @user_id, '', GetDate(), 'A'
		IF NOT EXISTS (SELECT * FROM PM.PM_PROJECT_USER_ROLES WHERE PROJECT_ID = @project_id AND USER_ID = @user_id)
			INSERT INTO PM.PM_PROJECT_USER_ROLES (PROJECT_ID, USER_ID, USER_ROLE_CD, ENTRY_DATE, STATUS_CD)
				SELECT @project_id, @user_id, 'DATA_OBFSC', GetDate(), 'A'
	END

	-- Make sure the user has a root workplace folder
	IF NOT EXISTS (SELECT * FROM WORK.WORKPLACE_ACCESS WHERE C_USER_ID = @user_id)
	BEGIN
		INSERT INTO WORK.WORKPLACE_ACCESS (C_TABLE_CD, C_TABLE_NAME, C_PROTECTED_ACCESS, C_HLEVEL, C_NAME, C_USER_ID, C_GROUP_ID, 
				C_SHARE_ID, C_INDEX, C_PARENT_INDEX, C_VISUALATTRIBUTES, C_TOOLTIP, C_ENTRY_DATE, C_CHANGE_DATE, C_STATUS_CD)
			SELECT 'WORK', 'WORKPLACE', 'N', 0, UPPER(@user_id), UPPER(@user_id), @project_id, 
				'N', CAST(NEWID() AS VARCHAR(50)), NULL, 'CA ', '@', GETDATE(), GETDATE(), 'A'
	END

	-- Get a session_id
	DECLARE @password VARCHAR(MAX)
	EXEC HIVE.uspGetNewID 20, @password OUTPUT
	SELECT @password = 'SessionKey:'+@password
	UPDATE PM.PM_USER_SESSION
		SET EXPIRED_DATE = GetDate()
		WHERE [USER_ID] = @user_id AND (EXPIRED_DATE IS NULL OR EXPIRED_DATE > GetDate())
	INSERT INTO PM.PM_USER_SESSION (USER_ID, SESSION_ID, EXPIRED_DATE)
		SELECT @user_id, @password, DATEADD(mi,15,GetDate())
	SELECT @password SESSION_ID

END
GO
