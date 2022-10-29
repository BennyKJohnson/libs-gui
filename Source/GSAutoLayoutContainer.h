#import <AppKit/NSLayoutConstraint.h>

@interface GSAutoLayoutContainer : NSObject
{
  NSLayoutConstraint *_widthConstraint;
  NSLayoutConstraint *_heightConstraint;
}

- (NSLayoutConstraint*) widthConstraint;
- (void) setWidthConstraint: (NSLayoutConstraint*)widthConstraint;

- (NSLayoutConstraint*) heightConstraint;
- (void) setHeightConstraint: (NSLayoutConstraint*)heightConstraint;

@end
