// Copyright 2022-present 650 Industries. All rights reserved.

#pragma once

#ifdef __cplusplus

#include <memory>

#include <folly/dynamic.h>
#include <react/renderer/components/view/ViewProps.h>
#include <react/renderer/core/PropsParserContext.h>

#include "ExpoViewPropsConfig.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

// macOS ViewProps doesn't support filterObjectKeys parameter
#if defined(TARGET_OS_OSX) && TARGET_OS_OSX
#define EXPO_VIEW_PROPS_SUPPORTS_FILTER_OBJECT_KEYS 0
#else
#define EXPO_VIEW_PROPS_SUPPORTS_FILTER_OBJECT_KEYS 1
#endif

namespace expo {

class ExpoViewProps : public facebook::react::ViewProps {
public:
  ExpoViewProps() = default;

  ExpoViewProps(
    const facebook::react::PropsParserContext &context,
    const ExpoViewProps &sourceProps,
    const facebook::react::RawProps &rawProps,
    const std::function<bool(const std::string &)> &filterObjectKeys = nullptr
  );

#pragma mark - Props

  /**
   Typed prop read by `ExpoViewShadowNode` during layout to decide view flattening. Parsed as a
   first-class `bool` (via `convertRawProp`) rather than looked up in `propsMap`, so the shadow
   node doesn't depend on `propsMap` being materialized.
   */
  bool disableForceFlatten = false;

  /**
   A map with props stored as `folly::dynamic` objects.

   `mutable` because, under JSI decoding, it is populated by the component descriptor's
   `cloneProps` after the props object is already held as `const` (only for the views that
   don't decode straight from JSI). Without JSI decoding it is built in the constructor.
   */
  mutable std::unordered_map<std::string, folly::dynamic> propsMap;

#ifdef EXPO_JSI_VIEW_PROPS
  /**
   View props that were decoded straight from their JavaScript values on the JavaScript
   thread during props parsing (see the JSI view-props decoding design). Type-erased to a
   `void` shared pointer that retains a Swift `EXDecodedViewProps` object; the deleter
   releases it via `CFBridgingRelease`. Set by the component descriptor's `cloneProps`,
   read on the main thread in `finalizeUpdates:`.

   `shared_ptr` so the (copyable, value-semantic) props object can be cloned by Fabric while
   the decoded container is released exactly once. `mutable` because it is filled in by the
   component descriptor's `cloneProps` after the props object is already held as `const`.
   */
  mutable std::shared_ptr<void> decodedProps;
#endif // EXPO_JSI_VIEW_PROPS
};

/**
 Borrows the props map from the source props and applies the update given in the raw props.
 */
std::unordered_map<std::string, folly::dynamic> propsMapFromProps(
  const ExpoViewProps &sourceProps,
  const facebook::react::RawProps &rawProps
);

} // namespace expo

#endif // __cplusplus
