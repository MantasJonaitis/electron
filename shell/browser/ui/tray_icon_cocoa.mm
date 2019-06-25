// Copyright (c) 2014 GitHub, Inc.
// Use of this source code is governed by the MIT license that can be
// found in the LICENSE file.

#include "shell/browser/ui/tray_icon_cocoa.h"

#include <string>
#include <vector>

// #include "base/mac/sdk_forward_declarations.h"
#include "base/strings/sys_string_conversions.h"
// #include "shell/browser/mac/atom_application.h"
// #include "shell/browser/ui/cocoa/NSString+ANSI.h"
#include "shell/browser/ui/cocoa/atom_menu_controller.h"
// #include "ui/display/screen.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
// #include "ui/gfx/image/image.h"
#include "ui/gfx/mac/coordinate_conversion.h"

@interface StatusItemView : NSView {
  electron::TrayIconCocoa* trayIcon_;   // weak
  AtomMenuController* menuController_;  // weak
  // electron::TrayIcon::HighlightMode highlight_mode_;
  // BOOL ignoreDoubleClickEvents_;
  // BOOL forceHighlight_;
  // BOOL inMouseEventSequence_;
  // BOOL ANSI_;
  // base::scoped_nsobject<NSImage> image_;
  // base::scoped_nsobject<NSImage> alternateImage_;
  // base::scoped_nsobject<NSString> title_;
  // base::scoped_nsobject<NSMutableAttributedString> attributedTitle_;
  base::scoped_nsobject<NSStatusItem> statusItem_;
  base::scoped_nsobject<NSTrackingArea> trackingArea_;
}

@end  // @interface StatusItemView

@implementation StatusItemView

- (void)dealloc {
  trayIcon_ = nil;
  menuController_ = nil;
  [super dealloc];
}

// - (void)drawRect:(NSRect)todoRect {
//   // set any NSColor for filling, say white:
//   // [[NSColor redColor] setFill];
//   // NSRectFill(todoRect);
//   [super drawRect:todoRect];
// }

- (id)initWithIcon:(electron::TrayIconCocoa*)icon {
  trayIcon_ = icon;
  menuController_ = nil;
  trackingArea_.reset();
  // highlight_mode_ = electron::TrayIcon::HighlightMode::SELECTION;
  // ignoreDoubleClickEvents_ = NO;
  // forceHighlight_ = NO;
  // inMouseEventSequence_ = NO;

  if ((self = [super initWithFrame:CGRectZero])) {
    // [self registerForDraggedTypes:@[
    //   NSFilenamesPboardType,
    //   NSStringPboardType,
    // ]];

    // Create the status item.
    NSStatusItem* item = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    statusItem_.reset([item retain]);
    [[statusItem_ button] addSubview:self];  // inject custom view
    // NSView* superview = [[statusItem_ button] superview];
    // [[superview superview] addSubview:self];
    [self updateDimensions];
  }
  return self;
}

- (void)updateDimensions {
  [self setFrame:[statusItem_ button].frame];

  LOG(INFO) << "button bounds: "
            << [NSStringFromRect([statusItem_ button].bounds) UTF8String];
  LOG(INFO) << "button frame: "
            << [NSStringFromRect([statusItem_ button].frame) UTF8String];
  LOG(INFO) << "self bounds: " << [NSStringFromRect(self.bounds) UTF8String];
  LOG(INFO) << "self frame: " << [NSStringFromRect(self.frame) UTF8String];
  // LOG(INFO) << "tracking rect: " <<
  // [NSStringFromRect(trackingArea_.get().rect) UTF8String];
}

- (void)updateTrackingAreas {
  // NSTrackingArea used for listening to mouseEnter, mouseExit, and mouseMove
  // events. Update tracking area size.
  [self removeTrackingArea:trackingArea_];
  trackingArea_.reset([[NSTrackingArea alloc]
      initWithRect:[self bounds]
           options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                   NSTrackingActiveAlways
             owner:self
          userInfo:nil]);
  [self addTrackingArea:trackingArea_];
  LOG(INFO) << "update tracking rect: "
            << [NSStringFromRect(trackingArea_.get().rect) UTF8String];
}

- (void)removeItem {
  // Turn off tracking events to prevent crash
  if (trackingArea_) {
    [self removeTrackingArea:trackingArea_];
    trackingArea_.reset();
  }
  [[NSStatusBar systemStatusBar] removeStatusItem:statusItem_];
  [self removeFromSuperview];
  statusItem_.reset();
}

- (void)setImage:(NSImage*)image {
  [[statusItem_ button] setImage:image];  // TODO: or [image copy] ?
  [self updateDimensions];
}

