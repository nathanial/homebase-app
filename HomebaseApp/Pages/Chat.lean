/-
  HomebaseApp.Pages.Chat - Chat section with threads, messages, and file uploads
-/
import Scribe
import Loom
import Loom.Stencil
import Stencil
import Ledger
import Staple
import Citadel
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.Upload
import HomebaseApp.Embeds
import HomebaseApp.StencilHelpers

namespace HomebaseApp.Pages

open Scribe
open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.AuditTxM (audit)
open Loom.Json
open Ledger
open Staple (String.containsSubstr)
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers hiding isLoggedIn isAdmin
open HomebaseApp.Upload
open HomebaseApp.StencilHelpers

/-! ## View Data Structures -/

structure Attachment where
  id : Nat
  fileName : String
  mimeType : String
  fileSize : Nat
  url : String
  deriving Inhabited

structure Message where
  id : Nat
  content : String
  timestamp : Nat
  userName : String
  attachments : List Attachment := []
  embeds : List Embeds.LinkEmbed := []
  deriving Inhabited

structure Thread where
  id : Nat
  title : String
  createdAt : Nat
  messageCount : Nat
  lastMessage : Option String
  deriving Inhabited

/-! ## Helpers -/

def getNowMs : IO Nat := do
  let nanos ← IO.monoNanosNow
  pure (nanos / 1000000)

/-! ## Database Helpers -/

def getThreads (ctx : Context) : List (EntityId × DbChatThread) :=
  match ctx.database with
  | none => []
  | some db =>
    let threadIds := db.entitiesWithAttr DbChatThread.attr_title
    let threads := threadIds.filterMap fun tid =>
      match DbChatThread.pull db tid with
      | some t => some (tid, t)
      | none => none
    threads.toArray.qsort (fun a b => a.2.createdAt > b.2.createdAt) |>.toList

def getMessagesForThread (db : Db) (threadId : EntityId) : List (EntityId × DbChatMessage) :=
  let msgIds := db.findByAttrValue DbChatMessage.attr_thread (.ref threadId)
  let messages := msgIds.filterMap fun mid =>
    match DbChatMessage.pull db mid with
    | some m =>
      if m.thread == threadId then some (mid, m)
      else none
    | none => none
  messages.toArray.qsort (fun a b => a.2.timestamp < b.2.timestamp) |>.toList

def getChatThread (ctx : Context) (threadId : Nat) : Option DbChatThread :=
  ctx.database.bind fun db => DbChatThread.pull db ⟨threadId⟩

def getUserNameFromDb (db : Db) (userId : EntityId) : String :=
  match db.getOne userId userName with
  | some (.string name) => name
  | _ => "Unknown"

def toViewThread (db : Db) (tid : EntityId) (t : DbChatThread) : Thread :=
  let messages := getMessagesForThread db tid
  let lastMsg := messages.getLast?.map fun (_, m) => m.content
  { id := t.id, title := t.title, createdAt := t.createdAt, messageCount := messages.length, lastMessage := lastMsg }

def getAttachmentsForMessage (db : Db) (messageId : EntityId) : List Attachment :=
  let attIds := db.findByAttrValue DbChatAttachment.attr_message (.ref messageId)
  attIds.filterMap fun attId =>
    match DbChatAttachment.pull db attId with
    | some a => some { id := a.id, fileName := a.fileName, mimeType := a.mimeType, fileSize := a.fileSize, url := s!"/uploads/{a.storedPath}" }
    | none => none

def getEmbedsForMessage (db : Db) (messageId : EntityId) : List Embeds.LinkEmbed :=
  let embedIds := db.findByAttrValue DbLinkEmbed.attr_message (.ref messageId)
  embedIds.filterMap fun embedId =>
    match DbLinkEmbed.pull db embedId with
    | some e => some {
        url := e.url
        embedType := e.embedType
        title := e.title
        description := e.description
        thumbnailUrl := e.thumbnailUrl
        authorName := e.authorName
        videoId := e.videoId
      }
    | none => none

def toViewMessageWithAttachments (db : Db) (msgId : EntityId) (m : DbChatMessage) : Message :=
  let attachments := getAttachmentsForMessage db msgId
  let embeds := getEmbedsForMessage db msgId
  { id := m.id, content := m.content, timestamp := m.timestamp, userName := getUserNameFromDb db m.user, attachments := attachments, embeds := embeds }

def toViewMessage (db : Db) (m : DbChatMessage) : Message :=
  { id := m.id, content := m.content, timestamp := m.timestamp, userName := getUserNameFromDb db m.user, attachments := [] }

