/-
  HomebaseApp.Tests.Kanban - Tests for Kanban card move/reorder actions

  These tests verify correct column reference handling when moving cards.
-/

import Crucible
import Ledger
import HomebaseApp.Models
import HomebaseApp.Entities

namespace HomebaseApp.Tests.Kanban

open Crucible
open Ledger
open HomebaseApp.Models

testSuite "Kanban Card Operations"

/-! ## Card Column Reference Tests

These tests verify that when a card is moved between columns,
the old column reference is properly retracted so the card
doesn't appear in both columns.
-/

test "moving card removes it from old column" := do
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  -- Create column A and column B
  let tx1 : Transaction := [
    .add columnA DbColumn.attr_name (.string "To Do"),
    .add columnA DbColumn.attr_order (.int 0),
    .add columnB DbColumn.attr_name (.string "Done"),
    .add columnB DbColumn.attr_order (.int 1)
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Create card in column A
  let tx2 : Transaction := [
    .add card DbCard.attr_title (.string "Test Card"),
    .add card DbCard.attr_column (.ref columnA),
    .add card DbCard.attr_order (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Verify card is in column A
  let cardsInA := conn.db.findByAttrValue DbCard.attr_column (.ref columnA)
  cardsInA.length ≡ 1

  -- Move card to column B using generated setter (handles retraction automatically)
  let tx3 := DbCard.set_column conn.db card columnB ++
             DbCard.set_order conn.db card 0
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- Verify card is NO LONGER in column A
  let cardsInAAfter := conn.db.findByAttrValue DbCard.attr_column (.ref columnA)
  cardsInAAfter.length ≡ 0

test "moved card appears in new column" := do
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA DbColumn.attr_name (.string "To Do"),
    .add columnB DbColumn.attr_name (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  let tx2 : Transaction := [
    .add card DbCard.attr_title (.string "Test Card"),
    .add card DbCard.attr_column (.ref columnA),
    .add card DbCard.attr_order (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Move card to column B using generated setter
  let tx3 := DbCard.set_column conn.db card columnB
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- Verify card IS in column B
  let cardsInB := conn.db.findByAttrValue DbCard.attr_column (.ref columnB)
  cardsInB.length ≡ 1

test "deleting old column does not delete moved card" := do
  -- This is the bug we fixed: card moved to B, then A deleted, card survives
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA DbColumn.attr_name (.string "To Do"),
    .add columnB DbColumn.attr_name (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Create card in column A
  let tx2 : Transaction := [
    .add card DbCard.attr_title (.string "Test Card"),
    .add card DbCard.attr_column (.ref columnA),
    .add card DbCard.attr_order (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Move card to column B using generated setter
  let tx3 := DbCard.set_column conn.db card columnB
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- Delete column A (simulate deleteColumn action)
  -- First find cards in column A (should be none after move)
  let cardsInA := conn.db.findByAttrValue DbCard.attr_column (.ref columnA)
  ensure (cardsInA.length == 0) "No cards should be in column A after move"

  -- Delete column A attributes
  let tx4 : Transaction := [
    .retract columnA DbColumn.attr_name (.string "To Do")
  ]
  let .ok (conn, _) := conn.transact tx4 | throw <| IO.userError "Tx4 failed"

  -- Card should still exist in column B
  let cardsInB := conn.db.findByAttrValue DbCard.attr_column (.ref columnB)
  cardsInB.length ≡ 1

test "reordering within same column keeps card in column" := do
  let conn := Connection.create
  let (column, conn) := conn.allocEntityId
  let (card1, conn) := conn.allocEntityId
  let (card2, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add column DbColumn.attr_name (.string "To Do")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Create two cards in the column
  let tx2 : Transaction := [
    .add card1 DbCard.attr_title (.string "Card 1"),
    .add card1 DbCard.attr_column (.ref column),
    .add card1 DbCard.attr_order (.int 0),
    .add card2 DbCard.attr_title (.string "Card 2"),
    .add card2 DbCard.attr_column (.ref column),
    .add card2 DbCard.attr_order (.int 1)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Reorder cards using generated setters
  let tx3 := DbCard.set_order conn.db card1 1 ++
             DbCard.set_order conn.db card2 0
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- Both cards should still be in the column
  let cardsInColumn := conn.db.findByAttrValue DbCard.attr_column (.ref column)
  cardsInColumn.length ≡ 2

test "moving card updates getOne result" := do
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA DbColumn.attr_name (.string "To Do"),
    .add columnB DbColumn.attr_name (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  let tx2 : Transaction := [
    .add card DbCard.attr_title (.string "Test Card"),
    .add card DbCard.attr_column (.ref columnA)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Verify getOne returns column A
  conn.db.getOne card DbCard.attr_column ≡ some (.ref columnA)

  -- Move card to column B using generated setter
  let tx3 := DbCard.set_column conn.db card columnB
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- Verify getOne now returns column B
  conn.db.getOne card DbCard.attr_column ≡ some (.ref columnB)

/-! ## Bug Regression Tests -/

test "BUG: without retraction, card appears in both columns" := do
  -- This demonstrates why retraction is necessary
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA DbColumn.attr_name (.string "To Do"),
    .add columnB DbColumn.attr_name (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  let tx2 : Transaction := [
    .add card DbCard.attr_title (.string "Test Card"),
    .add card DbCard.attr_column (.ref columnA)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Move WITHOUT retraction (the old buggy way)
  let tx3 : Transaction := [
    .add card DbCard.attr_column (.ref columnB)
  ]
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- BUG: Card still appears in column A (the old value is still in AVET index)
  let cardsInA := conn.db.findByAttrValue DbCard.attr_column (.ref columnA)
  -- This is the bug behavior - card is found in old column
  ensure (cardsInA.length == 1) "Without retraction, card appears in old column"

  -- And also in column B
  let cardsInB := conn.db.findByAttrValue DbCard.attr_column (.ref columnB)
  ensure (cardsInB.length == 1) "Card also appears in new column"

/-! ## Generated Setter Tests -/

test "set_column handles no-op when value unchanged" := do
  let conn := Connection.create
  let (column, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add card DbCard.attr_title (.string "Test Card"),
    .add card DbCard.attr_column (.ref column)
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Setting to same value should produce no ops
  let ops := DbCard.set_column conn.db card column
  ops.length ≡ 0

test "set_order retracts old value" := do
  let conn := Connection.create
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add card DbCard.attr_order (.int 5)
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Setting to new value should produce retract + add
  let ops := DbCard.set_order conn.db card 10
  ops.length ≡ 2

  -- Execute the ops
  let .ok (conn, _) := conn.transact ops | throw <| IO.userError "Tx2 failed"

  -- Should only have one value now
  let values := conn.db.get card DbCard.attr_order
  values.length ≡ 1
  conn.db.getOne card DbCard.attr_order ≡ some (.int 10)

end HomebaseApp.Tests.Kanban
