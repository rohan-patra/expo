// Copyright 2022-present 650 Industries. All rights reserved.

#include "ExpoViewProps.h"
#include <react/renderer/core/propsConversions.h>
#include <react/renderer/components/view/ViewProps.h>

namespace react = facebook::react;

namespace expo {

std::unordered_map<std::string, folly::dynamic> propsMapFromProps(
  const ExpoViewProps &sourceProps,
  const react::RawProps &rawProps
) {
  std::unordered_map<std::string, folly::dynamic> propsMap = sourceProps.propsMap;

  // Iterate over values in the raw props object.
  // Note that it contains only updated props.
  const auto &dynamicRawProps = static_cast<folly::dynamic>(rawProps);
  for (const auto &propsPair: dynamicRawProps.items()) {
    const auto &propName = propsPair.first.getString();
    propsMap[propName] = static_cast<folly::dynamic>(propsPair.second);
  }

  return propsMap;
}

ExpoViewProps::ExpoViewProps(
  const react::PropsParserContext &context,
  const ExpoViewProps &sourceProps,
  const react::RawProps &rawProps,
  [[maybe_unused]] const std::function<bool(const std::string &)> &filterObjectKeys
)
#if EXPO_VIEW_PROPS_SUPPORTS_FILTER_OBJECT_KEYS
  : react::ViewProps(context, sourceProps, rawProps, filterObjectKeys),
#else
  : react::ViewProps(context, sourceProps, rawProps),
#endif
#ifndef EXPO_JSI_VIEW_PROPS
    // Without JSI decoding, `propsMap` is the only carrier of props, so build it here from the
    // `folly::dynamic` lowering. With JSI decoding enabled, the component descriptor's
    // `cloneProps` owns `propsMap` instead: it skips this (expensive) lowering entirely for
    // views that decode straight from JSI, and only populates `propsMap` for the views that
    // still need it (non-JSI-backed props, or views that don't JSI-decode, e.g. SwiftUI).
    propsMap(propsMapFromProps(sourceProps, rawProps)),
#endif
    disableForceFlatten(react::convertRawProp(
      context, rawProps, "disableForceFlatten", sourceProps.disableForceFlatten, false)) {}

} // namespace expo