def formatRelativeTime (timestamp now : Nat) : String :=
  if now < timestamp then "just now"
  else
    let diffMs := now - timestamp
    let diffSeconds := diffMs / 1000
    let diffMinutes := diffSeconds / 60
    let diffHours := diffMinutes / 60
    let diffDays := diffHours / 24
    if diffSeconds < 60 then "just now"
    else if diffMinutes < 60 then s!"{diffMinutes} minute{if diffMinutes == 1 then "" else "s"} ago"
    else if diffHours < 24 then s!"{diffHours} hour{if diffHours == 1 then "" else "s"} ago"
    else if diffDays < 7 then s!"{diffDays} day{if diffDays == 1 then "" else "s"} ago"
    else s!"{diffDays / 7} week{if diffDays / 7 == 1 then "" else "s"} ago"

def formatFileSize (bytes : Nat) : String :=
  if bytes < 1024 then s!"{bytes} B"
  else if bytes < 1024 * 1024 then s!"{bytes / 1024} KB"
  else s!"{bytes / (1024 * 1024)} MB"

/-! ## Stencil Value Helpers -/

/-- Convert an attachment to Stencil.Value -/
def attachmentToValue (att : Attachment) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat att.id)),
    ("fileName", .string att.fileName),
    ("url", .string att.url),
    ("isImage", .bool (att.mimeType.startsWith "image/")),
    ("fileSizeFormatted", .string (formatFileSize att.fileSize))
  ]

/-- Convert an embed to Stencil.Value -/
def embedToValue (embed : Embeds.LinkEmbed) : Stencil.Value :=
  .object #[
    ("url", .string embed.url),
    ("embedType", .string embed.embedType),
    ("title", .string embed.title),
    ("description", .string embed.description),
    ("thumbnailUrl", .string embed.thumbnailUrl),
    ("authorName", .string embed.authorName),
    ("isYoutube", .bool (embed.embedType == "youtube")),
    ("isTwitter", .bool (embed.embedType == "twitter")),
    ("hasTitle", .bool (!embed.title.isEmpty && embed.title != "YouTube Video")),
    ("hasDescription", .bool (!embed.description.isEmpty)),
    ("hasThumbnail", .bool (!embed.thumbnailUrl.isEmpty)),
    ("hasAuthor", .bool (!embed.authorName.isEmpty))
  ]

/-- Convert a message to Stencil.Value -/
def messageToValue (msg : Message) (now : Nat) : Stencil.Value :=
  let contentLines := msg.content.splitOn "\n"
  .object #[
    ("id", .int (Int.ofNat msg.id)),
    ("userName", .string msg.userName),
    ("relativeTime", .string (formatRelativeTime msg.timestamp now)),
    ("contentLines", .array (contentLines.map .string).toArray),
    ("hasEmbeds", .bool (!msg.embeds.isEmpty)),
    ("embeds", .array (msg.embeds.map embedToValue).toArray),
    ("hasAttachments", .bool (!msg.attachments.isEmpty)),
    ("attachments", .array (msg.attachments.map attachmentToValue).toArray)
  ]

/-- Convert a thread to Stencil.Value -/
def threadToValue (thread : Thread) (isActive : Bool) (now : Nat) : Stencil.Value :=
  let preview := match thread.lastMessage with
    | some p => if p.length > 50 then p.take 50 ++ "..." else p
    | none => ""
  .object #[
    ("id", .int (Int.ofNat thread.id)),
    ("title", .string thread.title),
    ("relativeTime", .string (formatRelativeTime thread.createdAt now)),
    ("messageCount", .int (Int.ofNat thread.messageCount)),
    ("hasLastMessage", .bool thread.lastMessage.isSome),
    ("lastMessagePreview", .string preview),
    ("isActive", .bool isActive)
  ]

/-- Build chat page data for Stencil -/
def chatPageData (ctx : Context) (threads : List Thread) (activeThread : Option Thread)
    (messages : List Message) (now : Nat) : Stencil.Value :=
  let activeId := activeThread.map (·.id)
  .object #[
    ("threads", .array (threads.map fun t => threadToValue t (activeId == some t.id) now).toArray),
    ("hasActiveThread", .bool activeThread.isSome),
    ("activeThread", match activeThread with
      | some t => threadToValue t true now
      | none => .null),
    ("messages", .array (messages.map (messageToValue · now)).toArray),
    ("csrfToken", .string ctx.csrfToken)
  ]

