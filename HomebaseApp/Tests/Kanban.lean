/-
  HomebaseApp.Tests.Kanban - Tests for Kanban card move/reorder actions

  These tests verify correct column reference handling when moving cards.
-/

import Crucible
import Ledger
import HomebaseApp.Models

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
    .add columnA columnName (.string "To Do"),
    .add columnA columnOrder (.int 0),
    .add columnB columnName (.string "Done"),
    .add columnB columnOrder (.int 1)
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Create card in column A
  let tx2 : Transaction := [
    .add card cardTitle (.string "Test Card"),
    .add card cardColumn (.ref columnA),
    .add card cardOrder (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Verify card is in column A
  let cardsInA := conn.db.findByAttrValue cardColumn (.ref columnA)
  cardsInA.length ≡ 1

  -- Move card to column B (with proper retraction)
  let oldColumnRef := conn.db.getOne card cardColumn
  match oldColumnRef with
  | none => throw <| IO.userError "Card not found"
  | some oldRef =>
    let tx3 : Transaction := [
      .retract card cardColumn oldRef,
      .add card cardColumn (.ref columnB),
      .add card cardOrder (.int 0)
    ]
    let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

    -- Verify card is NO LONGER in column A
    let cardsInAAfter := conn.db.findByAttrValue cardColumn (.ref columnA)
    cardsInAAfter.length ≡ 0

test "moved card appears in new column" := do
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA columnName (.string "To Do"),
    .add columnB columnName (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  let tx2 : Transaction := [
    .add card cardTitle (.string "Test Card"),
    .add card cardColumn (.ref columnA),
    .add card cardOrder (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Move card to column B (with proper retraction)
  match conn.db.getOne card cardColumn with
  | none => throw <| IO.userError "Card not found"
  | some oldRef =>
    let tx3 : Transaction := [
      .retract card cardColumn oldRef,
      .add card cardColumn (.ref columnB)
    ]
    let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

    -- Verify card IS in column B
    let cardsInB := conn.db.findByAttrValue cardColumn (.ref columnB)
    cardsInB.length ≡ 1

test "deleting old column does not delete moved card" := do
  -- This is the bug we fixed: card moved to B, then A deleted, card survives
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA columnName (.string "To Do"),
    .add columnB columnName (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Create card in column A
  let tx2 : Transaction := [
    .add card cardTitle (.string "Test Card"),
    .add card cardColumn (.ref columnA),
    .add card cardOrder (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Move card to column B (with proper retraction)
  match conn.db.getOne card cardColumn with
  | none => throw <| IO.userError "Card not found"
  | some oldRef =>
    let tx3 : Transaction := [
      .retract card cardColumn oldRef,
      .add card cardColumn (.ref columnB)
    ]
    let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

    -- Delete column A (simulate deleteColumn action)
    -- First find cards in column A (should be none after move)
    let cardsInA := conn.db.findByAttrValue cardColumn (.ref columnA)
    ensure (cardsInA.length == 0) "No cards should be in column A after move"

    -- Delete column A attributes
    let tx4 : Transaction := [
      .retract columnA columnName (.string "To Do")
    ]
    let .ok (conn, _) := conn.transact tx4 | throw <| IO.userError "Tx4 failed"

    -- Card should still exist in column B
    let cardsInB := conn.db.findByAttrValue cardColumn (.ref columnB)
    cardsInB.length ≡ 1

test "reordering within same column keeps card in column" := do
  let conn := Connection.create
  let (column, conn) := conn.allocEntityId
  let (card1, conn) := conn.allocEntityId
  let (card2, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add column columnName (.string "To Do")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  -- Create two cards in the column
  let tx2 : Transaction := [
    .add card1 cardTitle (.string "Card 1"),
    .add card1 cardColumn (.ref column),
    .add card1 cardOrder (.int 0),
    .add card2 cardTitle (.string "Card 2"),
    .add card2 cardColumn (.ref column),
    .add card2 cardOrder (.int 1)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Reorder card1 (move to position 1) - same column, no retract needed
  let tx3 : Transaction := [
    .add card1 cardOrder (.int 1),
    .add card2 cardOrder (.int 0)
  ]
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- Both cards should still be in the column
  let cardsInColumn := conn.db.findByAttrValue cardColumn (.ref column)
  cardsInColumn.length ≡ 2

test "moving card updates getOne result" := do
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA columnName (.string "To Do"),
    .add columnB columnName (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  let tx2 : Transaction := [
    .add card cardTitle (.string "Test Card"),
    .add card cardColumn (.ref columnA)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Verify getOne returns column A
  conn.db.getOne card cardColumn ≡ some (.ref columnA)

  -- Move card to column B (with proper retraction)
  match conn.db.getOne card cardColumn with
  | none => throw <| IO.userError "Card not found"
  | some oldRef =>
    let tx3 : Transaction := [
      .retract card cardColumn oldRef,
      .add card cardColumn (.ref columnB)
    ]
    let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

    -- Verify getOne now returns column B
    conn.db.getOne card cardColumn ≡ some (.ref columnB)

/-! ## Bug Regression Tests -/

test "BUG: without retraction, card appears in both columns" := do
  -- This demonstrates why retraction is necessary
  let conn := Connection.create
  let (columnA, conn) := conn.allocEntityId
  let (columnB, conn) := conn.allocEntityId
  let (card, conn) := conn.allocEntityId

  let tx1 : Transaction := [
    .add columnA columnName (.string "To Do"),
    .add columnB columnName (.string "Done")
  ]
  let .ok (conn, _) := conn.transact tx1 | throw <| IO.userError "Tx1 failed"

  let tx2 : Transaction := [
    .add card cardTitle (.string "Test Card"),
    .add card cardColumn (.ref columnA)
  ]
  let .ok (conn, _) := conn.transact tx2 | throw <| IO.userError "Tx2 failed"

  -- Move WITHOUT retraction (the old buggy way)
  let tx3 : Transaction := [
    .add card cardColumn (.ref columnB)
  ]
  let .ok (conn, _) := conn.transact tx3 | throw <| IO.userError "Tx3 failed"

  -- BUG: Card still appears in column A (the old value is still in AVET index)
  let cardsInA := conn.db.findByAttrValue cardColumn (.ref columnA)
  -- This is the bug behavior - card is found in old column
  ensure (cardsInA.length == 1) "Without retraction, card appears in old column"

  -- And also in column B
  let cardsInB := conn.db.findByAttrValue cardColumn (.ref columnB)
  ensure (cardsInB.length == 1) "Card also appears in new column"

#generate_tests

end HomebaseApp.Tests.Kanban
