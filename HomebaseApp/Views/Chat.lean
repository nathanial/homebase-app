/-
  HomebaseApp.Views.Chat - Chat section view with threads and messages
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout
import HomebaseApp.Routes

namespace HomebaseApp.Views.Chat

open Scribe
open Loom
open HomebaseApp.Views.Layout
open HomebaseApp (Route)

-- ============================================================================
-- Data structures for view rendering
-- ============================================================================

/-- Attachment display info for view rendering -/
structure Attachment where
  id : Nat
  fileName : String
  mimeType : String
  fileSize : Nat
  url : String           -- /uploads/{storedPath}
  deriving Inhabited

structure Message where
  id : Nat
  content : String
  timestamp : Nat        -- milliseconds since epoch
  userName : String
  attachments : List Attachment := []
  deriving Inhabited

structure Thread where
  id : Nat
  title : String
  createdAt : Nat
  messageCount : Nat
  lastMessage : Option String  -- Preview of last message
  deriving Inhabited

-- ============================================================================
-- Timestamp formatting helpers
-- ============================================================================

/-- Format timestamp as relative time (e.g., "5 minutes ago", "2 hours ago") -/
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

/-- Format file size in human readable format -/
def formatFileSize (bytes : Nat) : String :=
  if bytes < 1024 then s!"{bytes} B"
  else if bytes < 1024 * 1024 then s!"{bytes / 1024} KB"
  else s!"{bytes / (1024 * 1024)} MB"

-- ============================================================================
-- Component rendering functions
-- ============================================================================

/-- Render a single attachment (image thumbnail or file link) -/
def renderAttachment (att : Attachment) : HtmlM Unit := do
  if att.mimeType.startsWith "image/" then
    -- Render as clickable image thumbnail
    a [href_ att.url, target_ "_blank", class_ "chat-attachment-image"] do
      img [src_ att.url, alt_ att.fileName, class_ "chat-attachment-thumbnail"]
  else
    -- Render as download link
    a [href_ att.url, download_ att.fileName, class_ "chat-attachment-file"] do
      span [class_ "chat-attachment-icon"] (text "📎")
      span [class_ "chat-attachment-name"] (text att.fileName)
      span [class_ "chat-attachment-size"] (text (formatFileSize att.fileSize))

/-- Render the file upload drop zone -/
def renderUploadZone (threadId : Nat) : HtmlM Unit := do
  div [id_ "upload-zone", class_ "chat-upload-zone",
       attr_ "ondragover" "event.preventDefault(); this.classList.add('dragover')",
       attr_ "ondragleave" "this.classList.remove('dragover')",
       attr_ "ondrop" "handleFileDrop(event, this)"] do
    input [type_ "file", id_ "file-input",
           class_ "chat-file-input",
           attr_ "multiple" "true",
           attr_ "accept" "image/*,.pdf,.txt",
           attr_ "onchange" "handleFileSelect(this.files)",
           attr_ "data-thread-id" (toString threadId)]
    label [for_ "file-input", class_ "chat-upload-label"] do
      span [class_ "chat-upload-icon"] (text "📁")
      text "Drop files here or click to upload"
  div [id_ "upload-preview", class_ "chat-upload-preview"] (pure ())

