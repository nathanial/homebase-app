/-
  HomebaseApp.Pages.GraphicNovel - AI-powered graphic novel maker
-/
import Scribe
import Loom
import Loom.SSE
import Loom.Stencil
import Stencil
import Ledger
import Citadel
import Oracle
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.Upload
import HomebaseApp.StencilHelpers

namespace HomebaseApp.Pages

open Scribe
open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.AuditTxM (audit)
open Loom.Json
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers
open HomebaseApp.Upload
open HomebaseApp.StencilHelpers

/-! ## Constants -/

/-- Valid layout templates -/
def validLayouts : List String := ["full", "two-panel", "three-panel", "four-grid", "six-grid"]

/-- Number of panels for each layout type -/
def panelCountForLayout : String → Nat
  | "full" => 1
  | "two-panel" => 2
  | "three-panel" => 3
  | "four-grid" => 4
  | "six-grid" => 6
  | _ => 1

/-! ## View Models -/

/-- Summary of a novel for list view -/
structure NovelSummary where
  id : Nat
  title : String
  description : String
  coverUrl : String
  pageCount : Nat
  updatedAt : Nat
  deriving Inhabited

/-- Panel view model -/
structure PanelView where
  id : Nat
  panelIndex : Nat
  prompt : String
  imageUrl : String
  caption : String
  status : String
  hasImage : Bool
  isGenerating : Bool
  isError : Bool
  deriving Inhabited

/-- Page view model -/
structure PageView where
  id : Nat
  pageNumber : Nat
  layoutTemplate : String
  panels : List PanelView
  deriving Inhabited

/-- Novel detail view model -/
structure NovelDetail where
  id : Nat
  title : String
  description : String
  pages : List PageView
  currentPage : Option PageView
  deriving Inhabited

/-! ## Stencil Value Helpers -/

def panelToValue (panel : PanelView) (novelId pageNum : Nat) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat panel.id)),
    ("panelIndex", .int (Int.ofNat panel.panelIndex)),
    ("prompt", .string panel.prompt),
    ("imageUrl", .string panel.imageUrl),
    ("caption", .string panel.caption),
    ("status", .string panel.status),
    ("hasImage", .bool panel.hasImage),
    ("isGenerating", .bool panel.isGenerating),
    ("isError", .bool panel.isError),
    ("novelId", .int (Int.ofNat novelId)),
    ("pageNumber", .int (Int.ofNat pageNum))
  ]

def pageToValue (pg : PageView) (novelId : Nat) (isActive : Bool) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat pg.id)),
    ("pageNumber", .int (Int.ofNat pg.pageNumber)),
    ("layoutTemplate", .string pg.layoutTemplate),
    ("panels", .array (pg.panels.map (panelToValue · novelId pg.pageNumber)).toArray),
    ("isActive", .bool isActive),
    ("novelId", .int (Int.ofNat novelId)),
    ("isFullLayout", .bool (pg.layoutTemplate == "full")),
    ("isTwoPanelLayout", .bool (pg.layoutTemplate == "two-panel")),
    ("isThreePanelLayout", .bool (pg.layoutTemplate == "three-panel")),
    ("isFourGridLayout", .bool (pg.layoutTemplate == "four-grid")),
    ("isSixGridLayout", .bool (pg.layoutTemplate == "six-grid"))
  ]

def novelSummaryToValue (novel : NovelSummary) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat novel.id)),
    ("title", .string novel.title),
    ("description", .string novel.description),
    ("coverUrl", .string novel.coverUrl),
    ("hasCover", .bool (!novel.coverUrl.isEmpty)),
    ("pageCount", .int (Int.ofNat novel.pageCount))
  ]

