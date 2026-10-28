// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIAppKitApplication.h
//  ActionUIAppKitApplication
//
//  Umbrella header for ActionUIAppKitApplication framework.
//
//  Plain C, like ActionUIApp.h: when modules are off, the Swift-generated
//  ActionUIAppKitApplication-Swift.h includes this header, so a plain C client of that header
//  compiles it too.
//

#ifndef ActionUIAppKitApplication_h
#define ActionUIAppKitApplication_h

#ifdef __cplusplus
extern "C" {
#endif

//! Project version number for ActionUIAppKitApplication.
extern double ActionUIAppKitApplicationVersionNumber;

//! Project version string for ActionUIAppKitApplication.
extern const unsigned char ActionUIAppKitApplicationVersionString[];

#ifdef __cplusplus
}
#endif

#if __has_include(<ActionUIAppKitApplication/ActionUIApp.h>)
    #include <ActionUIAppKitApplication/ActionUIApp.h>   // Xcode framework build
#else
    #include "ActionUIApp.h"                             // SPM build
#endif

#endif