/-- Convert a search result to Stencil.Value -/
def searchResultToValue (thread : Thread) (msg : Message) (now : Nat) : Stencil.Value :=
  .object #[
    ("thread", threadToValue thread false now),
    ("message", messageToValue msg now)
  ]

/-- Build search results data for Stencil -/
def searchResultsData (query : String) (results : List (Thread × Message)) (now : Nat) : Stencil.Value :=
  .object #[
    ("query", .string query),
    ("hasResults", .bool (!results.isEmpty)),
    ("results", .array (results.map fun (t, m) => searchResultToValue t m now).toArray)
  ]

/-! ## Pages -/

-- Chat index
view chat "/chat" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let now ← getNowMs
  match ctx.database with
  | none =>
    let data := pageContext ctx "Chat" PageId.chat (chatPageData ctx [] none [] now)
    Loom.Stencil.ActionM.renderWithLayout "app" "chat/index" data
  | some db =>
    let threadData := getThreads ctx
    let threads := threadData.map fun (tid, t) => toViewThread db tid t
    let data := pageContext ctx "Chat" PageId.chat (chatPageData ctx threads none [] now)
    Loom.Stencil.ActionM.renderWithLayout "app" "chat/index" data

-- View thread
view chatThread "/chat/thread/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let now ← getNowMs
  match ctx.database with
  | none => notFound "Database not available"
  | some db =>
    match DbChatThread.pull db ⟨id⟩ with
    | none => notFound "Thread not found"
    | some dbThread =>
      let thread := toViewThread db ⟨id⟩ dbThread
      let messageData := getMessagesForThread db ⟨id⟩
      let messages := messageData.map fun (mid, m) => toViewMessageWithAttachments db mid m
      if ctx.header "HX-Request" == some "true" then
        let data := mergeContext (chatPageData ctx [] (some thread) messages now)
          (.object #[("csrfToken", .string ctx.csrfToken)])
        Loom.Stencil.ActionM.renderPartial "chat/_thread-area" data
      else
        let threadData := getThreads ctx
        let threads := threadData.map fun (tid, t) => toViewThread db tid t
        let data := pageContext ctx "Chat" PageId.chat (chatPageData ctx threads (some thread) messages now)
        Loom.Stencil.ActionM.renderWithLayout "app" "chat/index" data

-- New thread form
view chatNewThreadForm "/chat/thread/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  Loom.Stencil.ActionM.render "chat/new" (.object #[("csrfToken", .string ctx.csrfToken)])

-- Create thread
action chatCreateThread "/chat/thread" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  if title.isEmpty then
    return ← badRequest "Thread title is required"
  let now ← getNowMs
  let (eid, _) ← withNewEntityAudit! fun eid => do
    let dbThread : DbChatThread := { id := eid.id.toNat, title := title, createdAt := now }
    DbChatThread.TxM.create eid dbThread
    audit "CREATE" "chat-thread" eid.id.toNat [("title", title)]
  let thread : Thread := { id := eid.id.toNat, title := title, createdAt := now, messageCount := 0, lastMessage := none }
  let threadId := eid.id.toNat
  let _ ← SSE.publishEvent "chat" "thread-created" (jsonStr! { threadId, title })
  Loom.Stencil.ActionM.render "chat/thread-item" (threadToValue thread false now)

-- Edit thread form
view chatEditThreadForm "/chat/thread/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => badRequest "Database not available"
  | some db =>
    match DbChatThread.pull db ⟨id⟩ with
    | none => notFound "Thread not found"
    | some dbThread =>
      let thread := toViewThread db ⟨id⟩ dbThread
      let data : Stencil.Value := .object #[
        ("id", .int (Int.ofNat id)),
        ("title", .string thread.title),
        ("csrfToken", .string ctx.csrfToken)
      ]
      Loom.Stencil.ActionM.render "chat/edit" data

-- Update thread
action chatUpdateThread "/chat/thread/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  if title.isEmpty then
    return ← badRequest "Thread title is required"
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    let db ← AuditTxM.getDb
    let oldTitle := match DbChatThread.pull db eid with
      | some t => t.title
      | none => "(unknown)"
    DbChatThread.TxM.setTitle eid title
    audit "UPDATE" "chat-thread" id [("old_title", oldTitle), ("new_title", title)]
  let now ← getNowMs
  let ctx ← getCtx
  match ctx.database with
  | none => notFound "Thread not found"
  | some db =>
    match DbChatThread.pull db eid with
    | none => notFound "Thread not found"
    | some dbThread =>
      let thread := toViewThread db eid dbThread
      let threadId := id
      let _ ← SSE.publishEvent "chat" "thread-updated" (jsonStr! { threadId, title })
      Loom.Stencil.ActionM.render "chat/thread-item" (threadToValue thread false now)