def novelDetailToValue (novel : NovelDetail) (currentPageNum : Option Nat) : Stencil.Value :=
  let pagesVal := novel.pages.map fun p =>
    pageToValue p novel.id (currentPageNum == some p.pageNumber)
  let currentVal := match novel.currentPage with
    | some p => pageToValue p novel.id true
    | none => .null
  .object #[
    ("id", .int (Int.ofNat novel.id)),
    ("title", .string novel.title),
    ("description", .string novel.description),
    ("pages", .array pagesVal.toArray),
    ("hasPages", .bool (!novel.pages.isEmpty)),
    ("currentPage", currentVal),
    ("hasCurrentPage", .bool novel.currentPage.isSome)
  ]

/-! ## Helpers -/

def novelGetNowMs : IO Nat := IO.monoMsNow

def novelGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-! ## Database Helpers -/

/-- Get all novels for current user -/
def getNovels (ctx : Context) : List NovelSummary :=
  match ctx.database, novelGetCurrentUserEid ctx with
  | some db, some userEid =>
    let novelIds := db.findByAttrValue DbGraphicNovel.attr_user (.ref userEid)
    let novels := novelIds.filterMap fun novelId =>
      match DbGraphicNovel.pull db novelId with
      | some novel =>
        -- Count pages for this novel
        let pageIds := db.findByAttrValue DbNovelPage.attr_novel (.ref novelId)
        let coverUrl := if novel.coverImagePath.isEmpty then "" else s!"/uploads/{novel.coverImagePath}"
        some { id := novel.id, title := novel.title, description := novel.description,
               coverUrl := coverUrl, pageCount := pageIds.length, updatedAt := novel.updatedAt }
      | none => none
    novels.toArray.qsort (fun a b => a.updatedAt > b.updatedAt) |>.toList
  | _, _ => []

/-- Get a single novel by ID -/
def getNovel (ctx : Context) (novelId : Nat) : Option DbGraphicNovel :=
  match ctx.database with
  | some db => DbGraphicNovel.pull db ⟨novelId⟩
  | none => none

/-- Get panels for a page -/
def getPanelsForPage (db : Db) (pageEid : EntityId) : List PanelView :=
  let panelIds := db.findByAttrValue DbNovelPanel.attr_pageRef (.ref pageEid)
  let panels := panelIds.filterMap fun panelId =>
    match DbNovelPanel.pull db panelId with
    | some panel =>
      let imageUrl := if panel.imagePath.isEmpty then "" else s!"/uploads/{panel.imagePath}"
      some { id := panel.id, panelIndex := panel.panelIndex, prompt := panel.prompt,
             imageUrl := imageUrl, caption := panel.caption, status := panel.generationStatus,
             hasImage := !panel.imagePath.isEmpty,
             isGenerating := panel.generationStatus == "generating",
             isError := panel.generationStatus == "error" }
    | none => none
  panels.toArray.qsort (fun a b => a.panelIndex < b.panelIndex) |>.toList

/-- Get pages for a novel -/
def getPagesForNovel (db : Db) (novelEid : EntityId) : List PageView :=
  let pageIds := db.findByAttrValue DbNovelPage.attr_novel (.ref novelEid)
  let pages := pageIds.filterMap fun pageId =>
    match DbNovelPage.pull db pageId with
    | some pg =>
      let panels := getPanelsForPage db pageId
      some { id := pg.id, pageNumber := pg.pageNumber,
             layoutTemplate := pg.layoutTemplate, panels := panels }
    | none => none
  pages.toArray.qsort (fun a b => a.pageNumber < b.pageNumber) |>.toList

/-- Get novel detail with all pages -/
def getNovelDetail (ctx : Context) (novelId : Nat) (currentPageNum : Option Nat) : Option NovelDetail :=
  match ctx.database with
  | some db =>
    let novelEid : EntityId := ⟨novelId⟩
    match DbGraphicNovel.pull db novelEid with
    | some novel =>
      let pages := getPagesForNovel db novelEid
      let currentPage := match currentPageNum with
        | some num => pages.find? (·.pageNumber == num)
        | none => pages.head?
      some { id := novel.id, title := novel.title, description := novel.description,
             pages := pages, currentPage := currentPage }
    | none => none
  | none => none

