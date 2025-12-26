/-
  HomebaseApp.Actions.Chat - Chat CRUD actions
-/
import Loom
import Ledger
import HomebaseApp.Helpers
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Upload
import HomebaseApp.Views.Chat

namespace HomebaseApp.Actions.Chat

open Loom
open Loom.Json
open Ledger
open HomebaseApp.Helpers
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Upload
open HomebaseApp.Views.Chat

-- ============================================================================
-- Helper functions
-- ============================================================================

/-- Check if a string contains a substring -/
private def containsSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

-- ============================================================================
-- Database helper functions
-- ============================================================================

/-- Get current timestamp in milliseconds -/
def getNowMs : IO Nat := do
  let nanos ← IO.monoNanosNow
  pure (nanos / 1000000)

/-- Get all threads from database, sorted by most recent activity -/
def getThreads (ctx : Context) : List (EntityId × DbChatThread) :=
  match ctx.database with
  | none => []
  | some db =>
    let threadIds := db.entitiesWithAttr DbChatThread.attr_title
    let threads := threadIds.filterMap fun tid =>
      match DbChatThread.pull db tid with
      | some t => some (tid, t)
      | none => none
    -- Sort by createdAt descending (most recent first)
    threads.toArray.qsort (fun a b => a.2.createdAt > b.2.createdAt) |>.toList

/-- Get messages for a thread, sorted by timestamp ascending -/
def getMessagesForThread (db : Db) (threadId : EntityId) : List (EntityId × DbChatMessage) :=
  let msgIds := db.findByAttrValue DbChatMessage.attr_thread (.ref threadId)
  let messages := msgIds.filterMap fun mid =>
    match DbChatMessage.pull db mid with
    | some m =>
      if m.thread == threadId then some (mid, m)
      else none
    | none => none
  -- Sort by timestamp ascending (oldest first)
  messages.toArray.qsort (fun a b => a.2.timestamp < b.2.timestamp) |>.toList

/-- Get thread by ID -/
def getThread (ctx : Context) (threadId : Nat) : Option DbChatThread :=
  match ctx.database with
  | none => none
  | some db => DbChatThread.pull db ⟨threadId⟩

/-- Get user name by EntityId -/
def getUserName (db : Db) (userId : EntityId) : String :=
  match db.getOne userId userName with
  | some (.string name) => name
  | _ => "Unknown"

/-- Convert DbChatThread to view Thread with message info -/
def toViewThread (db : Db) (tid : EntityId) (t : DbChatThread) : Thread :=
  let messages := getMessagesForThread db tid
  let lastMsg := messages.getLast?.map fun (_, m) => m.content
  t.toViewThread messages.length lastMsg

/-- Convert DbChatMessage to view Message -/
def toViewMessage (db : Db) (m : DbChatMessage) : Message :=
  m.toViewMessage (getUserName db m.user)

-- ============================================================================
-- Actions
-- ============================================================================

/-- Main chat page - list threads -/
def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let now ← getNowMs
  match ctx.database with
  | none =>
    -- Check if this is an HTMX request (partial) or full page
    if ctx.header "HX-Request" == some "true" then
      let html := Views.Chat.renderThreadListPartial [] none now
      Action.html html ctx
    else
      let html := Views.Chat.render ctx [] none [] now
      Action.html html ctx
  | some db =>
    let threadData := getThreads ctx
    let threads := threadData.map fun (tid, t) => toViewThread db tid t
    -- Check if this is an HTMX request (partial) or full page
    if ctx.header "HX-Request" == some "true" then
      let html := Views.Chat.renderThreadListPartial threads none now
      Action.html html ctx
    else
      let html := Views.Chat.render ctx threads none [] now
      Action.html html ctx

