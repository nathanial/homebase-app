/-
  HomebaseApp.Embeds - URL detection and link embed metadata fetching

  Detects URLs in message content and fetches metadata for:
  - YouTube videos (thumbnail from img.youtube.com)
  - Twitter/X posts (OpenGraph metadata)
  - Generic links (OpenGraph metadata)
-/
import Wisp
import Staple

namespace HomebaseApp.Embeds

open Wisp
open Staple (String.containsSubstr)

/-- Link embed metadata extracted from a URL. -/
structure LinkEmbed where
  url : String
  embedType : String        -- "youtube" | "twitter" | "generic"
  title : String
  description : String
  thumbnailUrl : String
  authorName : String       -- For Twitter
  videoId : String          -- For YouTube
  deriving Inhabited, Repr

/-- HTTP client for fetching metadata. -/
def httpClient : HTTP.Client :=
  HTTP.Client.new
    |>.withTimeout 5000      -- 5 second timeout
    |>.withFollowRedirects true

-- ============================================================================
-- String Helpers
-- ============================================================================

/-- Find the index of a substring in a string. Returns none if not found. -/
def findSubstrIdx (haystack needle : String) : Option Nat :=
  -- Use splitOn to find if needle exists and where
  let parts := haystack.splitOn needle
  if parts.length <= 1 then none
  else some parts[0]!.length

/-- Check if a string contains a substring. -/
def containsSubstr (haystack needle : String) : Bool :=
  String.containsSubstr haystack needle

-- ============================================================================
-- URL Detection
-- ============================================================================

/-- Check if a character is valid in a URL (simplified). -/
private def isUrlChar (c : Char) : Bool :=
  c.isAlphanum || c ∈ ['/', '.', '-', '_', '?', '&', '=', '%', '#', ':', '@', '+', '~', '!', '$', '\'', '(', ')', '*', ',', ';']

/-- Extract a URL starting at position i in the string. -/
private def extractUrl (s : String) (startIdx : Nat) : Option String := do
  let chars := s.toList.drop startIdx
  let urlChars := chars.takeWhile isUrlChar
  let url := String.mk urlChars
  -- Validate it looks like a URL
  if url.length < 10 then none
  else if !url.startsWith "http://" && !url.startsWith "https://" then none
  else some url

/-- Find all URLs in a text string. -/
def detectUrls (content : String) : List String := Id.run do
  let mut urls : List String := []
  let mut i := 0
  let chars := content.toList

  while i < chars.length do
    -- Look for "http://" or "https://"
    let remaining := String.mk (chars.drop i)
    if remaining.startsWith "http://" || remaining.startsWith "https://" then
      if let some url := extractUrl content i then
        -- Don't add duplicates
        if !urls.contains url then
          urls := urls ++ [url]
        i := i + url.length
      else
        i := i + 1
    else
      i := i + 1

  urls

-- ============================================================================
-- URL Classification
-- ============================================================================

/-- Extract YouTube video ID from a URL. -/
def extractYouTubeVideoId (url : String) : Option String := do
  -- youtube.com/watch?v=VIDEO_ID
  if containsSubstr url "youtube.com/watch" then
    let parts := url.splitOn "v="
    if h : parts.length > 1 then
      let afterV := parts[1]
      let videoId := (afterV.splitOn "&")[0]!
      if videoId.length >= 11 then
        return videoId.take 11
  -- youtu.be/VIDEO_ID
  else if containsSubstr url "youtu.be/" then
    let parts := url.splitOn "youtu.be/"
    if h : parts.length > 1 then
      let afterDomain := parts[1]
      let videoId := (afterDomain.splitOn "?")[0]!
      if videoId.length >= 11 then
        return videoId.take 11
  -- youtube.com/embed/VIDEO_ID
  else if containsSubstr url "youtube.com/embed/" then
    let parts := url.splitOn "/embed/"
    if h : parts.length > 1 then
      let afterEmbed := parts[1]
      let videoId := (afterEmbed.splitOn "?")[0]!
      if videoId.length >= 11 then
        return videoId.take 11
  none

/-- Check if URL is a Twitter/X post. -/
def isTwitterUrl (url : String) : Bool :=
  (containsSubstr url "twitter.com/" && containsSubstr url "/status/") ||
  (containsSubstr url "x.com/" && containsSubstr url "/status/")

/-- Classify a URL into embed type. -/
def classifyUrl (url : String) : String :=
  if (extractYouTubeVideoId url).isSome then "youtube"
  else if isTwitterUrl url then "twitter"
  else "generic"

