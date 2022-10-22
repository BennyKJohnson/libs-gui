//
//  NSAutoresizingMaskLayoutConstraint.h
//  GSAutoLayoutEngine
//
//  Created by Benjamin Johnson on 18/10/22.
//

#import <Foundation/NSGeometry.h>
#import <AppKit/NSView.h>
#import <AppKit/NSLayoutConstraint.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAutoresizingMaskLayoutConstraint : NSLayoutConstraint

+(NSArray*)constraintsWithAutoresizingMask:(NSAutoresizingMaskOptions)autoresizingMask subitem:(NSView*)subItem frame:(NSRect)frame superitem:(NSView*)superItem bounds:(NSRect)bounds;
@end

NS_ASSUME_NONNULL_END
