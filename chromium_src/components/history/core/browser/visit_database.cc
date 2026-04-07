/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at http://mozilla.org/MPL/2.0/. */

#include <components/history/core/browser/visit_database.cc>

namespace history {

bool VisitDatabase::GetKnownToSyncCount(int* count) {
  sql::Statement statement(
      GetDB().GetCachedStatement(SQL_FROM_HERE,
                                 "SELECT COUNT(*) "
                                 "FROM visits "
                                 "WHERE is_known_to_sync == TRUE"));

  *count = 0;
  if (statement.Step()) {
    *count = statement.ColumnInt(0);
  }
  return true;
}

}  // namespace history