-- ============================================================================
-- OpenGraph Parsing
-- ============================================================================

/-- Try to extract content value given a pattern to search for -/
private def tryExtractContent (html : String) (pattern : String) : Option String :=
  match findSubstrIdx html pattern with
  | none => none
  | some idx =>
    let afterProp := html.drop (idx + pattern.length)
    -- Try content=" after property
    match findSubstrIdx afterProp "content=\"" with
    | some contentIdx =>
      let afterContent := afterProp.drop (contentIdx + 9)
      let value := afterContent.takeWhile (· != '"')
      if value.isEmpty then none else some value
    | none =>
      -- Try content=' after property
      match findSubstrIdx afterProp "content='" with
      | some contentIdx =>
        let afterContent := afterProp.drop (contentIdx + 9)
        let value := afterContent.takeWhile (· != '\'')
        if value.isEmpty then none else some value
      | none => none

/-- Try extracting with content BEFORE property (some HTML generators do this) -/
private def tryExtractContentReverse (html : String) (property : String) : Option String :=
  -- Look for: content="..." property="og:..."
  -- Search for the property, then look backwards in that meta tag for content
  match findSubstrIdx html property with
  | none => none
  | some idx =>
    -- Get the portion before the property
    let before := html.take idx
    -- Find the last content=" before this property (within ~200 chars)
    let searchArea := before.drop (if before.length > 200 then before.length - 200 else 0)
    -- Look for content=" in this area, take the last one
    let parts := searchArea.splitOn "content=\""
    if parts.length < 2 then none
    else
      -- Get the last part that has content
      let lastContentPart := parts[parts.length - 1]!
      let value := lastContentPart.takeWhile (· != '"')
      if value.isEmpty then none else some value

/-- Extract content from a meta tag like: <meta property="og:title" content="..."> -/
private def extractMetaContent (html : String) (property : String) : Option String :=
  -- Try different attribute patterns (content after property)
  tryExtractContent html s!"property=\"{property}\""
  <|> tryExtractContent html s!"property='{property}'"
  <|> tryExtractContent html s!"name=\"{property}\""
  <|> tryExtractContent html s!"name='{property}'"
  -- Also try content before property
  <|> tryExtractContentReverse html s!"property=\"{property}\""

/-- Extract <title> tag content. -/
private def extractTitle (html : String) : Option String := do
  if let some startIdx := findSubstrIdx html "<title>" then
    let afterStart := html.drop (startIdx + 7)
    if let some endIdx := findSubstrIdx afterStart "</title>" then
      let title := afterStart.take endIdx
      return title.trim
  none

/-- Parse OpenGraph metadata from HTML. -/
def parseOpenGraph (html : String) : (String × String × String) :=
  let ogTitle := (extractMetaContent html "og:title").getD ""
  let ogDesc := (extractMetaContent html "og:description").getD ""
  let ogImage := (extractMetaContent html "og:image").getD ""

  -- Fallback to regular title and description
  let title := if ogTitle.isEmpty then (extractTitle html).getD "" else ogTitle
  let desc := if ogDesc.isEmpty then (extractMetaContent html "description").getD "" else ogDesc

  (title, desc, ogImage)

/-- Extract Twitter author from URL path like /username/status/123. -/
private def extractTwitterAuthor (url : String) : String :=
  -- twitter.com/username/status/123 or x.com/username/status/123
  let parts := url.splitOn "/"
  -- Find the part before "status"
  let rec findAuthor (parts : List String) (prev : String) : String :=
    match parts with
    | [] => if prev.startsWith "@" then prev else "@" ++ prev
    | p :: ps =>
      if p == "status" then
        if prev.startsWith "@" then prev else "@" ++ prev
      else findAuthor ps p
  findAuthor parts ""

-- ============================================================================
-- Metadata Fetching
-- ============================================================================

/-- Build YouTube embed from video ID (no HTTP needed). -/
def buildYouTubeEmbed (url : String) (videoId : String) : LinkEmbed :=
  { url := url
  , embedType := "youtube"
  , title := "YouTube Video"  -- We don't fetch the actual title to avoid API calls
  , description := ""
  , thumbnailUrl := s!"https://img.youtube.com/vi/{videoId}/hqdefault.jpg"
  , authorName := ""
  , videoId := videoId
  }

