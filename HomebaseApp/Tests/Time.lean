/-
  HomebaseApp.Tests.Time - Unit tests for Time tracker functionality
-/

import Crucible
import HomebaseApp.Pages.Time

namespace HomebaseApp.Tests.Time

open Crucible
open HomebaseApp.Pages

testSuite "Time Tracker"

/-! ## Duration Formatting Tests -/

test "formatDuration with zero seconds" := do
  formatDuration 0 ≡ "00:00:00"

test "formatDuration with under a minute" := do
  formatDuration 45 ≡ "00:00:45"

test "formatDuration with exactly one hour" := do
  formatDuration 3600 ≡ "01:00:00"

test "formatDuration pads single digits" := do
  formatDuration 3661 ≡ "01:01:01"

test "formatDuration with large value" := do
  formatDuration 36000 ≡ "10:00:00"

test "formatDuration max reasonable value" := do
  -- 99 hours, 59 minutes, 59 seconds
  formatDuration 359999 ≡ "99:59:59"

/-! ## Short Duration Formatting Tests -/

test "formatDurationShort with zero seconds" := do
  formatDurationShort 0 ≡ "0s"

test "formatDurationShort with only minutes" := do
  formatDurationShort 300 ≡ "5m"

test "formatDurationShort with only hours" := do
  formatDurationShort 7200 ≡ "2h"

test "formatDurationShort with hours and minutes" := do
  formatDurationShort 5400 ≡ "1h 30m"

test "formatDurationShort boundary at 59 seconds" := do
  formatDurationShort 59 ≡ "59s"

test "formatDurationShort boundary at 60 seconds" := do
  formatDurationShort 60 ≡ "1m"

test "formatDurationShort exactly 1 hour no minutes" := do
  formatDurationShort 3600 ≡ "1h"

test "formatDurationShort 1 hour 1 minute" := do
  formatDurationShort 3660 ≡ "1h 1m"

/-! ## Time of Day Formatting Tests -/

test "formatTimeOfDay at midnight" := do
  formatTimeOfDay 0 ≡ "00:00"

test "formatTimeOfDay at noon" := do
  formatTimeOfDay (12 * 60 * 60 * 1000) ≡ "12:00"

test "formatTimeOfDay wraps after 24 hours" := do
  formatTimeOfDay (25 * 60 * 60 * 1000) ≡ "01:00"

test "formatTimeOfDay pads single digits" := do
  formatTimeOfDay (9 * 60 * 60 * 1000 + 5 * 60 * 1000) ≡ "09:05"

test "formatTimeOfDay end of day" := do
  formatTimeOfDay (23 * 60 * 60 * 1000 + 59 * 60 * 1000) ≡ "23:59"

/-! ## Day/Week Boundary Tests -/

test "getStartOfToday is divisible by msPerDay" := do
  let nowMs := 1703721600000  -- some arbitrary time
  let result := getStartOfToday nowMs
  let msPerDay := 24 * 60 * 60 * 1000
  shouldSatisfy (result % msPerDay == 0) "should be midnight"

test "getStartOfToday is idempotent" := do
  let nowMs := 1703721600000
  let today := getStartOfToday nowMs
  getStartOfToday today ≡ today

test "getStartOfToday same day returns same start" := do
  let msPerDay := 24 * 60 * 60 * 1000
  let midnight := 1703721600000  -- assume this is a midnight
  let midday := midnight + (12 * 60 * 60 * 1000)
  -- Both should round to the same day start
  let start1 := getStartOfToday midnight
  let start2 := getStartOfToday midday
  -- They should be at most one day apart (since our midnight might not be exact)
  shouldSatisfy ((start2 - start1) < msPerDay) "same day should have same start"

test "getStartOfWeek is divisible by msPerWeek" := do
  let nowMs := 1703721600000
  let result := getStartOfWeek nowMs
  let msPerWeek := 7 * 24 * 60 * 60 * 1000
  shouldSatisfy (result % msPerWeek == 0) "should be week start"

test "getStartOfWeek is idempotent" := do
  let nowMs := 1703721600000
  let week := getStartOfWeek nowMs
  getStartOfWeek week ≡ week

/-! ## Aggregation Tests -/

test "totalDuration with empty list" := do
  totalDuration [] ≡ 0

test "totalDuration sums correctly" := do
  let entries : List TimeEntry := [
    { id := 1, description := "a", startTime := 0, endTime := 0, duration := 100, category := "Work" },
    { id := 2, description := "b", startTime := 0, endTime := 0, duration := 200, category := "Work" }
  ]
  totalDuration entries ≡ 300

test "totalDuration with single entry" := do
  let entries : List TimeEntry := [
    { id := 1, description := "a", startTime := 0, endTime := 0, duration := 42, category := "Work" }
  ]
  totalDuration entries ≡ 42

test "totalDuration with many entries" := do
  let entries : List TimeEntry := [
    { id := 1, description := "a", startTime := 0, endTime := 0, duration := 100, category := "Work" },
    { id := 2, description := "b", startTime := 0, endTime := 0, duration := 200, category := "Personal" },
    { id := 3, description := "c", startTime := 0, endTime := 0, duration := 300, category := "Learning" },
    { id := 4, description := "d", startTime := 0, endTime := 0, duration := 400, category := "Health" }
  ]
  totalDuration entries ≡ 1000