- (void)setAlternateImage:(NSImage*)image {
  [[statusItem_ button] setAlternateImage:image];  // TODO: or [image copy] ?
}

- (void)setToolTip:(NSString*)toolTip {
  [[statusItem_ button] setToolTip:toolTip];  // TODO: or [toolTip copy] ?
}

- (void)setTitle:(NSString*)title {
  [[statusItem_ button] setTitle:title];  // TODO: or [title copy] ?

  // Fix icon margins.
  if (title.length == 0) {
    [[statusItem_ button] setImagePosition:NSImageOnly];
  } else {
    [[statusItem_ button] setImagePosition:NSImageLeft];
  }

  [self updateDimensions];
}

- (NSString*)title {
  return [statusItem_ button].title;
}

- (void)setMenuController:(AtomMenuController*)menu {
  menuController_ = menu;
}

- (void)mouseDown:(NSEvent*)event {
  LOG(INFO) << "Mouse down";

  // [statusItem_ popUpStatusItemMenu:[menuController_ menu]];
  // [[menuController_ menu] popUpMenuPositioningItem:nil atLocation:NSZeroPoint
  // inView:[statusItem_ button]]; [theMenu popUpMenuPositioningItem:nil
  // atLocation:[NSEvent mouseLocation] inView:nil];

  [super mouseDown:event];
}

- (void)mouseExited:(NSEvent*)event {
  trayIcon_->NotifyMouseExited(
      gfx::ScreenPointFromNSPoint([event locationInWindow]),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

- (void)mouseEntered:(NSEvent*)event {
  trayIcon_->NotifyMouseEntered(
      gfx::ScreenPointFromNSPoint([event locationInWindow]),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

- (void)mouseMoved:(NSEvent*)event {
  trayIcon_->NotifyMouseMoved(
      gfx::ScreenPointFromNSPoint([event locationInWindow]),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

@end

namespace electron {

TrayIconCocoa::TrayIconCocoa() {
  status_item_view_.reset([[StatusItemView alloc] initWithIcon:this]);
}

TrayIconCocoa::~TrayIconCocoa() {
  LOG(INFO) << "~TrayIconCocoa()";
  [status_item_view_ removeItem];
  if (menu_model_)
    menu_model_->RemoveObserver(this);
}

void TrayIconCocoa::SetImage(const gfx::Image& image) {
  [status_item_view_ setImage:image.IsEmpty() ? nil : image.AsNSImage()];
}

void TrayIconCocoa::SetPressedImage(const gfx::Image& image) {
  [status_item_view_
      setAlternateImage:image.IsEmpty() ? nil : image.AsNSImage()];
}

void TrayIconCocoa::SetToolTip(const std::string& tool_tip) {
  [status_item_view_ setToolTip:base::SysUTF8ToNSString(tool_tip)];
}

void TrayIconCocoa::SetTitle(const std::string& title) {
  [status_item_view_ setTitle:base::SysUTF8ToNSString(title)];
}

std::string TrayIconCocoa::GetTitle() {
  return base::SysNSStringToUTF8([status_item_view_ title]);
}

void TrayIconCocoa::SetHighlightMode(TrayIcon::HighlightMode mode) {
  // [status_item_view_ setHighlight:mode];
}

void TrayIconCocoa::SetIgnoreDoubleClickEvents(bool ignore) {
  // [status_item_view_ setIgnoreDoubleClickEvents:ignore];
}

bool TrayIconCocoa::GetIgnoreDoubleClickEvents() {
  // return [status_item_view_ getIgnoreDoubleClickEvents];
  return false;
}

void TrayIconCocoa::PopUpContextMenu(const gfx::Point& pos,
                                     AtomMenuModel* menu_model) {
  // [status_item_view_ popUpContextMenu:menu_model];
}

void TrayIconCocoa::SetContextMenu(AtomMenuModel* menu_model) {
  // Subscribe to MenuClosed event.
  if (menu_model_)
    menu_model_->RemoveObserver(this);

  menu_model_ = menu_model;

  if (menu_model) {
    menu_model->AddObserver(this);
    // Create native menu.
    menu_.reset([[AtomMenuController alloc] initWithModel:menu_model
                                    useDefaultAccelerator:NO]);
  } else {
    menu_.reset();
  }

  [status_item_view_ setMenuController:menu_.get()];
}

gfx::Rect TrayIconCocoa::GetBounds() {
  return gfx::ScreenRectFromNSRect([status_item_view_ bounds]);
}

// void TrayIconCocoa::OnMenuWillClose() {
//   [status_item_view_ setNeedsDisplay:YES];
// }

// static
TrayIcon* TrayIcon::Create() {
  return new TrayIconCocoa;
}

}  // namespace electron
