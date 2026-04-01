/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "chrome/browser/metrics/chrome_metrics_service_client.h"

#define ChromeMetricsServiceClient ChromeMetricsServiceClient_ChromiumImpl
#include <chrome/browser/metrics/chrome_metrics_service_client.cc>
#undef ChromeMetricsServiceClient
