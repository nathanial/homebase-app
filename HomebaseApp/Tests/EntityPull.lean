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

  -- Create column using TxOps
  let colTx : Transaction := [
    TxOp.add colId DbColumn.attr_name (.string "Backlog"),
    TxOp.add colId DbColumn.attr_order (.int 0)
  ]
  let .ok (db, _) := db.transact colTx | throw <| IO.userError "Column tx failed"

  -- Create card using TxOps
  let cardTx : Transaction := [
    TxOp.add cardId DbCard.attr_title (.string "Test Card"),
    TxOp.add cardId DbCard.attr_description (.string "Description"),
    TxOp.add cardId DbCard.attr_column (.ref colId),
    TxOp.add cardId DbCard.attr_order (.int 0),
    TxOp.add cardId DbCard.attr_labels (.string "")
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
test "Attribute names match expected format" := do
  -- Verify generated attributes have the expected names
  DbCard.attr_title.name ≡ ":card/title"
  DbCard.attr_description.name ≡ ":card/description"
  DbCard.attr_column.name ≡ ":card/column"
  DbCard.attr_order.name ≡ ":card/order"
  DbCard.attr_labels.name ≡ ":card/labels"

  DbColumn.attr_name.name ≡ ":column/name"
  DbColumn.attr_order.name ≡ ":column/order"

-- Test that DbCard.pull works with createOps (round-trip)
test "DbCard createOps round-trip" := do
  let db := Db.empty
  let (boardId, db) := db.allocEntityId
  let (colId, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  -- Create column using generated createOps
  let dbCol : DbColumn := { id := colId.id.toNat, name := "Todo", order := 0, board := boardId }
  let colTx := DbColumn.createOps colId dbCol
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

  -- Create two cards in the column using generated createOps
  let card1 : DbCard := { id := card1Id.id.toNat, title := "Card 1", description := "", labels := "", order := 0, column := colId }
  let card2 : DbCard := { id := card2Id.id.toNat, title := "Card 2", description := "", labels := "", order := 1, column := colId }
  let tx := DbCard.createOps card1Id card1 ++ DbCard.createOps card2Id card2
  let .ok (db, _) := db.transact tx | throw <| IO.userError "Tx failed"

  -- Find cards using generated attribute
  let foundCards := db.findByAttrValue DbCard.attr_column (.ref colId)
  foundCards.length ≡ 2

-- Test Pull API directly to see what it returns
test "Pull API raw result" := do
  let db := Db.empty
  let (colId, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  let tx : Transaction := [
    TxOp.add cardId DbCard.attr_title (.string "Test"),
    TxOp.add cardId DbCard.attr_description (.string "Desc"),
    TxOp.add cardId DbCard.attr_column (.ref colId),
    TxOp.add cardId DbCard.attr_order (.int 5),
    TxOp.add cardId DbCard.attr_labels (.string "urgent")
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
-- This test verifies that pull still works even if old data has multiple values
test "DbCard.pull with multiple column values (move bug)" := do
  let db := Db.empty
  let (col1Id, db) := db.allocEntityId
  let (col2Id, db) := db.allocEntityId
  let (cardId, db) := db.allocEntityId

  -- Create card in column 1
  let tx1 : Transaction := [
    TxOp.add cardId DbCard.attr_title (.string "Card"),
    TxOp.add cardId DbCard.attr_description (.string ""),
    TxOp.add cardId DbCard.attr_column (.ref col1Id),
    TxOp.add cardId DbCard.attr_order (.int 0),
    TxOp.add cardId DbCard.attr_labels (.string "")
  ]
  let .ok (db, _) := db.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Move to column 2 WITHOUT retracting old column (this is the bug pattern in existing data)
  let tx2 : Transaction := [
    TxOp.add cardId DbCard.attr_column (.ref col2Id),
    TxOp.add cardId DbCard.attr_order (.int 0)
  ]
  let .ok (db, _) := db.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Check raw values - should have TWO column refs now
  let columnValues := db.get cardId DbCard.attr_column
  IO.println s!"Column values count: {columnValues.length}"
  for v in columnValues do
    IO.println s!"  Column value: {repr v}"

  -- Check what getOne returns (should be most recent)
  match db.getOne cardId DbCard.attr_column with
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