/-- Get page entity by novel and page number -/
def getPageByNumber (db : Db) (novelEid : EntityId) (pageNum : Nat) : Option (EntityId × DbNovelPage) :=
  let pageIds := db.findByAttrValue DbNovelPage.attr_novel (.ref novelEid)
  pageIds.findSome? fun pageId =>
    match DbNovelPage.pull db pageId with
    | some pg => if pg.pageNumber == pageNum then some (pageId, pg) else none
    | none => none

/-- Get panel entity by page and panel index -/
def getPanelByIndex (db : Db) (pageEid : EntityId) (panelIdx : Nat) : Option (EntityId × DbNovelPanel) :=
  let panelIds := db.findByAttrValue DbNovelPanel.attr_pageRef (.ref pageEid)
  panelIds.findSome? fun panelId =>
    match DbNovelPanel.pull db panelId with
    | some panel => if panel.panelIndex == panelIdx then some (panelId, panel) else none
    | none => none

/-- Create panels for a page based on layout (call from ActionM) -/
def createPanelsForPageM (pageEid : EntityId) (layout : String) : ActionM Unit := do
  let panelCount := panelCountForLayout layout
  for i in [:panelCount] do
    let _ ← withNewEntityAudit! fun panelEid => do
      let panel : DbNovelPanel := {
        id := panelEid.id.toNat
        panelIndex := i
        prompt := ""
        imagePath := ""
        caption := ""
        generationStatus := "pending"
        pageRef := pageEid
      }
      DbNovelPanel.TxM.create panelEid panel
      pure ()

/-! ## Pages -/

-- List all novels
view novelsPage "/novels" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let novels := getNovels ctx
  let data := pageContext ctx "Graphic Novels" PageId.novels
    (.object #[
      ("novels", .array (novels.map novelSummaryToValue).toArray),
      ("hasNovels", .bool (!novels.isEmpty))
    ])
  Loom.Stencil.ActionM.renderWithLayout "app" "novels/index" data

-- New novel form (full page)
view novelNewForm "/novels/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let data := pageContext ctx "New Novel" PageId.novels (.object #[])
  Loom.Stencil.ActionM.renderWithLayout "app" "novels/new" data

-- Create novel
action novelCreate "/novels" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  match novelGetCurrentUserEid ctx with
  | none => redirect "/login"
  | some userEid =>
    let title := ctx.paramD "title" "Untitled Novel"
    let description := ctx.paramD "description" ""
    let now ← novelGetNowMs
    -- Create novel
    let (novelEid, _) ← withNewEntityAudit! fun novelEid => do
      let novel : DbGraphicNovel := { id := novelEid.id.toNat, title := title, description := description,
                                      coverImagePath := "", createdAt := now, updatedAt := now, user := userEid }
      DbGraphicNovel.TxM.create novelEid novel
      audit "CREATE" "graphic-novel" novelEid.id.toNat [("title", title)]
    -- Create first page
    let (pageEid, _) ← withNewEntityAudit! fun pageEid => do
      let novelPage : DbNovelPage := { id := pageEid.id.toNat, pageNumber := 1, layoutTemplate := "full", novel := novelEid, createdAt := now }
      DbNovelPage.TxM.create pageEid novelPage
      audit "CREATE" "novel-page" pageEid.id.toNat [("page_number", "1")]
    -- Create panels for the page
    createPanelsForPageM pageEid "full"
    let novelId := novelEid.id.toNat
    let _ ← SSE.publishEvent "novels" "novel-created" (jsonStr! { novelId, title })
    redirect s!"/novels/{novelId}"

-- Edit novel form (full page)
view novelEditForm "/novels/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNovel ctx id with
  | none => notFound "Novel not found"
  | some novel =>
    let data := pageContext ctx "Edit Novel" PageId.novels
      (.object #[
        ("id", .int (Int.ofNat novel.id)),
        ("title", .string novel.title),
        ("description", .string novel.description)
      ])
    Loom.Stencil.ActionM.renderWithLayout "app" "novels/edit" data

