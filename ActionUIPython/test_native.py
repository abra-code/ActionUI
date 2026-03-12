#!/usr/bin/env python3
"""
Simple example using ActionUI native Python extension.
Demonstrates basic usage without AppKit/window management.
"""

import actionui
import json

def main():
    print("ActionUI Python Native Extension Example")
    print("=" * 50)
    
    # Check version
    version = actionui.get_version()
    print(f"ActionUI Version: {version}")
    print()
    
    # Create application
    app = actionui.Application()
    
    # Track state
    state = {
        'clicks': 0,
        'name': '',
        'enabled': True
    }
    
    # Register action handlers
    @app.action("button.click")
    def on_button_click(ctx: actionui.ActionContext):
        print(f"\n[ACTION] Button clicked!")
        print(f"  View ID: {ctx.view_id}")
        print(f"  Window: {ctx.window_uuid}")
        
        state['clicks'] += 1
        
        # Get window and update UI
        window_uuid = ctx.window_uuid
        # In real app, you'd look up the window object
        # For now, we'll use the native API directly
        import _actionui
        _actionui.set_int_value(window_uuid, 4, state['clicks'], 0)
        _actionui.set_string_value(window_uuid, 7, f"Clicks: {state['clicks']}", 0)
        
        print(f"  Total clicks: {state['clicks']}")
    
    @app.action("textfield.changed")
    def on_text_changed(ctx: actionui.ActionContext):
        print(f"\n[ACTION] Text changed in view {ctx.view_id}")
        
        import _actionui
        value = _actionui.get_string_value(ctx.window_uuid, ctx.view_id, 0)
        state['name'] = value or ''
        
        print(f"  New value: {state['name']}")
        
        # Update greeting
        if state['name']:
            greeting = f"Hello, {state['name']}!"
        else:
            greeting = "Enter your name above"
        
        _actionui.set_string_value(ctx.window_uuid, 7, greeting, 0)
    
    @app.action("toggle.changed")
    def on_toggle_changed(ctx: actionui.ActionContext):
        print(f"\n[ACTION] Toggle changed")
        
        import _actionui
        value = _actionui.get_bool_value(ctx.window_uuid, ctx.view_id, 0)
        state['enabled'] = value
        
        print(f"  New state: {state['enabled']}")
    
    # Set default handler for debugging
    def default_handler(ctx: actionui.ActionContext):
        print(f"\n[UNHANDLED] Action: {ctx.action_id}")
        print(f"  View: {ctx.view_id}, Window: {ctx.window_uuid}")
        if ctx.context:
            print(f"  Context: {ctx.context}")
    
    app.set_default_handler(default_handler)
    
    # Create UI definition
    ui_def = {
        "type": "VStack",
        "id": 1,
        "properties": {
            "spacing": 20,
            "padding": 20
        },
        "children": [
            {
                "type": "Text",
                "id": 2,
                "properties": {
                    "content": "ActionUI Native Example",
                    "font": "largeTitle"
                }
            },
            {
                "type": "TextField",
                "id": 3,
                "properties": {
                    "prompt": "Enter your name",
                    "actionID": "textfield.changed"
                }
            },
            {
                "type": "Button",
                "id": 5,
                "properties": {
                    "title": "Click Me!",
                    "actionID": "button.click"
                }
            },
            {
                "type": "Text",
                "id": 7,
                "properties": {
                    "content": "Enter your name above",
                    "font": "headline",
                    "foregroundColor": "blue"
                }
            },
            {
                "type": "Toggle",
                "id": 8,
                "properties": {
                    "title": "Enable feature",
                    "value": True,
                    "actionID": "toggle.changed"
                }
            }
        ]
    }
    
    print("\nCreating window (no URL — value tests use arbitrary view IDs)...")

    # Window.from_file / Window.from_url require a running app with a real URL.
    # For unit-testing the value store we only need a UUID; view_ptr stays None.
    window = actionui.Window()

    print(f"Window UUID: {window.uuid}")
    print(f"View pointer: {window.view_ptr} (None — no URL loaded)")
    
    # Note: type-specific set/get operations require view elements to exist in
    # ActionUI's model (i.e. a UI must be loaded via Window.from_file or
    # Window.from_url first).  Without a loaded UI the calls succeed silently
    # but getters return None because no ViewModel exists for the view ID.
    #
    # The calls below verify that the API is reachable without crashing; value
    # round-trip assertions belong in an integration test with a real NSWindow.
    print("\n" + "=" * 50)
    print("API reachability check (no UI loaded — getters return None)")
    print("=" * 50)

    window.set_int(100, 42)
    print(f"set_int(100, 42)       -> get_int(100)    = {window.get_int(100)}")

    window.set_double(101, 3.14159)
    print(f"set_double(101, 3.14) -> get_double(101)  = {window.get_double(101)}")

    window.set_bool(102, True)
    print(f"set_bool(102, True)   -> get_bool(102)    = {window.get_bool(102)}")

    window.set_string(103, "Hello, World!")
    print(f"set_string(103, ...)  -> get_string(103)  = {window.get_string(103)}")

    window.set_value(104, 100)
    window.set_value(105, 2.718)
    window.set_value(106, False)
    window.set_value(107, "Test")
    window.set_value(108, {"key": "value", "num": 123})
    window.set_value(109, [1, 2, 3, "four"])
    print(f"set_value / get_value (int):    {window.get_value(104)}")
    print(f"set_value / get_value (float):  {window.get_value(105)}")
    print(f"set_value / get_value (bool):   {window.get_value(106)}")
    print(f"set_value / get_value (str):    {window.get_value(107)}")
    print(f"set_value / get_value (dict):   {window.get_value(108)}")
    print(f"set_value / get_value (list):   {window.get_value(109)}")

    print("\n" + "=" * 50)
    print("Smoke test passed — API layer is reachable.")
    print("=" * 50)

    print("\nTo run a full integration test, integrate with AppKit:")
    print("  1. Create NSWindow")
    print("  2. Load UI via Window.from_file('ui.json')")
    print("  3. Set view_ptr as the window's contentView")
    print("  4. Run NSApplication event loop")

    print("\nExample ready for integration!")


if __name__ == "__main__":
    main()