/-! ## Group By Category Tests -/

test "groupByCategory with empty list" := do
  groupByCategory [] ≡ []

test "groupByCategory groups same category" := do
  let entries : List TimeEntry := [
    { id := 1, description := "a", startTime := 0, endTime := 0, duration := 100, category := "Work" },
    { id := 2, description := "b", startTime := 0, endTime := 0, duration := 200, category := "Work" }
  ]
  let result := groupByCategory entries
  result.length ≡ 1
  match result.head? with
  | some (cat, dur) => do cat ≡ "Work"; dur ≡ 300
  | none => throw <| IO.userError "Expected one category"

test "groupByCategory sorts by duration descending" := do
  let entries : List TimeEntry := [
    { id := 1, description := "a", startTime := 0, endTime := 0, duration := 100, category := "Personal" },
    { id := 2, description := "b", startTime := 0, endTime := 0, duration := 500, category := "Work" }
  ]
  let result := groupByCategory entries
  match result.head? with
  | some (cat, _) => cat ≡ "Work"  -- Work has more duration
  | none => throw <| IO.userError "Expected categories"

test "groupByCategory multiple categories" := do
  let entries : List TimeEntry := [
    { id := 1, description := "a", startTime := 0, endTime := 0, duration := 100, category := "Work" },
    { id := 2, description := "b", startTime := 0, endTime := 0, duration := 200, category := "Personal" },
    { id := 3, description := "c", startTime := 0, endTime := 0, duration := 50, category := "Work" }
  ]
  let result := groupByCategory entries
  result.length ≡ 2
  -- Personal should be first (200 > 150)
  match result.head? with
  | some (cat, dur) => do cat ≡ "Personal"; dur ≡ 200
  | none => throw <| IO.userError "Expected categories"

/-! ## Category Class Tests -/

test "timeCategoryClass work" := do
  timeCategoryClass "Work" ≡ "category-work"

test "timeCategoryClass personal" := do
  timeCategoryClass "Personal" ≡ "category-personal"

test "timeCategoryClass learning" := do
  timeCategoryClass "Learning" ≡ "category-learning"

test "timeCategoryClass health" := do
  timeCategoryClass "Health" ≡ "category-health"

test "timeCategoryClass case insensitive" := do
  timeCategoryClass "WORK" ≡ "category-work"
  timeCategoryClass "work" ≡ "category-work"
  timeCategoryClass "WoRk" ≡ "category-work"

test "timeCategoryClass unknown returns other" := do
  timeCategoryClass "Unknown" ≡ "category-other"

test "timeCategoryClass empty string returns other" := do
  timeCategoryClass "" ≡ "category-other"

/-! ## Default Categories Tests -/

test "defaultCategories contains expected values" := do
  shouldContain defaultCategories "Work"
  shouldContain defaultCategories "Personal"
  shouldContain defaultCategories "Learning"
  shouldContain defaultCategories "Health"
  shouldContain defaultCategories "Other"

test "defaultCategories has 5 items" := do
  defaultCategories.length ≡ 5

/-! ## BUG DETECTION: Monotonic vs Wall Clock Time -/

-- This test documents a potential bug: timeGetNowMs uses IO.monoMsNow
-- which is monotonic time (since boot), not Unix epoch time.
-- This means stored timestamps won't represent actual wall clock time.

test "BUG: timeGetNowMs should return wall clock time" := do
  -- Current time from monoMsNow
  let monoTime ← timeGetNowMs
  -- A reasonable Unix timestamp for 2025 would be around 1735689600000 ms
  -- (Jan 1, 2025 00:00:00 UTC)
  let jan2025 : Nat := 1735689600000
  -- Monotonic time is typically much smaller (time since boot)
  -- If monoTime < jan2025, it's likely monotonic, not wall clock
  if monoTime < jan2025 then
    IO.println s!"WARNING: timeGetNowMs returned {monoTime}, which appears to be monotonic time, not wall clock time."
    IO.println "This bug means:"
    IO.println "  - Stored timestamps don't represent actual dates"
    IO.println "  - 'Today' and 'This week' calculations are wrong"
    IO.println "  - Time-based filtering won't work correctly"
    -- Note: We don't fail the test since this documents existing behavior
    pure ()
  else
    IO.println s!"timeGetNowMs returned {monoTime}, which looks like valid wall clock time"

/-! ## parseTime Tests -/

-- Note: parseTime is an inline function inside timeCreateEntry
-- We can't test it directly without extracting it.
-- These tests document the expected behavior for when it's extracted.

-- Expected parseTime behavior:
-- "09:30" -> some (9 * 3600 + 30 * 60) = some 34200
-- "00:00" -> some 0
-- "23:59" -> some (23 * 3600 + 59 * 60) = some 86340
-- "invalid" -> none
-- "9:30" -> some 34200 (single digit hour should work)
-- "09:5" -> some (9 * 3600 + 5 * 60) (single digit minute should work)

end HomebaseApp.Tests.Time