-- View/edit novel
view novelView "/novels/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let pageNum := ctx.param "page" >>= String.toNat?
  match getNovelDetail ctx id pageNum with
  | none => notFound "Novel not found"
  | some novel =>
    let data := pageContext ctx novel.title PageId.novels
      (novelDetailToValue novel pageNum)
    Loom.Stencil.ActionM.renderWithLayout "app" "novels/show" data

-- View specific page
view novelPageView "/novels/:id/page/:pageNum" [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) do
  let ctx ← getCtx
  match getNovelDetail ctx id (some pageNum) with
  | none => notFound "Novel or page not found"
  | some novel =>
    let data := pageContext ctx novel.title PageId.novels
      (novelDetailToValue novel (some pageNum))
    Loom.Stencil.ActionM.renderWithLayout "app" "novels/show" data

-- Add new page
action novelAddPage "/novels/:id/pages" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => redirect s!"/novels/{id}"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    let existingPages := getPagesForNovel db novelEid
    let newPageNum := (existingPages.map (·.pageNumber)).foldl max 0 + 1
    let layout := ctx.paramD "layout" "full"
    let now ← novelGetNowMs
    -- Create the page
    let (pageEid, _) ← withNewEntityAudit! fun pageEid => do
      let novelPage : DbNovelPage := { id := pageEid.id.toNat, pageNumber := newPageNum, layoutTemplate := layout, novel := novelEid, createdAt := now }
      DbNovelPage.TxM.create pageEid novelPage
      audit "CREATE" "novel-page" pageEid.id.toNat [("page_number", toString newPageNum)]
    -- Create panels for the page
    createPanelsForPageM pageEid layout
    -- Update novel's updatedAt
    runAuditTx! do
      DbGraphicNovel.TxM.setUpdatedAt novelEid now
    let novelId := id
    let _ ← SSE.publishEvent "novels" "page-added" (jsonStr! { novelId, "pageNum" : newPageNum })
    redirect s!"/novels/{id}/page/{newPageNum}"

