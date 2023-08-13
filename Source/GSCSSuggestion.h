#import <Foundation/Foundation.h>
#import "GSCSVariable.h"

#ifndef _GS_CS_SUGGESTION_H
#define _GS_CS_SUGGESTION_H

@interface GSCSSuggestion : NSObject

@property (nonatomic, strong) GSCSVariable *variable;

@property double value;

- (instancetype)initWithVariable: (GSCSVariable*)variable value: (double)value;

@end

#endif
