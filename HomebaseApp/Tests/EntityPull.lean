/-
  Tests for DbCard/DbColumn pull with existing data formats
-/
import Crucible
import Ledger
import HomebaseApp.Models
import HomebaseApp.Entities

open Crucible
open Ledger
open HomebaseApp.Models

testSuite "Entity Pull Compatibility"

-- Test that DbCard.pull works with manually created data (old format)
test "DbCard.pull with manual TxOps" := do
  let db := Db.empty
  let (colId, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  -- Create column using old manual style
  let colTx : Transaction := [
    TxOp.add colId columnName (.string "Backlog"),
    TxOp.add colId columnOrder (.int 0)
  ]
  let .ok (db, _) := db.transact colTx | throw <| IO.userError "Column tx failed"

  -- Create card using old manual style (like the existing data)
  let cardTx : Transaction := [
    TxOp.add cardId cardTitle (.string "Test Card"),
    TxOp.add cardId cardDescription (.string "Description"),
    TxOp.add cardId cardColumn (.ref colId),
    TxOp.add cardId cardOrder (.int 0),
    TxOp.add cardId cardLabels (.string "")
  ]
  let .ok (db, _) := db.transact cardTx | throw <| IO.userError "Card tx failed"

  -- Now try to pull using generated DbCard.pull
  match DbCard.pull db cardId with
  | some card =>
    card.title ≡ "Test Card"
    card.description ≡ "Description"
    card.labels ≡ ""
    card.order ≡ 0
    ensure (card.column == colId) "Column should match"
  | none =>
    throw <| IO.userError "DbCard.pull returned none!"

-- Test attribute name consistency
test "Attribute names match" := do
  -- Verify generated attributes match manual definitions
  DbCard.attr_title.name ≡ cardTitle.name
  DbCard.attr_description.name ≡ cardDescription.name
  DbCard.attr_column.name ≡ cardColumn.name
  DbCard.attr_order.name ≡ cardOrder.name
  DbCard.attr_labels.name ≡ cardLabels.name

  DbColumn.attr_name.name ≡ columnName.name
  DbColumn.attr_order.name ≡ columnOrder.name

-- Test that DbCard.pull works with createOps (round-trip)
test "DbCard createOps round-trip" := do
  let db := Db.empty
  let (colId, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  -- Create column
  let colTx : Transaction := [
    TxOp.add colId columnName (.string "Todo"),
    TxOp.add colId columnOrder (.int 0)
  ]
  let .ok (db, _) := db.transact colTx | throw <| IO.userError "Column tx failed"

  -- Create card using generated createOps
  let dbCard : DbCard := {
    id := cardId.id.toNat
    title := "New Card"
    description := "Desc"
    labels := "bug"
    order := 1
    column := colId
  }
  let cardTx := DbCard.createOps cardId dbCard
  let .ok (db, _) := db.transact cardTx | throw <| IO.userError "Card tx failed"

  -- Pull it back
  match DbCard.pull db cardId with
  | some pulled =>
    pulled.title ≡ "New Card"
    pulled.description ≡ "Desc"
    pulled.labels ≡ "bug"
    pulled.order ≡ 1
    ensure (pulled.column == colId) "Column should match"
  | none =>
    throw <| IO.userError "DbCard.pull returned none!"

-- Test findByAttrValue with generated attribute
test "findByAttrValue with DbCard.attr_column" := do
  let db := Db.empty
  let (colId, db) := db.allocEntityId
  let (card1Id, db) := db.allocEntityId
  let (card2Id, db) := db.allocEntityId

  -- Create two cards in the column
  let tx : Transaction := [
    TxOp.add card1Id cardTitle (.string "Card 1"),
    TxOp.add card1Id cardDescription (.string ""),
    TxOp.add card1Id cardColumn (.ref colId),
    TxOp.add card1Id cardOrder (.int 0),
    TxOp.add card1Id cardLabels (.string ""),
    TxOp.add card2Id cardTitle (.string "Card 2"),
    TxOp.add card2Id cardDescription (.string ""),
    TxOp.add card2Id cardColumn (.ref colId),
    TxOp.add card2Id cardOrder (.int 1),
    TxOp.add card2Id cardLabels (.string "")
  ]
  let .ok (db, _) := db.transact tx | throw <| IO.userError "Tx failed"

  -- Find cards using generated attribute
  let foundWithGenerated := db.findByAttrValue DbCard.attr_column (.ref colId)
  -- Find cards using manual attribute
  let foundWithManual := db.findByAttrValue cardColumn (.ref colId)

  foundWithGenerated.length ≡ 2
  foundWithManual.length ≡ 2

-- Test Pull API directly to see what it returns
test "Pull API raw result" := do
  let db := Db.empty
  let (colId, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  let tx : Transaction := [
    TxOp.add cardId cardTitle (.string "Test"),
    TxOp.add cardId cardDescription (.string "Desc"),
    TxOp.add cardId cardColumn (.ref colId),
    TxOp.add cardId cardOrder (.int 5),
    TxOp.add cardId cardLabels (.string "urgent")
  ]
  let .ok (db, _) := db.transact tx | throw <| IO.userError "Tx failed"

  -- Use the generated pullSpec
  let result := Pull.pull db cardId DbCard.pullSpec

  -- Check each field
  match result.get? DbCard.attr_title with
  | some (.scalar (.string s)) => s ≡ "Test"
  | other => throw <| IO.userError s!"Expected scalar string for title, got {repr other}"

  match result.get? DbCard.attr_order with
  | some (.scalar (.int n)) => n ≡ 5
  | other => throw <| IO.userError s!"Expected scalar int for order, got {repr other}"

  match result.get? DbCard.attr_column with
  | some (.ref e) => ensure (e == colId) "Column ref should match"
  | some (.scalar (.ref e)) => ensure (e == colId) "Column ref should match (scalar)"
  | other => throw <| IO.userError s!"Expected ref for column, got {repr other}"

-- Test with multiple values for same attribute (simulating move without retraction bug)
test "DbCard.pull with multiple column values (move bug)" := do
  let db := Db.empty
  let (col1Id, db) := db.allocEntityId
  let (col2Id, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  -- Create card in column 1
  let tx1 : Transaction := [
    TxOp.add cardId cardTitle (.string "Card"),
    TxOp.add cardId cardDescription (.string ""),
    TxOp.add cardId cardColumn (.ref col1Id),
    TxOp.add cardId cardOrder (.int 0),
    TxOp.add cardId cardLabels (.string "")
  ]
  let .ok (db, _) := db.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Move to column 2 WITHOUT retracting old column (this is the bug pattern in existing data)
  let tx2 : Transaction := [
    TxOp.add cardId cardColumn (.ref col2Id),
    TxOp.add cardId cardOrder (.int 0)
  ]
  let .ok (db, _) := db.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Check raw values - should have TWO column refs now
  let columnValues := db.get cardId cardColumn
  IO.println s!"Column values count: {columnValues.length}"
  for v in columnValues do
    IO.println s!"  Column value: {repr v}"

  -- Check what getOne returns (should be most recent)
  match db.getOne cardId cardColumn with
  | some v => IO.println s!"getOne column: {repr v}"
  | none => IO.println "getOne column: none"

  -- Check what Pull API returns
  let pullResult := Pull.pull db cardId DbCard.pullSpec
  match pullResult.get? DbCard.attr_column with
  | some pv => IO.println s!"Pull column: {repr pv}"
  | none => IO.println "Pull column: none"

  -- Try DbCard.pull - this is what might fail
  match DbCard.pull db cardId with
  | some card =>
    IO.println s!"DbCard.pull succeeded: column={card.column.id}"
  | none =>
    IO.println "DbCard.pull FAILED - this is the bug!"
    throw <| IO.userError "DbCard.pull returned none when multiple column values exist!"

#generate_tests