/-- Render a single thread in the sidebar list -/
def renderThreadItem (thread : Thread) (isActive : Bool) (now : Nat) : HtmlM Unit := do
  let activeClass := if isActive then " chat-thread-active" else ""
  div [id_ s!"thread-{thread.id}",
       class_ s!"chat-thread-item{activeClass}",
       hx_get' (Route.chatThread thread.id),
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

/-- Render a single message -/
def renderMessage (msg : Message) (now : Nat) : HtmlM Unit := do
  div [id_ s!"message-{msg.id}", class_ "chat-message"] do
    div [class_ "chat-message-header"] do
      span [class_ "chat-message-author"] (text msg.userName)
      span [class_ "chat-message-time"] (text (formatRelativeTime msg.timestamp now))
    div [class_ "chat-message-content"] do
      -- Preserve line breaks in message content
      for line in msg.content.splitOn "\n" do
        p [] (text line)
    -- Render attachments if any
    if !msg.attachments.isEmpty then
      div [class_ "chat-attachments"] do
        for att in msg.attachments do
          renderAttachment att

/-- Render the message input form -/
def renderMessageInput (ctx : Context) (threadId : Nat) : HtmlM Unit := do
  -- Upload zone (above the input form)
  renderUploadZone threadId

  -- Message form
  form [id_ "message-form",
        hx_post' (Route.chatAddMessage threadId),
        hx_target "#messages-list",
        hx_swap "beforeend",
        attr_ "hx-on::after-request" "afterMessageSubmit(this)"] do
    input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
    input [type_ "hidden", name_ "attachments", id_ "attachments-input", value_ ""]
    div [class_ "chat-input-container"] do
      textarea [name_ "content", id_ "message-content",
                class_ "chat-input",
                placeholder_ "Type your message...",
                rows_ 2,
                attr_ "onkeydown" "if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); submitMessageWithAttachments(); }"]
      button [type_ "submit", class_ "chat-send-btn",
              attr_ "onclick" "event.preventDefault(); submitMessageWithAttachments()"]
        (text "Send")

/-- Render the thread list sidebar -/
def renderThreadList (threads : List Thread) (activeThreadId : Option Nat) (now : Nat) : HtmlM Unit := do
  div [id_ "chat-threads", class_ "chat-threads"] do
    div [class_ "chat-threads-header"] do
      h2 [] (text "Threads")
      button [class_ "btn btn-primary btn-sm",
              hx_get' Route.chatNewThreadForm,
              hx_target "#modal-container",
              hx_swap "innerHTML"]
        (text "+ New Thread")
    div [id_ "threads-list", class_ "chat-threads-list"] do
      for thread in threads do
        renderThreadItem thread (activeThreadId == some thread.id) now

/-- Render the message area for a thread -/
def renderMessageArea (ctx : Context) (thread : Thread) (messages : List Message) (now : Nat) : HtmlM Unit := do
  div [class_ "chat-message-area"] do
    -- Thread header with actions
    div [class_ "chat-message-header-bar"] do
      h2 [class_ "chat-current-title"] (text thread.title)
      div [class_ "chat-message-actions"] do
        button [class_ "btn-icon",
                hx_get' (Route.chatEditThreadForm thread.id),
                hx_target "#modal-container",
                hx_swap "innerHTML"]
          (text "Edit")
        button [class_ "btn-icon btn-icon-danger",
                hx_delete' (Route.chatDeleteThread thread.id),
                hx_target "#chat-container",
                hx_swap "innerHTML",
                hx_confirm s!"Delete thread '{thread.title}' and all its messages?"]
          (text "Delete")
    -- Messages container (scrollable)
    div [id_ "messages-list", class_ "chat-messages-list"] do
      for msg in messages do
        renderMessage msg now
    -- Message input
    renderMessageInput ctx thread.id

/-- Render empty state when no thread is selected -/
def renderEmptyState : HtmlM Unit := do
  div [class_ "chat-empty-state"] do
    div [class_ "text-6xl mb-4"] (text "Select a thread")
    p [] (text "Choose a thread from the sidebar or create a new one.")

/-- Render new thread form modal -/
def renderNewThreadForm (ctx : Context) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-sm"] do
      h3 [class_ "modal-title"] (text "New Thread")
      form [hx_post' Route.chatCreateThread,
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

/-- Render edit thread form modal -/
def renderEditThreadForm (ctx : Context) (thread : Thread) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-sm"] do
      h3 [class_ "modal-title"] (text "Edit Thread")
      form [hx_put' (Route.chatUpdateThread thread.id),
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

/-- Render search results -/
def renderSearchResults (query : String) (results : List (Thread × Message)) (now : Nat) : HtmlM Unit := do
  div [class_ "chat-search-results"] do
    h3 [] (text s!"Search results for \"{query}\"")
    if results.isEmpty then
      p [class_ "text-slate-500"] (text "No messages found.")
    else
      for (thread, msg) in results do
        div [class_ "chat-search-result",
             hx_get' (Route.chatThread thread.id),
             hx_target "#chat-messages-area",
             hx_swap "innerHTML"] do
          div [class_ "chat-search-thread"] (text s!"in {thread.title}")
          renderMessage msg now

-- ============================================================================
-- Main content
-- ============================================================================

/-- Main chat page content -/
def chatContent (ctx : Context) (threads : List Thread) (activeThread : Option Thread)
    (messages : List Message) (now : Nat) : HtmlM Unit := do

  -- Chat container
  div [id_ "chat-container", class_ "chat-container"] do
    -- Sidebar with thread list
    div [class_ "chat-sidebar"] do
      -- Search bar
      div [class_ "chat-search"] do
        input [type_ "search",
               name_ "q",
               class_ "chat-search-input",
               placeholder_ "Search messages...",
               hx_get' Route.chatSearch,
               attr_ "hx-trigger" "keyup changed delay:300ms",
               hx_target "#chat-messages-area",
               hx_swap "innerHTML"]
      -- Thread list
      renderThreadList threads (activeThread.map (·.id)) now

    -- Main message area
    div [id_ "chat-messages-area", class_ "chat-main"] do
      div [id_ "chat-main-content"] do
        match activeThread with
        | some thread => renderMessageArea ctx thread messages now
        | none => renderEmptyState

  -- Modal container
  div [id_ "modal-container"] do
    pure ()

  -- Chat JavaScript (SSE handling)
  script [src' (Route.staticJs "chat.js")]

-- ============================================================================
-- Full page and partial renders
-- ============================================================================

/-- Full page render -/
def render (ctx : Context) (threads : List Thread) (activeThread : Option Thread)
    (messages : List Message) (now : Nat) : String :=
  Layout.render ctx "Chat - Homebase" "/chat" (chatContent ctx threads activeThread messages now)

/-- Render just the thread list (for SSE refresh) -/
def renderThreadListPartial (threads : List Thread) (activeThreadId : Option Nat) (now : Nat) : String :=
  HtmlM.render (renderThreadList threads activeThreadId now)

/-- Render just the messages area -/
def renderMessageAreaPartial (ctx : Context) (thread : Thread) (messages : List Message) (now : Nat) : String :=
  HtmlM.render (renderMessageArea ctx thread messages now)

/-- Render a single message (for HTMX append) -/
def renderMessagePartial (msg : Message) (now : Nat) : String :=
  HtmlM.render (renderMessage msg now)

/-- Render a single thread item -/
def renderThreadItemPartial (thread : Thread) (isActive : Bool) (now : Nat) : String :=
  HtmlM.render (renderThreadItem thread isActive now)

/-- Render new thread form modal -/
def renderNewThreadFormPartial (ctx : Context) : String :=
  HtmlM.render (renderNewThreadForm ctx)

/-- Render edit thread form modal -/
def renderEditThreadFormPartial (ctx : Context) (thread : Thread) : String :=
  HtmlM.render (renderEditThreadForm ctx thread)

/-- Render search results -/
def renderSearchResultsPartial (query : String) (results : List (Thread × Message)) (now : Nat) : String :=
  HtmlM.render (renderSearchResults query results now)

/-- Render thread deleted confirmation (shows empty state; thread list is refreshed via SSE) -/
def renderThreadDeletedPartial (_ctx : Context) (_threads : List Thread) (_now : Nat) : String :=
  HtmlM.render renderEmptyState

end HomebaseApp.Views.Chat
