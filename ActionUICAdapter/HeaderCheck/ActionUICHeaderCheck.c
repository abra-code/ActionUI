// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUICHeaderCheck.c
//  ActionUICAdapter
//
//  Adds no code. It includes the hand-written ActionUIC.h and the Swift-generated
//  ActionUICAdapter-Swift.h together, so each @c function is declared twice; a parameter or
//  return type that differs between the two declarations is a "conflicting types" error, and
//  the build fails. A function on one side only compiles here: Scripts/check-c-prototypes.sh
//  checks the names.
//
//  Built by the Xcode framework target (this folder is part of it); for package builds,
//  Scripts/check-c-prototypes.sh --generated-headers compiles it.
//

#include "../include/ActionUIC.h"
#if __has_include(<ActionUICAdapter/ActionUICAdapter-Swift.h>)
#include <ActionUICAdapter/ActionUICAdapter-Swift.h>     // Xcode framework build
#else
#include "ActionUICAdapter-Swift.h"                      // Scripts/check-c-prototypes.sh
#endif