/-- View a specific thread with messages -/
def showThread (threadId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let now ← getNowMs
  match ctx.database with
  | none => Action.notFound ctx "Database not available"
  | some db =>
    match DbChatThread.pull db ⟨threadId⟩ with
    | none => Action.notFound ctx "Thread not found"
    | some dbThread =>
      let thread := toViewThread db ⟨threadId⟩ dbThread
      let messageData := getMessagesForThread db ⟨threadId⟩
      let messages := messageData.map fun (_, m) => toViewMessage db m
      -- Check if this is an HTMX request (partial) or full page
      if ctx.header "HX-Request" == some "true" then
        let html := Views.Chat.renderMessageAreaPartial ctx thread messages now
        Action.html html ctx
      else
        let threadData := getThreads ctx
        let threads := threadData.map fun (tid, t) => toViewThread db tid t
        let html := Views.Chat.render ctx threads (some thread) messages now
        Action.html html ctx

/-- Show new thread form (modal) -/
def newThreadForm : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := Views.Chat.renderNewThreadFormPartial ctx
  Action.html html ctx

/-- Create a new thread -/
def createThread : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let title := ctx.params.getD "title" ""
  if title.isEmpty then
    return ← Action.badRequest ctx "Thread title is required"

  match ctx.allocEntityId with
  | none => Action.badRequest ctx "Database not available"
  | some (eid, ctx') =>
    let now ← getNowMs
    let dbThread : DbChatThread := { id := eid.id.toNat, title := title, createdAt := now }
    let tx := DbChatThread.createOps eid dbThread
    match ← ctx'.transact tx with
    | .ok ctx'' =>
      logAudit ctx'' "CREATE" "chat-thread" eid.id.toNat [("title", title)]
      let thread : Thread := { id := eid.id.toNat, title := title, createdAt := now, messageCount := 0, lastMessage := none }
      -- Notify SSE clients
      let threadId := eid.id.toNat
      let _ ← SSE.publishEvent "chat" "thread-created" (jsonStr! { threadId, title })
      let html := Views.Chat.renderThreadItemPartial thread false now
      Action.html html ctx''
    | .error e =>
      logAuditError ctx "CREATE" "chat-thread" [("title", title), ("error", toString e)]
      Action.badRequest ctx' s!"Failed to create thread: {e}"

/-- Show edit thread form (modal) -/
def editThreadForm (threadId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    match DbChatThread.pull db ⟨threadId⟩ with
    | none => Action.notFound ctx "Thread not found"
    | some dbThread =>
      let thread := toViewThread db ⟨threadId⟩ dbThread
      let html := Views.Chat.renderEditThreadFormPartial ctx thread
      Action.html html ctx

/-- Update a thread title -/
def updateThread (threadId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let title := ctx.params.getD "title" ""
  if title.isEmpty then
    return ← Action.badRequest ctx "Thread title is required"

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    let oldTitle := match DbChatThread.pull db ⟨threadId⟩ with
      | some t => t.title
      | none => "(unknown)"
    let tx := DbChatThread.set_title db ⟨threadId⟩ title
    match ← ctx.transact tx with
    | .ok ctx' =>
      let now ← getNowMs
      match ctx'.database with
      | none => Action.notFound ctx' "Thread not found"
      | some db' =>
        match DbChatThread.pull db' ⟨threadId⟩ with
        | none => Action.notFound ctx' "Thread not found"
        | some dbThread =>
          let thread := toViewThread db' ⟨threadId⟩ dbThread
          logAudit ctx' "UPDATE" "chat-thread" threadId [("old_title", oldTitle), ("new_title", title)]
          let _ ← SSE.publishEvent "chat" "thread-updated" (jsonStr! { threadId, title })
          let html := Views.Chat.renderThreadItemPartial thread false now
          Action.html html ctx'
    | .error e =>
      logAuditError ctx "UPDATE" "chat-thread" [("thread_id", toString threadId), ("error", toString e)]
      Action.badRequest ctx s!"Failed to update thread: {e}"

/-- Delete a thread and all its messages -/
def deleteThread (threadId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    let threadTitle := match DbChatThread.pull db ⟨threadId⟩ with
      | some t => t.title
      | none => "(unknown)"

    let tid : EntityId := ⟨threadId⟩
    let messageIds := db.findByAttrValue DbChatMessage.attr_thread (.ref tid)
    let msgCount := messageIds.length

    -- Build retraction operations for all messages, attachments, then the thread
    let mut txOps : List TxOp := []
    let mut attachmentCount : Nat := 0
    for msgId in messageIds do
      -- Delete attachments for this message first
      let attachmentIds := db.findByAttrValue DbChatAttachment.attr_message (.ref msgId)
      for attId in attachmentIds do
        match DbChatAttachment.pull db attId with
        | some att =>
          -- Delete file from disk
          let _ ← Upload.deleteFile att.storedPath
          txOps := txOps ++ DbChatAttachment.retractionOps db attId
          attachmentCount := attachmentCount + 1
        | none => pure ()
      txOps := txOps ++ DbChatMessage.retractionOps db msgId
    txOps := txOps ++ DbChatThread.retractionOps db tid

    match ← ctx.transact txOps with
    | .ok ctx' =>
      let now ← getNowMs
      logAudit ctx' "DELETE" "chat-thread" threadId [("title", threadTitle), ("cascade_messages", toString msgCount)]
      let _ ← SSE.publishEvent "chat" "thread-deleted" (jsonStr! { threadId })
      -- Return updated thread list and empty state
      let threadData := getThreads ctx'
      match ctx'.database with
      | none =>
        let html := Views.Chat.renderThreadDeletedPartial ctx' [] now
        Action.html html ctx'
      | some db' =>
        let threads := threadData.map fun (tid, t) => toViewThread db' tid t
        let html := Views.Chat.renderThreadDeletedPartial ctx' threads now
        Action.html html ctx'
    | .error e =>
      logAuditError ctx "DELETE" "chat-thread" [("thread_id", toString threadId), ("error", toString e)]
      Action.badRequest ctx s!"Failed to delete thread: {e}"

/-- Add a message to a thread -/
def addMessage (threadId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let content := ctx.params.getD "content" ""
  let attachmentIds : List Int := ctx.params.getD "attachments" ""
    |>.splitOn ","
    |>.filterMap String.toInt?

  -- Either content or attachments must be present
  if content.trim.isEmpty && attachmentIds.isEmpty then
    return ← Action.badRequest ctx "Message content or attachment is required"

  match ctx.allocEntityId with
  | none => Action.badRequest ctx "Database not available"
  | some (eid, ctx') =>
    -- Get current user ID from session
    let userId := match currentUserId ctx' with
      | some idStr => match idStr.toNat? with
        | some n => EntityId.mk n
        | none => EntityId.null
      | none => EntityId.null

    let now ← getNowMs
    let dbMessage : DbChatMessage := {
      id := eid.id.toNat
      content := content.trim
      timestamp := now
      thread := ⟨threadId⟩
      user := userId
    }

    -- Create message and link attachments in one transaction
    let mut tx := DbChatMessage.createOps eid dbMessage
    match ctx'.database with
    | none => pure ()
    | some db =>
      for attId in attachmentIds do
        -- Update attachment to point to this message
        tx := tx ++ DbChatAttachment.set_message db ⟨attId⟩ eid

    match ← ctx'.transact tx with
    | .ok ctx'' =>
      let (userName, viewAttachments) := match ctx''.database with
        | some db =>
          let name := getUserName db userId
          let atts := attachmentIds.filterMap fun attId =>
            match DbChatAttachment.pull db ⟨attId⟩ with
            | some a => some a.toViewAttachment
            | none => none
          (name, atts)
        | none => ("Unknown", [])
      logAudit ctx'' "CREATE" "chat-message" eid.id.toNat [("thread_id", toString threadId), ("attachments", toString attachmentIds.length)]
      let msg : Message := {
        id := eid.id.toNat
        content := content.trim
        timestamp := now
        userName := userName
        attachments := viewAttachments
      }
      -- Notify SSE clients
      let messageId := eid.id.toNat
      let _ ← SSE.publishEvent "chat" "message-added" (jsonStr! { messageId, threadId })
      let html := Views.Chat.renderMessagePartial msg now
      Action.html html ctx''
    | .error e =>
      logAuditError ctx "CREATE" "chat-message" [("thread_id", toString threadId), ("error", toString e)]
      Action.badRequest ctx' s!"Failed to add message: {e}"

/-- Search messages across all threads -/
def search : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let query := ctx.params.getD "q" ""
  if query.trim.isEmpty then
    -- Empty query - show empty
    return ← Action.html "" ctx

  let now ← getNowMs
  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    -- Get all messages and filter by content
    let allMsgIds := db.entitiesWithAttr DbChatMessage.attr_content
    let queryLower := query.toLower
    let results := allMsgIds.filterMap fun msgId =>
      match DbChatMessage.pull db msgId with
      | some msg =>
        if containsSubstr msg.content.toLower queryLower then
          match DbChatThread.pull db msg.thread with
          | some thread =>
            let viewThread := toViewThread db msg.thread thread
            let viewMsg := toViewMessage db msg
            some (viewThread, viewMsg)
          | none => none
        else none
      | none => none

    -- Sort by timestamp descending (most recent matches first)
    let sortedResults := results.toArray.qsort (fun a b => a.2.timestamp > b.2.timestamp) |>.toList

    let html := Views.Chat.renderSearchResultsPartial query sortedResults now
    Action.html html ctx

-- ============================================================================
-- Attachment helpers
-- ============================================================================

/-- Get attachments for a message -/
def getAttachmentsForMessage (db : Db) (msgId : EntityId) : List (EntityId × DbChatAttachment) :=
  let attIds := db.findByAttrValue DbChatAttachment.attr_message (.ref msgId)
  attIds.filterMap fun attId =>
    match DbChatAttachment.pull db attId with
    | some a => some (attId, a)
    | none => none

/-- Convert DbChatMessage to view Message with attachments -/
def toViewMessageWithAttachments (db : Db) (msgId : EntityId) (m : DbChatMessage) : Message :=
  let userName := getUserName db m.user
  let attachments := getAttachmentsForMessage db msgId
  let viewAttachments := attachments.map fun (_, a) => a.toViewAttachment
  m.toViewMessage userName viewAttachments

-- ============================================================================
-- File upload actions
-- ============================================================================

/-- Upload an attachment to a thread -/
def uploadAttachment (threadId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.json "{\"error\": \"Not logged in\"}" ctx

  -- Get uploaded file
  match ctx.file "file" with
  | none => Action.json "{\"error\": \"No file uploaded\"}" ctx
  | some file =>
    -- Validate file size
    if file.content.size > maxFileSize then
      return ← Action.json "{\"error\": \"File too large (max 10MB)\"}" ctx

    -- Validate MIME type
    let mimeType := file.contentType.getD "application/octet-stream"
    if !isAllowedType mimeType then
      return ← Action.json "{\"error\": \"File type not allowed\"}" ctx

    -- Store file on disk
    let storedPath ← storeFile file.content (file.filename.getD "upload")

    -- Create attachment entity
    match ctx.allocEntityId with
    | none => Action.json "{\"error\": \"Database not available\"}" ctx
    | some (eid, ctx') =>
      let now ← getNowMs
      let attachment : DbChatAttachment := {
        id := eid.id.toNat
        fileName := file.filename.getD "upload"
        storedPath := storedPath
        mimeType := mimeType
        fileSize := file.content.size
        uploadedAt := now
        message := EntityId.null  -- Will be linked when message is created
      }
      let tx := DbChatAttachment.createOps eid attachment
      match ← ctx'.transact tx with
      | .ok ctx'' =>
        logAudit ctx'' "CREATE" "chat-attachment" eid.id.toNat [("thread_id", toString threadId), ("filename", file.filename.getD "upload")]
        -- Return JSON with attachment ID
        let fileName := file.filename.getD "upload"
        Action.json s!"\{\"id\": {eid.id.toNat}, \"fileName\": \"{fileName}\", \"storedPath\": \"{storedPath}\"}" ctx''
      | .error e =>
        logAuditError ctx "CREATE" "chat-attachment" [("error", toString e)]
        Action.json s!"\{\"error\": \"Failed to save attachment: {e}\"}" ctx'

/-- Serve an uploaded file -/
def serveAttachment : Action := fun ctx => do
  -- Extract filename from path params
  let filename := ctx.params.getD "filename" ""
  if filename.isEmpty || !Upload.isSafePath filename then
    return ← Action.notFound ctx "File not found"

  -- Read file from disk
  match ← Upload.readFile filename with
  | none => Action.notFound ctx "File not found"
  | some content =>
    let mimeType := Upload.mimeTypeForFile filename
    -- Build response with file content
    let resp := Citadel.ResponseBuilder.withStatus Herald.Core.StatusCode.ok
      |>.withHeader "Content-Type" mimeType
      |>.withHeader "Content-Length" (toString content.size)
      |>.withHeader "Cache-Control" "public, max-age=31536000"
      |>.withBody content
      |>.build
    pure (resp, ctx)

/-- Delete an attachment -/
def deleteAttachment (attachmentId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.json "{\"error\": \"Not logged in\"}" ctx

  match ctx.database with
  | none => Action.json "{\"error\": \"Database not available\"}" ctx
  | some db =>
    let attId : EntityId := ⟨attachmentId⟩
    match DbChatAttachment.pull db attId with
    | none => Action.json "{\"error\": \"Attachment not found\"}" ctx
    | some attachment =>
      -- Delete file from disk
      let _ ← Upload.deleteFile attachment.storedPath
      -- Delete from database
      let tx := DbChatAttachment.retractionOps db attId
      match ← ctx.transact tx with
      | .ok ctx' =>
        logAudit ctx' "DELETE" "chat-attachment" attachmentId [("filename", attachment.fileName)]
        Action.json "{\"success\": true}" ctx'
      | .error e =>
        logAuditError ctx "DELETE" "chat-attachment" [("attachment_id", toString attachmentId), ("error", toString e)]
        Action.json s!"\{\"error\": \"Failed to delete attachment: {e}\"}" ctx

end HomebaseApp.Actions.Chat
