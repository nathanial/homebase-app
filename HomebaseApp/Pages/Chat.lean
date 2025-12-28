/-
  HomebaseApp.Pages.Chat - Chat section with threads, messages, and file uploads
-/
import Scribe
import Loom
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

/-! ## View Helpers -/

def renderAttachment (att : Attachment) : HtmlM Unit := do
  if att.mimeType.startsWith "image/" then
    a [href_ att.url, target_ "_blank", class_ "chat-attachment-image"] do
      img [src_ att.url, alt_ att.fileName, class_ "chat-attachment-thumbnail"]
  else
    a [href_ att.url, download_ att.fileName, class_ "chat-attachment-file"] do
      span [class_ "chat-attachment-icon"] (text "📎")
      span [class_ "chat-attachment-name"] (text att.fileName)
      span [class_ "chat-attachment-size"] (text (formatFileSize att.fileSize))

/-! ## Embed Rendering -/

def renderYouTubeEmbed (embed : Embeds.LinkEmbed) : HtmlM Unit := do
  a [href_ embed.url, target_ "_blank", class_ "chat-embed-youtube-link"] do
    div [class_ "chat-embed-youtube-thumb"] do
      img [src_ embed.thumbnailUrl, alt_ embed.title]
      div [class_ "chat-embed-play-icon"] (text "▶")
    if !embed.title.isEmpty && embed.title != "YouTube Video" then
      div [class_ "chat-embed-youtube-info"] do
        div [class_ "chat-embed-title"] (text embed.title)

def renderTwitterEmbed (embed : Embeds.LinkEmbed) : HtmlM Unit := do
  a [href_ embed.url, target_ "_blank", class_ "chat-embed-twitter-link"] do
    div [class_ "chat-embed-twitter-header"] do
      span [class_ "chat-embed-twitter-icon"] (text "𝕏")
      if !embed.authorName.isEmpty then
        span [class_ "chat-embed-twitter-author"] (text embed.authorName)
    if !embed.description.isEmpty then
      div [class_ "chat-embed-twitter-text"] (text embed.description)
    -- Show image if available (fxtwitter provides these)
    if !embed.thumbnailUrl.isEmpty then
      img [src_ embed.thumbnailUrl, alt_ "", class_ "chat-embed-twitter-image"]

def renderGenericEmbed (embed : Embeds.LinkEmbed) : HtmlM Unit := do
  a [href_ embed.url, target_ "_blank", class_ "chat-embed-generic-link"] do
    if !embed.thumbnailUrl.isEmpty then
      img [src_ embed.thumbnailUrl, alt_ "", class_ "chat-embed-generic-thumb"]
    div [class_ "chat-embed-generic-info"] do
      if !embed.title.isEmpty then
        div [class_ "chat-embed-title"] (text embed.title)
      if !embed.description.isEmpty then
        div [class_ "chat-embed-description"] (text embed.description)

def renderEmbed (embed : Embeds.LinkEmbed) : HtmlM Unit := do
  div [class_ s!"chat-embed chat-embed-{embed.embedType}"] do
    match embed.embedType with
    | "youtube" => renderYouTubeEmbed embed
    | "twitter" => renderTwitterEmbed embed
    | _ => renderGenericEmbed embed


def renderThreadItem (thread : Thread) (isActive : Bool) (now : Nat) : HtmlM Unit := do
  let activeClass := if isActive then " chat-thread-active" else ""
  div [id_ s!"thread-{thread.id}",
       class_ s!"chat-thread-item{activeClass}",
       attr_ "hx-get" s!"/chat/thread/{thread.id}",
       hx_target "#chat-messages-area",
       hx_swap "innerHTML",
       attr_ "hx-push-url" "true"] do
    div [class_ "chat-thread-header"] do
      h4 [class_ "chat-thread-title"] (text thread.title)
      span [class_ "chat-thread-time"] (text (formatRelativeTime thread.createdAt now))
    match thread.lastMessage with
    | some preview =>
      let truncated := if preview.length > 50 then preview.take 50 ++ "..." else preview
      p [class_ "chat-thread-preview"] (text truncated)
    | none => pure ()
    div [class_ "chat-thread-meta"] do
      span [class_ "chat-thread-count"] (text s!"{thread.messageCount} messages")

