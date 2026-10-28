// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUICAdapter.h
//  ActionUICAdapter
//
//  Umbrella header for ActionUICAdapter framework.
//
//  Plain C, like ActionUIC.h: when modules are off, the Swift-generated ActionUICAdapter-Swift.h
//  includes this header, so a plain C client of that header compiles it too.
//

#ifndef ActionUICAdapter_h
#define ActionUICAdapter_h

#ifdef __cplusplus
extern "C" {
#endif

//! Project version number for ActionUICAdapter.
extern double ActionUICAdapterVersionNumber;

//! Project version string for ActionUICAdapter.
extern const unsigned char ActionUICAdapterVersionString[];

#ifdef __cplusplus
}
#endif

// Include the C interface
#if __has_include(<ActionUICAdapter/ActionUIC.h>)
    #include <ActionUICAdapter/ActionUIC.h>   // Xcode framework build
#else
    #include "ActionUIC.h"                    // SPM build
#endif

#endif
