#import "GSAutoLayoutContainer.h"

@implementation GSAutoLayoutContainer

- (NSLayoutConstraint*) widthConstraint
{
    return _widthConstraint;
}

- (void) setWidthConstraint: (NSLayoutConstraint*)widthConstraint
{
    _widthConstraint = widthConstraint;
}

- (NSLayoutConstraint*) heightConstraint
{
    return _heightConstraint;
}

- (void) setHeightConstraint: (NSLayoutConstraint*)heightConstraint
{
    _heightConstraint = heightConstraint;
}

@end