def renderMessage (msg : Message) (now : Nat) : HtmlM Unit := do
  div [id_ s!"message-{msg.id}", class_ "chat-message"] do
    div [class_ "chat-message-header"] do
      span [class_ "chat-message-author"] (text msg.userName)
      span [class_ "chat-message-time"] (text (formatRelativeTime msg.timestamp now))
    div [class_ "chat-message-content"] do
      for line in msg.content.splitOn "\n" do
        p [] (text line)
    -- Render embeds (link previews)
    if !msg.embeds.isEmpty then
      div [class_ "chat-embeds"] do
        for embed in msg.embeds do
          renderEmbed embed
    -- Render attachments (uploaded files)
    if !msg.attachments.isEmpty then
      div [class_ "chat-attachments"] do
        for att in msg.attachments do
          renderAttachment att

def renderMessageInput (ctx : Context) (threadId : Nat) : HtmlM Unit := do
  form [id_ "message-form",
        attr_ "hx-post" s!"/chat/thread/{threadId}/message",
        hx_target "#messages-list",
        hx_swap "beforeend",
        attr_ "hx-on::after-request" "afterMessageSubmit(this)"] do
    input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
    input [type_ "hidden", name_ "attachments", id_ "attachments-input", value_ ""]
    -- Hidden file input
    input [type_ "file", id_ "file-input",
           class_ "chat-file-input",
           attr_ "multiple" "true",
           attr_ "accept" "image/*,.pdf,.txt",
           attr_ "onchange" "handleFileSelect(this.files)",
           attr_ "data-thread-id" (toString threadId)]
    -- Preview area for pending files
    div [id_ "upload-preview", class_ "chat-upload-preview"] (pure ())
    -- Input container with drag/drop support
    div [class_ "chat-input-container",
         id_ "chat-input-drop-zone",
         attr_ "ondragover" "handleDragOver(event)",
         attr_ "ondragleave" "handleDragLeave(event)",
         attr_ "ondrop" "handleInputDrop(event)"] do
      textarea [name_ "content", id_ "message-content",
                class_ "chat-input",
                placeholder_ "Type a message or drop files here...",
                rows_ 2,
                attr_ "onkeydown" "if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); submitMessageWithAttachments(); }"]
      -- Attach button
      button [type_ "button", class_ "chat-attach-btn",
              attr_ "onclick" "document.getElementById('file-input').click()",
              title_ "Attach files"]
        (text "📎")
      button [type_ "submit", class_ "chat-send-btn",
              attr_ "onclick" "event.preventDefault(); submitMessageWithAttachments()"]
        (text "Send")

def renderThreadList (threads : List Thread) (activeThreadId : Option Nat) (now : Nat) : HtmlM Unit := do
  div [id_ "chat-threads", class_ "chat-threads"] do
    div [class_ "chat-threads-header"] do
      h2 [] (text "Threads")
      button [class_ "btn btn-primary btn-sm",
              attr_ "hx-get" "/chat/thread/new",
              hx_target "#modal-container",
              hx_swap "innerHTML"]
        (text "+ New Thread")
    div [id_ "threads-list", class_ "chat-threads-list"] do
      for thread in threads do
        renderThreadItem thread (activeThreadId == some thread.id) now

def renderMessageArea (ctx : Context) (thread : Thread) (messages : List Message) (now : Nat) : HtmlM Unit := do
  div [class_ "chat-message-area"] do
    div [class_ "chat-message-header-bar"] do
      h2 [class_ "chat-current-title"] (text thread.title)
      div [class_ "chat-message-actions"] do
        button [class_ "btn-icon",
                attr_ "hx-get" s!"/chat/thread/{thread.id}/edit",
                hx_target "#modal-container",
                hx_swap "innerHTML"]
          (text "Edit")
        button [class_ "btn-icon btn-icon-danger",
                attr_ "hx-delete" s!"/chat/thread/{thread.id}",
                hx_target "#chat-container",
                hx_swap "innerHTML",
                hx_confirm s!"Delete thread '{thread.title}' and all its messages?"]
          (text "Delete")
    div [id_ "messages-list", class_ "chat-messages-list"] do
      for msg in messages do
        renderMessage msg now
    renderMessageInput ctx thread.id

def renderEmptyState : HtmlM Unit := do
  div [class_ "chat-empty-state"] do
    div [class_ "text-6xl mb-4"] (text "Select a thread")
    p [] (text "Choose a thread from the sidebar or create a new one.")

