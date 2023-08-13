#import "GSCSSuggestion.h"

@implementation GSCSSuggestion

- (instancetype)initWithVariable: (GSCSVariable*)variable value: (double)value
{
    self = [super init];
    if (self) {
        self.variable = variable;
        self.value = value;
    }
    return self;
}

-(void)dealloc
{
    RELEASE(_variable);
    [super dealloc];
}

@end
