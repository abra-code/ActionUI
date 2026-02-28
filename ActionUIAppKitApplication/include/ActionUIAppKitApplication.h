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

#import <Foundation/Foundation.h>

//! Project version number for ActionUIAppKitApplication.
FOUNDATION_EXPORT double ActionUIAppKitApplicationVersionNumber;

//! Project version string for ActionUIAppKitApplication.
FOUNDATION_EXPORT const unsigned char ActionUIAppKitApplicationVersionString[];

#if __has_include(<ActionUIAppKitApplication/ActionUIApp.h>)
    #import <ActionUIAppKitApplication/ActionUIApp.h>   // Xcode framework build
#else
    #import "ActionUIApp.h"                             // SPM build
#endif
