#!/usr/bin/env bats
# Flag handling: anything but --calendar [YYYY] or no flag exits 2 with usage.
load helpers

@test "--holidays (the old flag) is rejected" { run at "$NOW" bash "$SL" --holidays 2027 </dev/null; assert_status 2; assert_has "usage:"; }
@test "--calendar with a bad year is rejected" { run at "$NOW" bash "$SL" --calendar 20x; assert_status 2; assert_has "usage:"; }
@test "--calendar with an extra argument is rejected" { run at "$NOW" bash "$SL" --calendar 2026 extra; assert_status 2; assert_has "usage:"; }
@test "a stray argument is rejected" { run at "$NOW" bash "$SL" render-me </dev/null; assert_status 2; assert_has "usage:"; }
@test "--calendar exits 0" { run at "$NOW" bash "$SL" --calendar 2026; assert_status 0; assert_has "workdays:"; }