/-- Fetch metadata for a generic URL via OpenGraph. -/
def fetchGenericMetadata (url : String) : IO (Option LinkEmbed) := do
  try
    let task ← httpClient.get url
    let result := task.get
    match result with
    | .ok resp =>
      if resp.status >= 200 && resp.status < 300 then
        let html := String.fromUTF8! resp.body
        let (title, desc, image) := parseOpenGraph html
        if title.isEmpty && desc.isEmpty && image.isEmpty then
          return none
        return some {
          url := url
          embedType := "generic"
          title := title
          description := desc.take 200  -- Truncate long descriptions
          thumbnailUrl := image
          authorName := ""
          videoId := ""
        }
      else
        return none
    | .error _ =>
      return none
  catch _ =>
    return none

/-- Convert Twitter/X URL to fxtwitter.com URL for metadata fetching.
    fxtwitter.com is a proxy that provides proper OpenGraph metadata. -/
private def toFxTwitterUrl (url : String) : String :=
  -- Replace twitter.com or x.com with fxtwitter.com
  let url' := if containsSubstr url "x.com/" then
    url.replace "x.com/" "fxtwitter.com/"
  else
    url.replace "twitter.com/" "fxtwitter.com/"
  url'

/-- Fetch metadata for a Twitter URL. -/
def fetchTwitterMetadata (url : String) : IO (Option LinkEmbed) := do
  try
    -- Use fxtwitter.com proxy which provides proper OpenGraph metadata
    let fetchUrl := toFxTwitterUrl url
    IO.println s!"[EMBED DEBUG] Fetching Twitter URL: {fetchUrl}"
    let task ← httpClient.get fetchUrl
    let result := task.get
    match result with
    | .ok resp =>
      IO.println s!"[EMBED DEBUG] Got response status: {resp.status}"
      if resp.status >= 200 && resp.status < 300 then
        let html := String.fromUTF8! resp.body
        IO.println s!"[EMBED DEBUG] HTML length: {html.length}"
        -- Debug: check if og:title exists in HTML
        let hasOgTitle := containsSubstr html "og:title"
        let hasOgDesc := containsSubstr html "og:description"
        IO.println s!"[EMBED DEBUG] Contains og:title: {hasOgTitle}, og:description: {hasOgDesc}"
        -- Try to find and show the meta tag
        if let some idx := findSubstrIdx html "og:description" then
          let snippet := (html.drop (idx - 30)).take 150
          IO.println s!"[EMBED DEBUG] Snippet around og:description: {snippet}"
        let (title, desc, image) := parseOpenGraph html
        IO.println s!"[EMBED DEBUG] Parsed - title: '{title}', desc: '{desc.take 50}...', image: '{image.take 50}...'"
        let author := extractTwitterAuthor url
        -- Use og:description as the tweet text
        let tweetText := if !desc.isEmpty then desc else title
        if tweetText.isEmpty then
          IO.println s!"[EMBED DEBUG] tweetText is empty, returning none"
          return none
        IO.println s!"[EMBED DEBUG] Success! Returning embed"
        return some {
          url := url  -- Keep original URL for linking
          embedType := "twitter"
          title := title
          description := tweetText.take 280  -- Tweet length limit
          thumbnailUrl := image  -- fxtwitter provides images
          authorName := author
          videoId := ""
        }
      else
        IO.println s!"[EMBED DEBUG] Bad status code"
        return none
    | .error e =>
      IO.println s!"[EMBED DEBUG] HTTP error: {e}"
      return none
  catch e =>
    IO.println s!"[EMBED DEBUG] Exception: {e}"
    return none

/-- Fetch embed metadata for a URL. Returns none if fetching fails or URL is invalid. -/
def fetchEmbedMetadata (url : String) : IO (Option LinkEmbed) := do
  let embedType := classifyUrl url
  IO.println s!"[EMBED DEBUG] URL: {url} -> classified as: {embedType}"

  match embedType with
  | "youtube" =>
    match extractYouTubeVideoId url with
    | some videoId => return some (buildYouTubeEmbed url videoId)
    | none => return none
  | "twitter" =>
    fetchTwitterMetadata url
  | _ =>
    fetchGenericMetadata url

/-- Fetch embed metadata for multiple URLs, limiting to maxEmbeds.
    Returns list of successfully fetched embeds. -/
def fetchEmbedsForUrls (urls : List String) (maxEmbeds : Nat := 3) : IO (List LinkEmbed) := do
  let mut embeds : List LinkEmbed := []
  for url in urls.take maxEmbeds do
    if let some embed ← fetchEmbedMetadata url then
      embeds := embeds ++ [embed]
  return embeds

end HomebaseApp.Embeds