-- Delete thread
action chatDeleteThread "/chat/thread/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let some db := ctx.database | return ← badRequest "Database not available"
  let tid : EntityId := ⟨id⟩
  let threadTitle := match DbChatThread.pull db tid with
    | some t => t.title
    | none => "(unknown)"
  let messageIds := db.findByAttrValue DbChatMessage.attr_thread (.ref tid)
  -- Delete attachment files from disk
  for msgId in messageIds do
    let attachmentIds := db.findByAttrValue DbChatAttachment.attr_message (.ref msgId)
    for attId in attachmentIds do
      match DbChatAttachment.pull db attId with
      | some att => let _ ← Upload.deleteFile att.storedPath
      | none => pure ()
  -- Delete all entities in a transaction
  let msgCount := messageIds.length
  runAuditTx! do
    for msgId in messageIds do
      let attachmentIds := db.findByAttrValue DbChatAttachment.attr_message (.ref msgId)
      for attId in attachmentIds do
        DbChatAttachment.TxM.delete attId
      DbChatMessage.TxM.delete msgId
    DbChatThread.TxM.delete tid
    audit "DELETE" "chat-thread" id [("title", threadTitle), ("message_count", toString msgCount)]
  let threadId := id
  let _ ← SSE.publishEvent "chat" "thread-deleted" (jsonStr! { threadId })
  Loom.Stencil.ActionM.render "chat/empty" (.object #[])

-- Add message
action chatAddMessage "/chat/thread/:id/message" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let content := ctx.paramD "content" ""
  let attachmentIds : List Int := ctx.paramD "attachments" ""
    |>.splitOn ","
    |>.filterMap String.toInt?
  if content.trim.isEmpty && attachmentIds.isEmpty then
    return ← badRequest "Message content or attachment is required"
  let userId := match currentUserId ctx with
    | some idStr => match idStr.toNat? with
      | some n => EntityId.mk n
      | none => EntityId.null
    | none => EntityId.null
  let now ← getNowMs

  -- Detect URLs and fetch embed metadata (before transaction)
  let urls := Embeds.detectUrls content.trim
  let fetchedEmbeds ← Embeds.fetchEmbedsForUrls urls

  -- Allocate entity ID for the message
  let msgEid ← match ← allocEntityId with
    | some eid => pure eid
    | none => throw (IO.userError "No database connection")

  -- Allocate entity IDs for all embeds upfront
  let mut embedEids : List EntityId := []
  for _ in fetchedEmbeds do
    match ← allocEntityId with
    | some eid => embedEids := embedEids ++ [eid]
    | none => throw (IO.userError "No database connection")

  -- Run the audit transaction with pre-allocated IDs
  runAuditTx! do
    let dbMessage : DbChatMessage := {
      id := msgEid.id.toNat
      content := content.trim
      timestamp := now
      thread := ⟨id⟩
      user := userId
    }
    DbChatMessage.TxM.create msgEid dbMessage
    -- Link attachments to this message
    for attId in attachmentIds do
      DbChatAttachment.TxM.setMessage ⟨attId⟩ msgEid
    -- Store embeds for this message (using pre-allocated IDs)
    for (embed, embedEid) in fetchedEmbeds.zip embedEids do
      let dbEmbed : DbLinkEmbed := {
        id := embedEid.id.toNat
        url := embed.url
        embedType := embed.embedType
        title := embed.title
        description := embed.description
        thumbnailUrl := embed.thumbnailUrl
        authorName := embed.authorName
        videoId := embed.videoId
        message := msgEid
      }
      DbLinkEmbed.TxM.create embedEid dbEmbed
    audit "CREATE" "chat-message" msgEid.id.toNat [("thread_id", toString id), ("attachment_count", toString attachmentIds.length), ("embed_count", toString fetchedEmbeds.length)]
  let eid := msgEid
  let ctx ← getCtx
  let (viewUserName, viewAttachments) := match ctx.database with
    | some db =>
      let name := getUserNameFromDb db userId
      let atts := attachmentIds.filterMap fun attId =>
        match DbChatAttachment.pull db ⟨attId⟩ with
        | some a => some { id := a.id, fileName := a.fileName, mimeType := a.mimeType, fileSize := a.fileSize, url := s!"/uploads/{a.storedPath}" }
        | none => none
      (name, atts)
    | none => ("Unknown", [])
  let msg : Message := {
    id := eid.id.toNat
    content := content.trim
    timestamp := now
    userName := viewUserName
    attachments := viewAttachments
    embeds := fetchedEmbeds
  }
  let messageId := eid.id.toNat
  let threadId := id
  let _ ← SSE.publishEvent "chat" "message-added" (jsonStr! { messageId, threadId })
  Loom.Stencil.ActionM.render "chat/message" (messageToValue msg now)

-- Get single message (for SSE append)
view chatGetMessage "/chat/message/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let now ← getNowMs
  match ctx.database with
  | none => notFound "Database not available"
  | some db =>
    let msgId : EntityId := ⟨id⟩
    match DbChatMessage.pull db msgId with
    | none => notFound "Message not found"
    | some dbMsg =>
      let msg := toViewMessageWithAttachments db msgId dbMsg
      Loom.Stencil.ActionM.render "chat/message" (messageToValue msg now)

-- Search
view chatSearch "/chat/search" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let query := ctx.paramD "q" ""
  if query.trim.isEmpty then
    return ← html ""
  let now ← getNowMs
  match ctx.database with
  | none => badRequest "Database not available"
  | some db =>
    let allMsgIds := db.entitiesWithAttr DbChatMessage.attr_content
    let queryLower := query.toLower
    let results := allMsgIds.filterMap fun msgId =>
      match DbChatMessage.pull db msgId with
      | some msg =>
        if String.containsSubstr msg.content.toLower queryLower then
          match DbChatThread.pull db msg.thread with
          | some thread =>
            let viewThread := toViewThread db msg.thread thread
            let viewMsg := toViewMessage db msg
            some (viewThread, viewMsg)
          | none => none
        else none
      | none => none
    let sortedResults := results.toArray.qsort (fun a b => a.2.timestamp > b.2.timestamp) |>.toList
    Loom.Stencil.ActionM.render "chat/search-results" (searchResultsData query sortedResults now)

-- Upload attachment
action chatUploadAttachment "/chat/thread/:id/upload" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match ctx.file "file" with
  | none => json "{\"error\": \"No file uploaded\"}"
  | some file =>
    if file.content.size > maxFileSize then
      return ← json "{\"error\": \"File too large (max 10MB)\"}"
    let mimeType := file.contentType.getD "application/octet-stream"
    if !isAllowedType mimeType then
      return ← json "{\"error\": \"File type not allowed\"}"
    let storedPath ← storeFile file.content (file.filename.getD "upload")
    let now ← getNowMs
    let (eid, _) ← withNewEntityAudit! fun eid => do
      let attachment : DbChatAttachment := {
        id := eid.id.toNat
        fileName := file.filename.getD "upload"
        storedPath := storedPath
        mimeType := mimeType
        fileSize := file.content.size
        uploadedAt := now
        message := EntityId.null
      }
      DbChatAttachment.TxM.create eid attachment
      audit "CREATE" "chat-attachment" eid.id.toNat [("thread_id", toString id), ("file_name", file.filename.getD "upload")]
    let fileName := file.filename.getD "upload"
    let aid := eid.id.toNat
    json (jsonStr! { "id" : aid, "fileName" : fileName, "storedPath" : storedPath })

-- Serve upload
view chatServeUpload "/uploads/:filename" [] (filename : String) do
  if filename.isEmpty || !Upload.isSafePath filename then
    return ← notFound "File not found"
  match ← Upload.readFile filename with
  | none => notFound "File not found"
  | some content =>
    let mimeType := Upload.mimeTypeForFile filename
    let resp := Citadel.ResponseBuilder.withStatus Herald.Core.StatusCode.ok
      |>.withHeader "Content-Type" mimeType
      |>.withHeader "Content-Length" (toString content.size)
      |>.withHeader "Cache-Control" "public, max-age=31536000"
      |>.withBody content
      |>.build
    pure resp

-- Delete attachment
action chatDeleteAttachment "/chat/attachment/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => json "{\"error\": \"Database not available\"}"
  | some db =>
    let attId : EntityId := ⟨id⟩
    match DbChatAttachment.pull db attId with
    | none => json "{\"error\": \"Attachment not found\"}"
    | some attachment =>
      let _ ← Upload.deleteFile attachment.storedPath
      runAuditTx! do
        DbChatAttachment.TxM.delete attId
        audit "DELETE" "chat-attachment" id [("file_name", attachment.fileName)]
      json "{\"success\": true}"

end HomebaseApp.Pages