def renderNewThreadForm (ctx : Context) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-sm"] do
      h3 [class_ "modal-title"] (text "New Thread")
      form [attr_ "hx-post" "/chat/thread",
            hx_target "#threads-list",
            hx_swap "afterbegin",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "title", class_ "form-label"] (text "Thread Title")
            input [type_ "text", name_ "title", id_ "title",
                   class_ "form-input", placeholder_ "Enter thread title", required_, autofocus_]
          div [class_ "form-actions"] do
            button [type_ "button", class_ "btn btn-secondary",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"]
              (text "Create Thread")

def renderEditThreadForm (ctx : Context) (thread : Thread) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-sm"] do
      h3 [class_ "modal-title"] (text "Edit Thread")
      form [attr_ "hx-put" s!"/chat/thread/{thread.id}",
            hx_target s!"#thread-{thread.id}",
            hx_swap "outerHTML",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "title", class_ "form-label"] (text "Thread Title")
            input [type_ "text", name_ "title", id_ "title", value_ thread.title,
                   class_ "form-input", placeholder_ "Enter thread title", required_, autofocus_]
          div [class_ "form-actions"] do
            button [type_ "button", class_ "btn btn-secondary",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"]
              (text "Save Changes")

def renderSearchResults (query : String) (results : List (Thread × Message)) (now : Nat) : HtmlM Unit := do
  div [class_ "chat-search-results"] do
    h3 [] (text s!"Search results for \"{query}\"")
    if results.isEmpty then
      p [class_ "text-slate-500"] (text "No messages found.")
    else
      for (thread, msg) in results do
        div [class_ "chat-search-result",
             attr_ "hx-get" s!"/chat/thread/{thread.id}",
             hx_target "#chat-messages-area",
             hx_swap "innerHTML"] do
          div [class_ "chat-search-thread"] (text s!"in {thread.title}")
          renderMessage msg now

def chatContent (ctx : Context) (threads : List Thread) (activeThread : Option Thread)
    (messages : List Message) (now : Nat) : HtmlM Unit := do
  div [id_ "chat-container", class_ "chat-container"] do
    div [class_ "chat-sidebar"] do
      div [class_ "chat-search"] do
        input [type_ "search",
               name_ "q",
               class_ "chat-search-input",
               placeholder_ "Search messages...",
               attr_ "hx-get" "/chat/search",
               attr_ "hx-trigger" "keyup changed delay:300ms",
               hx_target "#chat-messages-area",
               hx_swap "innerHTML"]
      renderThreadList threads (activeThread.map (·.id)) now
    div [id_ "chat-messages-area", class_ "chat-main"] do
      div [id_ "chat-main-content"] do
        match activeThread with
        | some thread => renderMessageArea ctx thread messages now
        | none => renderEmptyState
  div [id_ "modal-container"] do
    pure ()
  script [src_ "/js/chat.js"]

/-! ## Pages -/

-- Chat index
view chat "/chat" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let now ← getNowMs
  match ctx.database with
  | none =>
    if ctx.header "HX-Request" == some "true" then
      html (HtmlM.render (renderThreadList [] none now))
    else
      html (Shared.render ctx "Chat - Homebase" "/chat" (chatContent ctx [] none [] now))
  | some db =>
    let threadData := getThreads ctx
    let threads := threadData.map fun (tid, t) => toViewThread db tid t
    if ctx.header "HX-Request" == some "true" then
      html (HtmlM.render (renderThreadList threads none now))
    else
      html (Shared.render ctx "Chat - Homebase" "/chat" (chatContent ctx threads none [] now))

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
        html (HtmlM.render (renderMessageArea ctx thread messages now))
      else
        let threadData := getThreads ctx
        let threads := threadData.map fun (tid, t) => toViewThread db tid t
        html (Shared.render ctx "Chat - Homebase" "/chat" (chatContent ctx threads (some thread) messages now))

-- New thread form
view chatNewThreadForm "/chat/thread/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render (renderNewThreadForm ctx))

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
  html (HtmlM.render (renderThreadItem thread false now))

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
      html (HtmlM.render (renderEditThreadForm ctx thread))

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
      html (HtmlM.render (renderThreadItem thread false now))

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
  html (HtmlM.render renderEmptyState)

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
  html (HtmlM.render (renderMessage msg now))

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
      html (HtmlM.render (renderMessage msg now))

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
    html (HtmlM.render (renderSearchResults query sortedResults now))

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
