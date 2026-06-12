// Copyright 2025-present 650 Industries. All rights reserved.

#pragma once

// Decodes Fabric view props straight from their JavaScript values on the JavaScript thread
// during props parsing, instead of lowering them to `folly::dynamic` and decoding on the main
// thread (see the JSI view-props decoding design). On by default; comment out the `#define` to
// build without it (e.g. if a future React Native release breaks the `RawProps` member access in
// `ExpoRawPropsAccess.h`, which fails loudly at compile time).
#define EXPO_JSI_VIEW_PROPS 1
