// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIAppHeaderCheck.c
//  ActionUIAppKitApplication
//
//  Adds no code. It includes the hand-written ActionUIApp.h and the Swift-generated header of
//  the application functions together, so each @c function is declared twice; a parameter or
//  return type that differs between the two declarations is a "conflicting types" error, and
//  the build fails. A function on one side only compiles here: Scripts/check-c-prototypes.sh
//  checks the names.
//
//  Built by the Xcode framework target on Apple platforms (this folder is part of it); on
//  Linux Scripts/check-c-prototypes.sh --generated-headers compiles it, against
//  ActionUIAdwaitaApplication.
//

#include "../include/ActionUIApp.h"
#if __has_include(<ActionUIAppKitApplication/ActionUIAppKitApplication-Swift.h>)
#include <ActionUIAppKitApplication/ActionUIAppKitApplication-Swift.h>  // Xcode framework build
#elif defined(__APPLE__)
#include "ActionUIAppKitApplication-Swift.h"                            // Scripts/check-c-prototypes.sh
#else
#include "ActionUIAdwaitaApplication-Swift.h"
#endif