-- Delete page (POST for form compatibility)
action novelDeletePage "/novels/:id/page/:pageNum/delete" POST [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => redirect s!"/novels/{id}"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    match getPageByNumber db novelEid pageNum with
    | none => redirect s!"/novels/{id}"
    | some (pageEid, _) =>
      -- Delete all panels first
      let panelIds := db.findByAttrValue DbNovelPanel.attr_pageRef (.ref pageEid)
      for panelId in panelIds do
        runAuditTx! do
          DbNovelPanel.TxM.delete panelId
      -- Delete the page
      runAuditTx! do
        DbNovelPage.TxM.delete pageEid
        audit "DELETE" "novel-page" pageEid.id.toNat [("page_number", toString pageNum)]
      let novelId := id
      let _ ← SSE.publishEvent "novels" "page-deleted" (jsonStr! { novelId, pageNum })
      redirect s!"/novels/{id}"

-- Change page layout (POST for form compatibility)
action novelPageLayout "/novels/:id/page/:pageNum/layout" POST [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => redirect s!"/novels/{id}/page/{pageNum}"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    match getPageByNumber db novelEid pageNum with
    | none => redirect s!"/novels/{id}"
    | some (pageEid, _) =>
      let layout := ctx.paramD "layout" "full"
      if !validLayouts.contains layout then
        return ← redirect s!"/novels/{id}/page/{pageNum}"
      -- Delete existing panels
      let panelIds := db.findByAttrValue DbNovelPanel.attr_pageRef (.ref pageEid)
      for panelId in panelIds do
        runAuditTx! do
          DbNovelPanel.TxM.delete panelId
      -- Update layout
      runAuditTx! do
        DbNovelPage.TxM.setLayoutTemplate pageEid layout
        audit "UPDATE" "novel-page" pageEid.id.toNat [("layout", layout)]
      -- Create new panels
      createPanelsForPageM pageEid layout
      let novelId := id
      let _ ← SSE.publishEvent "novels" "page-layout-changed" (jsonStr! { novelId, pageNum, layout })
      redirect s!"/novels/{id}/page/{pageNum}"

-- Update panel caption (POST for form compatibility)
action novelPanelCaption "/novels/:id/page/:pageNum/panel/:idx/caption" POST [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) (idx : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => redirect s!"/novels/{id}/page/{pageNum}"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    match getPageByNumber db novelEid pageNum with
    | none => redirect s!"/novels/{id}/page/{pageNum}"
    | some (pageEid, _) =>
      match getPanelByIndex db pageEid idx with
      | none => redirect s!"/novels/{id}/page/{pageNum}"
      | some (panelEid, _) =>
        let caption := ctx.paramD "caption" ""
        runAuditTx! do
          DbNovelPanel.TxM.setCaption panelEid caption
        redirect s!"/novels/{id}/page/{pageNum}"

-- Update panel prompt (for regeneration)
action novelPanelPrompt "/novels/:id/page/:pageNum/panel/:idx/prompt" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) (idx : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => return ← html ""
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    match getPageByNumber db novelEid pageNum with
    | none => return ← html ""
    | some (pageEid, _) =>
      match getPanelByIndex db pageEid idx with
      | none => return ← html ""
      | some (panelEid, _) =>
        let prompt := ctx.paramD "prompt" ""
        runAuditTx! do
          DbNovelPanel.TxM.setPrompt panelEid prompt
        html ""

-- Generate image for panel using Oracle AI
action novelPanelGenerate "/novels/:id/page/:pageNum/panel/:idx/generate" POST [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) (idx : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => return ← badRequest "Database not available"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    match getPageByNumber db novelEid pageNum with
    | none => return ← notFound "Page not found"
    | some (pageEid, _) =>
      match getPanelByIndex db pageEid idx with
      | none => return ← notFound "Panel not found"
      | some (panelEid, _) =>
        let prompt := ctx.paramD "prompt" ""
        if prompt.isEmpty then
          return ← badRequest "Prompt is required"
        -- Update panel status to generating
        runAuditTx! do
          DbNovelPanel.TxM.setPrompt panelEid prompt
          DbNovelPanel.TxM.setGenerationStatus panelEid "generating"
        let novelId := id
        let panelIndex := idx
        let _ ← SSE.publishEvent "novels" "panel-generating" (jsonStr! { novelId, pageNum, panelIndex })
        -- Get API key and generate image
        let apiKey ← IO.getEnv "OPENROUTER_API_KEY"
        match apiKey with
        | none =>
          -- No API key - mark as error
          runAuditTx! do
            DbNovelPanel.TxM.setGenerationStatus panelEid "error"
          return ← badRequest "OPENROUTER_API_KEY not set"
        | some key =>
          -- Create Oracle client with image generation model
          let client := Oracle.Client.withModel key Oracle.Models.geminiFlashImage
          -- Generate a unique filename
          let timestamp ← IO.monoMsNow
          let filename := s!"panel_{id}_{pageNum}_{idx}_{timestamp}.png"
          let filepath := s!"data/uploads/{filename}"
          -- Generate and save image
          match ← client.generateImageToFile prompt filepath with
          | .ok _ =>
            -- Success - update panel with image path
            runAuditTx! do
              DbNovelPanel.TxM.setImagePath panelEid filename
              DbNovelPanel.TxM.setGenerationStatus panelEid "complete"
            let _ ← SSE.publishEvent "novels" "panel-generated" (jsonStr! { novelId, pageNum, panelIndex })
            -- Return the result partial
            let imageUrl := s!"/uploads/{filename}"
            let data : Stencil.Value := .object #[
              ("hasImage", .bool true),
              ("imageUrl", .string imageUrl),
              ("isGenerating", .bool false),
              ("isError", .bool false),
              ("prompt", .string prompt),
              ("caption", .string ""),
              ("novelId", .int (Int.ofNat id)),
              ("pageNumber", .int (Int.ofNat pageNum)),
              ("panelIndex", .int (Int.ofNat idx))
            ]
            Loom.Stencil.ActionM.render "novels/_panel-result" data
          | .error _ =>
            -- API error or no image in response
            runAuditTx! do
              DbNovelPanel.TxM.setGenerationStatus panelEid "error"
            let data : Stencil.Value := .object #[
              ("hasImage", .bool false),
              ("isGenerating", .bool false),
              ("isError", .bool true),
              ("prompt", .string prompt),
              ("novelId", .int (Int.ofNat id)),
              ("pageNumber", .int (Int.ofNat pageNum)),
              ("panelIndex", .int (Int.ofNat idx))
            ]
            Loom.Stencil.ActionM.render "novels/_panel-result" data

-- Get panel status (for polling)
view novelPanelStatus "/novels/:id/page/:pageNum/panel/:idx/status" [HomebaseApp.Middleware.authRequired] (id : Nat) (pageNum : Nat) (idx : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => return ← badRequest "Database not available"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    match getPageByNumber db novelEid pageNum with
    | none => return ← notFound "Page not found"
    | some (pageEid, _) =>
      match getPanelByIndex db pageEid idx with
      | none => return ← notFound "Panel not found"
      | some (_, panel) =>
        let imageUrl := if panel.imagePath.isEmpty then "" else s!"/uploads/{panel.imagePath}"
        let data : Stencil.Value := .object #[
          ("hasImage", .bool (!panel.imagePath.isEmpty)),
          ("imageUrl", .string imageUrl),
          ("isGenerating", .bool (panel.generationStatus == "generating")),
          ("isError", .bool (panel.generationStatus == "error")),
          ("prompt", .string panel.prompt),
          ("caption", .string panel.caption),
          ("novelId", .int (Int.ofNat id)),
          ("pageNumber", .int (Int.ofNat pageNum)),
          ("panelIndex", .int (Int.ofNat idx))
        ]
        Loom.Stencil.ActionM.render "novels/_panel-result" data

-- Update novel metadata (POST for form compatibility)
action novelUpdate "/novels/:id" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let now ← novelGetNowMs
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    if !title.isEmpty then
      DbGraphicNovel.TxM.setTitle eid title
    DbGraphicNovel.TxM.setDescription eid description
    DbGraphicNovel.TxM.setUpdatedAt eid now
    audit "UPDATE" "graphic-novel" id [("title", title)]
  let novelId := id
  let _ ← SSE.publishEvent "novels" "novel-updated" (jsonStr! { novelId, title })
  redirect s!"/novels/{id}"

-- Delete novel (POST for form compatibility)
action novelDelete "/novels/:id/delete" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match ctx.database with
  | none => redirect "/novels"
  | some db =>
    let novelEid : EntityId := ⟨id⟩
    -- Delete all panels and pages first
    let pageIds := db.findByAttrValue DbNovelPage.attr_novel (.ref novelEid)
    for pageId in pageIds do
      let panelIds := db.findByAttrValue DbNovelPanel.attr_pageRef (.ref pageId)
      for panelId in panelIds do
        -- TODO: Delete image files
        runAuditTx! do
          DbNovelPanel.TxM.delete panelId
      runAuditTx! do
        DbNovelPage.TxM.delete pageId
    -- Delete the novel
    runAuditTx! do
      DbGraphicNovel.TxM.delete novelEid
      audit "DELETE" "graphic-novel" id []
    let novelId := id
    let _ ← SSE.publishEvent "novels" "novel-deleted" (jsonStr! { novelId })
    redirect "/novels"

end HomebaseApp.Pages
